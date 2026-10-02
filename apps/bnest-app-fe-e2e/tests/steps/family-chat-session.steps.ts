import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { ROOM_ROUTE } from "../support/family-chat";
import {
  attemptsFor,
  delivery,
  expectRowStatus,
  interfereWithSends,
  sendThroughComposer,
  stopInterfering,
} from "../support/family-chat-delivery";
import {
  currentUserId,
  expectStored,
  storedOutboxRows,
  storedRowFor,
} from "../support/family-chat-outbox-store";
import { waitForRoomReady } from "../support/family-chat-resume";
import { uniqueBody } from "../support/family-chat-reply";
import {
  bindPushSubscription,
  identityToken,
  serverPushEnabled,
} from "../support/family-chat-session";
import { isolatedTestIdentity } from "../support/test-identity";

// family_chat.feature's "Rule: Auth expiry pause and logout isolation" in a
// real browser: one device, its one IndexedDB, and the sessions that come
// and go on it.

const { Given, Then, When } = createBdd();

const QUIET_WINDOW_MS = 4_000;

let visitorUserId = "";
let visitorToken = "";
let attemptsAtExpiry = 0;

Given("a message is queued", async ({ page }) => {
  await waitForRoomReady(page);
  visitorUserId = await currentUserId(page);
  await interfereWithSends(page, "abort");
  await sendThroughComposer(page, uniqueBody("Queued for this member"));
  await expectRowStatus(page, delivery.body, "Retrying in …");
  const row = await expectStored(page, delivery.body);
  expect(row.namespace.startsWith(`${visitorUserId}:`)).toBe(true);
});

// --- Authentication expiry -------------------------------------------------

When("the visitor's authentication expires", async ({ page }) => {
  // The identity session ends while the page stays open; the page's own
  // Phoenix session cookie, and with it CSRF, is untouched.
  await page.context().clearCookies({ name: "_bnest_identity" });
  await stopInterfering(page);
  await expect
    .poll(
      () =>
        attemptsFor(page, delivery.body).some(
          (attempt) => attempt.errorCode === "UNAUTHENTICATED",
        ),
      { timeout: 20_000 },
    )
    .toBe(true);
  attemptsAtExpiry = attemptsFor(page, delivery.body).length;
});

Then("queue draining pauses for that namespace", async ({ page }) => {
  // Longer than the next two retry waits could be: a queue that only
  // backed off would have tried again inside it.
  await page.waitForTimeout(QUIET_WINDOW_MS);
  expect(attemptsFor(page, delivery.body)).toHaveLength(attemptsAtExpiry);
  expect(await storedRowFor(page, delivery.body)).toBeDefined();
  await expect(
    page
      .locator('[data-role="family-chat-message"]')
      .filter({ hasText: delivery.body }),
  ).not.toHaveAttribute("data-delivery-state", "committed");
});

Then(
  "no other user's session drains that queued message",
  async ({ page, $testInfo }) => {
    // Another member signs in on the same device and opens the same room.
    await login(page, isolatedTestIdentity($testInfo).child);
    await page.goto(ROOM_ROUTE);
    await waitForRoomReady(page);
    expect(await currentUserId(page)).not.toBe(visitorUserId);
    await page.waitForTimeout(QUIET_WINDOW_MS);
    expect(attemptsFor(page, delivery.body)).toHaveLength(attemptsAtExpiry);
    await expect(
      page
        .locator('[data-role="family-chat-message"]')
        .filter({ hasText: delivery.body }),
    ).toHaveCount(0);
    const row = await storedRowFor(page, delivery.body);
    expect(row?.namespace.startsWith(`${visitorUserId}:`)).toBe(true);
  },
);

// --- Logout ----------------------------------------------------------------

When("the visitor logs out", async ({ page }) => {
  // The session's push binding has to exist for its removal to mean
  // anything; it is made the way the room makes it, and checked through the
  // same server read the Then uses.
  await bindPushSubscription(page);
  visitorToken = await identityToken(page);
  expect(serverPushEnabled(visitorUserId, visitorToken)).toBe(true);

  await page.goto("/");
  await stopInterfering(page);
  expect(
    (await storedOutboxRows(page)).some((row) =>
      row.namespace.startsWith(`${visitorUserId}:`),
    ),
  ).toBe(true);
  await Promise.all([
    page.waitForURL("**/login", { timeout: 15_000 }),
    page.getByRole("button", { name: "Log out" }).click(),
  ]);
});

Then("the visitor's local outbox namespace is cleared", async ({ page }) => {
  const rows = await storedOutboxRows(page);
  expect(
    rows.filter((row) => row.namespace.startsWith(`${visitorUserId}:`)),
  ).toEqual([]);
});

Then("the current session's Web Push subscription is disabled", () => {
  expect(serverPushEnabled(visitorUserId, visitorToken)).toBe(false);
});

// --- Push permission state -------------------------------------------------

Given(
  "the visitor's device reports push state {string}",
  async ({ page }, state: string) => {
    // The one state this browser really is in: headless Chromium answers
    // every notification permission check with "denied". The others are
    // e2e-exempt in the feature for exactly that reason.
    expect(state).toBe("permission denied");
    expect(await page.evaluate(() => Notification.permission)).toBe("denied");
  },
);

Then(
  "the room shows the control {string}",
  async ({ page }, text: string) => {
    await waitForRoomReady(page);
    const control = page.locator('[data-role="family-chat-push-control"]');
    await expect(control).toHaveText(text);
    // Informational: nothing to press, and nothing to turn off.
    await expect(control).toBeDisabled();
    await expect(
      page.locator('[data-role="family-chat-push-disable"]'),
    ).toBeHidden();
  },
);
