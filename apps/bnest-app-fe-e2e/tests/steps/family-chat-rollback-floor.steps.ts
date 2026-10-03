import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  delivery,
  expectCommitted,
  sendAttempts,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomReady } from "../support/family-chat-resume";
import { promoteCandidateWithReplyFlag } from "../support/routed-rollout";
import { messageById } from "../support/family-chat-gestures";
import {
  expectMenuOpenFor,
  openMenuItems,
  openMenuWithKeyboard,
  postMessage,
  QUOTE,
  REPLY_STRIP,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";

// AC-FCR-13's two release scenarios: a browser holding an older bundle while
// the routed slot changes beneath it. Neither ever navigates after the route
// moves. `reloadRoute` only rewrites Caddy's upstream and polls readiness
// over `page.request`, so the document, its bundle, and its socket are the
// ones loaded before the route moved, and everything the Thens judge is that
// held bundle talking to the newly routed revision.
//
// Everything is driven from the visitor's own page. An earlier version seeded
// through a second browser context, which had to log in against a slot that
// had just booted; that returned `Internal Server Error` often enough to make
// the scenario worthless. The proof does not need a second member.

/** The reply committed after the rollback -- the one the floor itself answered. */
let floorReplyId = "";
/** The revision whose bundle the page holds, and the one routed after it. */
let heldRevision = "";
let routedRevision = "";

const { Given, Then, When } = createBdd();

function navigationCount(page: Page): Promise<number> {
  return page.evaluate(() => performance.getEntriesByType("navigation").length);
}

/**
 * Also the gate before any reload that follows a promotion: the room loads its
 * history once and never retries, so a reload into the churn window sits at
 * "booting" for good -- the held page, still open, can ask first.
 *
 * A promotion swaps the process behind the routed port, and `/health/ready`
 * answering with the new revision does not mean that process can reach SQLite
 * yet: the repo's pool can still be tearing down, and a request that lands in
 * that window comes back `Internal Server Error` with
 * `DBConnection.Holder.checkout ... (EXIT) shutdown` in the slot's log. It is
 * the harness's slot churn, not the room -- a plain send fails there just as a
 * reply does. So wait until the routed slot will actually answer a
 * database-backed read before asking it to commit anything.
 */
async function waitForRoutedReads(page: Page, revision: string): Promise<void> {
  await expect
    .poll(
      () =>
        page.evaluate(async (expected) => {
          const probe = async (): Promise<boolean> => {
            const response = await fetch("/api/graphql", {
              method: "POST",
              credentials: "same-origin",
              headers: {
                "content-type": "application/json",
                "x-csrf-token":
                  document.querySelector<HTMLMetaElement>(
                    "meta[name='csrf-token']",
                  )?.content ?? "",
              },
              body: JSON.stringify({
                query:
                  "query Probe($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug, limit: 1) { nodes { id } } }",
                variables: { roomSlug: "ruang-keluarga" },
              }),
            });
            if (!response.ok) return false;
            // Answered by the revision just routed, not one still draining.
            if (response.headers.get("x-bnest-revision") !== expected)
              return false;
            const payload = (await response.json()) as { errors?: unknown };
            return payload.errors === undefined;
          };
          // Side by side, so the browser's other pooled connections to the
          // origin are asked too: the next real request may not reuse this one.
          const answers = await Promise.all(
            Array.from({ length: 6 }, () => probe().catch(() => false)),
          );
          return answers.every(Boolean);
        }, revision),
      { timeout: 20_000 },
    )
    .toBe(true);
}

/**
 * Reloads into the routed room. The page itself comes from the slot just
 * routed, and a slot still settling can answer that one request with an error
 * page that has no room in it; reloading again is what a person would do.
 */
async function reloadRoutedRoom(page: Page): Promise<void> {
  const room = page.locator('[data-role="family-chat-room"]');
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop -- each reload is judged on its own result.
    await page.reload();
    // eslint-disable-next-line no-await-in-loop -- see above.
    const loaded = await room
      .waitFor({ state: "attached", timeout: 5_000 })
      .then(() => true)
      .catch(() => false);
    if (loaded) break;
  }
  await waitForRoomReady(page);
}

// --- The compatibility revision ------------------------------------------
//
// The page loads the room from a revision routed with the reply flag off --
// a bundle that never asks for or sends a reply, the closest this suite can
// hold to one built before replies existed -- and keeps it while the
// compatibility revision (also flag off, a different build) is routed.

Given("the compatibility revision is routed", async ({ page, $testInfo }) => {
  await ensureRoomOpen(page, $testInfo);
  ({ revision: heldRevision } = await promoteCandidateWithReplyFlag(
    page,
    false,
  ));
  await waitForRoutedReads(page, heldRevision);
  await reloadRoutedRoom(page);
  ({ revision: routedRevision } = await promoteCandidateWithReplyFlag(
    page,
    false,
  ));
  expect(routedRevision).not.toBe(heldRevision);
});

When(
  "a browser loaded from the previous revision opens {string}",
  async ({ page }, route: string) => {
    // Already open, from before the promotion: the held page is the browser.
    expect(new URL(page.url()).pathname).toBe(route);
    expect(await navigationCount(page)).toBe(1);
    await waitForRoomReady(page);
    await waitForRoutedReads(page, routedRevision);
  },
);

Then("the room loads", async ({ page }) => {
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
  );
  // The feature is off, so neither surface is bound; the room is otherwise
  // exactly the shipped one.
  await expect(page.locator(REPLY_STRIP)).toHaveAttribute("hidden", /.*/u);
});

Then("the visitor can send a message normally", async ({ page }) => {
  const sent = page.waitForResponse((response) =>
    (response.request().postData() ?? "").includes("SendFamilyChatMessage"),
  );
  await sendThroughComposer(page, uniqueBody("Compatibility send"));
  // Answered by the newly routed revision, through the held bundle.
  expect((await sent).headers()["x-bnest-revision"]).toBe(routedRevision);
  await expectCommitted(page, delivery.body);
  expect(await navigationCount(page)).toBe(1);
});

// --- The rollback floor ----------------------------------------------------

Given(
  "a visitor holds the reply-aware bundle with a reply on screen",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);

    // Seeded before any promotion, against the slot already serving. The
    // server stores `replyToMessageId` whatever the flag says; only the
    // browser's willingness to ask for it back is gated.
    scenario.targetBody = uniqueBody("Rollback original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);

    const { revision } = await promoteCandidateWithReplyFlag(page, true);
    await waitForRoutedReads(page, revision);
    await reloadRoutedRoom(page);
    await waitForRoutedReads(page, revision);

    scenario.replyId = await postMessage(
      page,
      uniqueBody("Rollback reply"),
      scenario.targetId,
    );
    // Reloading here rather than waiting for the live push: this step only
    // stages the state the scenario acts on, and waiting on a subscription
    // that has just survived a promotion made the setup fail about a third of
    // the time on mobile. The constraint that matters -- never navigating --
    // binds from the rollback onwards, not here.
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toBeVisible();
  },
);

When(
  "the routed slot is rolled back to the compatibility revision",
  async ({ page }) => {
    ({ revision: routedRevision } = await promoteCandidateWithReplyFlag(
      page,
      false,
    ));
    // The route moved under a live socket: the prior slot's connection dies
    // and the browser has to re-subscribe against the floor before it can be
    // asked anything. Without this the next step races the reconnect.
    await waitForRoomReady(page);
    await waitForRoutedReads(page, routedRevision);
  },
);

When(
  "the visitor replies again with the bundle it still holds",
  async ({ page }) => {
    // Asserting the quote already on screen would assert stale DOM -- it was
    // rendered before the rollback and would survive the floor answering with
    // nothing at all. This reply is composed in the held bundle's own UI and
    // committed *after* the rollback, so rendering its quote requires the
    // floor to accept `replyToMessageId` and to serve `replyTo` back with the
    // reply flag off, which is the asymmetry the compatibility release
    // depends on (tech-doc 002).
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
    await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
    await expect(page.locator(REPLY_STRIP)).not.toHaveAttribute(
      "hidden",
      /.*/u,
    );
    const sent = page.waitForResponse((response) =>
      (response.request().postData() ?? "").includes("SendFamilyChatMessage"),
    );
    await sendThroughComposer(page, uniqueBody("Floor reply"));
    expect((await sent).headers()["x-bnest-revision"]).toBe(routedRevision);
    floorReplyId = await expectCommitted(page, delivery.body);
    expect(sendAttempts(page).at(-1)?.replyToMessageId).toBe(scenario.targetId);
  },
);

Then("existing replies still render their quotes", async ({ page }) => {
  // Both: the one rendered before the rollback and the one the floor itself
  // answered with. The second is what makes this more than a stale-DOM check.
  await Promise.all(
    [scenario.replyId, floorReplyId].map(async (id) => {
      const quote = messageById(page, id).locator(QUOTE);
      await expect(quote).toBeVisible();
      await expect(quote).toContainText(scenario.targetBody);
    }),
  );
});
