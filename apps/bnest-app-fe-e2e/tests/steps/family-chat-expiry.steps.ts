import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  attemptsFor,
  expectCommitted,
  interfereWithSends,
  pendingRow,
  pendingRowId,
  sendThroughComposer,
  stopInterfering,
} from "../support/family-chat-delivery";
import {
  expectStored,
  storedRowFor,
} from "../support/family-chat-outbox-store";
import { waitForRoomReady } from "../support/family-chat-resume";
import { uniqueBody } from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";

// family_chat.feature's seven-day expiry in a real browser: messages queued
// on a device whose clock then moves on more than a week, reopened, left
// alone by the automatic retry, and still the member's to retry or discard.
// Split from `family-chat-delivery.steps.ts` for this project's line budget.

const { Given, Then } = createBdd();

const DAY_MS = 24 * 60 * 60 * 1000;
const QUIET_WINDOW_MS = 3_500;
const ROOM_ROUTE = "/family-chat/ruang-keluarga";

let expiredIds: string[] = [];
let attemptsAtReopen: number[] = [];
let expiredBodies: string[] = [];

// --- Seven-day expiry ------------------------------------------------------

Given(
  "the visitor has a queued message created more than seven days ago",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    // The device's own clock is set eight days back while the messages are
    // queued, then forward to today -- the member closed the app and came
    // back a week and a day later.
    await page.clock.install({ time: Date.now() - 8 * DAY_MS });
    await page.reload();
    await waitForRoomReady(page);
    await interfereWithSends(page, "abort");
    expiredBodies = [uniqueBody("Old retry"), uniqueBody("Old discard")];
    for (const body of expiredBodies) {
      // eslint-disable-next-line no-await-in-loop -- composed one after another, as a member would.
      await sendThroughComposer(page, body);
      // eslint-disable-next-line no-await-in-loop -- each must be written through before the session ends.
      await expectStored(page, body);
    }
    await page.goto("about:blank");
    await stopInterfering(page);
    await page.clock.setSystemTime(Date.now());
  },
);

Then("the message is not automatically retried", async ({ page }) => {
  await page.waitForURL(`**${ROOM_ROUTE}`);
  expiredIds = await Promise.all(
    expiredBodies.map((body) => pendingRowId(page, body)),
  );
  // Everything these messages ever sent was in the session that queued them.
  attemptsAtReopen = expiredBodies.map(
    (body) => attemptsFor(page, body).length,
  );
  await page.waitForTimeout(QUIET_WINDOW_MS);
  for (const [index, body] of expiredBodies.entries()) {
    expect(attemptsFor(page, body)).toHaveLength(attemptsAtReopen[index] ?? -1);
    // eslint-disable-next-line no-await-in-loop -- each row is read on its own.
    await expect(pendingRow(page, body)).toHaveAttribute(
      "data-delivery-state",
      "Couldn't send",
    );
  }
});

Then("the visitor can still manually retry or discard it", async ({ page }) => {
  const [retryBody, discardBody] = expiredBodies;
  const [retryId, discardId] = expiredIds;
  if (!retryBody || !discardBody || !retryId || !discardId) {
    throw new Error("the expired messages were not found");
  }
  await page
    .locator(`[data-message-id="${retryId}"]`)
    .getByRole("button", { name: "Retry" })
    .click();
  await expectCommitted(page, retryBody);

  page.once("dialog", (dialog) => {
    void dialog.accept();
  });
  await page
    .locator(`[data-message-id="${discardId}"]`)
    .getByRole("button", { name: "Discard" })
    .click();
  await expect(pendingRow(page, discardBody)).toHaveCount(0);
  await expect(
    page.locator('[data-role="family-chat-live-region"]'),
  ).toHaveText("Message discarded.");
  await expect
    .poll(async () => (await storedRowFor(page, discardBody)) === undefined)
    .toBe(true);
  expect(attemptsFor(page, discardBody)).toHaveLength(
    attemptsAtReopen[1] ?? -1,
  );
});
