import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";
import {
  promoteCandidateWithFlag,
  restorePrimaryRoute,
} from "../support/routed-rollout";

// Tech-doc 009's Experience Release Procedure steps 2-3: repeat the
// candidate/revision/readiness promotion sequence with the flag flipped on,
// then use two `test-user-` contexts against that now-routed candidate to
// prove draft, offline queue, reconnect, catch-up, FIFO drain, and
// exact-once rendering. Both members open the room only *after* promotion:
// `require_family_chat_enabled/2` (user_auth.ex) returns a genuine 404 while
// the flag is off, so a member can never be "in the room" on a flag-off
// slot -- there is nothing to reconnect *from*. The room is a plain Phoenix
// controller, never a LiveView (tech-doc 005), so it reuses
// `family-chat.steps.ts`'s own real readiness signal
// (`data-connection-state`) rather than `[data-phx-main]`.

const { Given, Then, When } = createBdd();

const DRAFT_MESSAGE = "Queued before the experience release promotion";
let identity: TestIdentity;
let memberAPage: Page;
let memberBContext: BrowserContext;
let memberBPage: Page;
let interceptSend = false;

Given(
  "Caddy has promoted the flag-enabled experience candidate",
  async ({ page, $testInfo }) => {
    interceptSend = false;
    memberAPage = page;
    // Identity seeding writes into the authoritative (not-yet-activated)
    // storage; it must complete before `promoteCandidateWithFlag`'s
    // `ensureLiveSqlite()` activates the routed-rollout storage authority,
    // mirroring every other routed-rollout scenario's ordering.
    identity = isolatedTestIdentity($testInfo);
    const rollout = await promoteCandidateWithFlag(page, true);
    expect(rollout.revision).not.toBe(rollout.previousRevision);

    // `fetch_current_user/2` (user_auth.ex) unconditionally touches
    // `StorageCoordinator.active_backend/1` on every request, even an
    // unauthenticated one. That coordinator's cold-start check-and-restart
    // (storage_coordinator.ex's `ensure_started!/1`) is not itself
    // serialized: two real requests racing through it as the *first* caller
    // on a freshly promoted candidate can tear down the Ecto repo pid one
    // of them is mid-migration-check against (a genuine, independently
    // reproduced production race -- see learnings.md). One throwaway
    // request here forces that one-time cold start to resolve
    // deterministically before either member's real login begins.
    await page.request.get("/login");
  },
);

Given("two members each open {string}", async ({ browser }, route: string) => {
  await memberAPage.route("**/api/graphql", async (routeHandle) => {
    const body = routeHandle.request().postData() ?? "";
    if (interceptSend && body.includes("SendFamilyChatMessage")) {
      await routeHandle.abort("connectionfailed");
      return;
    }
    await routeHandle.continue();
  });
  await memberAPage.context().clearCookies();
  await login(memberAPage, identity.admin);
  await memberAPage.goto(route);
  await expect(
    memberAPage.locator('[data-role="family-chat-room"]'),
  ).toHaveAttribute("data-connection-state", "ready", { timeout: 10_000 });
  // "ready" flips before the room's own background mount work (the push-
  // subscription check, the GraphQL subscribe) has necessarily settled --
  // those are genuinely concurrent requests that can still be racing
  // `StorageCoordinator.ensure_started!/1`'s one-time cold start on this
  // freshly promoted candidate. Letting member A's page go network-idle
  // before member B's own first request starts avoids two authenticated
  // "first requests" overlapping on that cold start.
  await memberAPage.waitForLoadState("networkidle");

  memberBContext = await browser.newContext();
  try {
    memberBPage = await memberBContext.newPage();
    await login(memberBPage, identity.child);
    await memberBPage.goto(route);
    await expect(
      memberBPage.locator('[data-role="family-chat-room"]'),
    ).toHaveAttribute("data-connection-state", "ready", { timeout: 10_000 });
  } catch (error) {
    await memberBContext.close();
    throw error;
  }
});

Given("one member queues a message while offline", async () => {
  interceptSend = true;
  await memberAPage.getByLabel("Message").fill(DRAFT_MESSAGE);
  await memberAPage.getByRole("button", { name: "Send" }).click();
  await expect(
    memberAPage.locator("[data-role=family-chat-outbox-status]"),
  ).toContainText("Retrying");
});

When("the offline member's connection is restored", async () => {
  interceptSend = false;
  await memberAPage.evaluate(() => window.dispatchEvent(new Event("online")));
});

Then(
  "the offline member's queued message drains exactly once after reconnect",
  async () => {
    await expect(
      memberAPage.locator("[data-role=family-chat-outbox-status]"),
    ).not.toContainText("Retrying", { timeout: 10_000 });
    await expect(
      memberAPage.locator("[data-role=family-chat-message]", {
        hasText: DRAFT_MESSAGE,
      }),
    ).toHaveCount(1);
  },
);

Then("neither member sees a duplicate or lost message", async () => {
  try {
    await expect(
      memberBPage.locator("[data-role=family-chat-message]", {
        hasText: DRAFT_MESSAGE,
      }),
    ).toHaveCount(1, { timeout: 10_000 });
    await expect(
      memberAPage.locator("[data-role=family-chat-message]", {
        hasText: DRAFT_MESSAGE,
      }),
    ).toHaveCount(1);
  } finally {
    await memberBContext.close();
    await restorePrimaryRoute(memberAPage);
  }
});
