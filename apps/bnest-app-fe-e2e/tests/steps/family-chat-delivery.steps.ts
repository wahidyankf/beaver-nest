import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  attemptsFor,
  delivery,
  expectCommitted,
  interfereWithSends,
  expectRowStatus,
  pendingRow,
  sendThroughComposer,
  stopInterfering,
} from "../support/family-chat-delivery";
import {
  currentUserId,
  expectStored,
  roomNamespace,
  storedOutboxRows,
} from "../support/family-chat-outbox-store";
import { waitForRoomReady } from "../support/family-chat-resume";
import { uniqueBody } from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";

// family_chat.feature's delivery rules in a real browser: a send's status,
// a rejected send, the per-room queue bound, resuming a closed session's
// queue, the online event, the backoff sequence, and the seven-day expiry (in
// `family-chat-expiry.steps.ts`). Each
// is the real room's outbox against the real server, with only the network
// between them changed (`interfereWithSends`).

const { Given, Then, When } = createBdd();

const BACKOFF_BASES_MS = [1_000, 2_000, 4_000, 8_000, 16_000];
// Time between the browser's request and this process seeing it, either
// side of a wait.
const OBSERVATION_SLACK_MS = 400;
const QUIET_WINDOW_MS = 3_500;

let onlineAt = 0;
let attemptsBeforeOnline = 0;

/** Holds the scenario until `count` sends of `body` have been attempted. */
async function awaitAttempts(
  page: Parameters<typeof attemptsFor>[0],
  body: string,
  count: number,
  timeout: number,
): Promise<void> {
  await expect
    .poll(() => attemptsFor(page, body).length, { timeout })
    .toBeGreaterThanOrEqual(count);
}

// --- Online send status ----------------------------------------------------

When(
  "the visitor sends the family chat message {string}",
  async ({ page }, body: string) => {
    await waitForRoomReady(page);
    // A slow network, so "Sending" is on screen long enough to be read.
    await interfereWithSends(page, 2_000);
    await sendThroughComposer(page, body);
  },
);

When(
  "the visitor sends a family chat message the server rejects as invalid",
  async ({ page }) => {
    await waitForRoomReady(page);
    await interfereWithSends(page, "reject");
    await sendThroughComposer(page, uniqueBody("Rejected send"));
  },
);

Then("no automatic retry is attempted", async ({ page }) => {
  const attempts = attemptsFor(page, delivery.body);
  expect(attempts.map((attempt) => attempt.errorCode)).toEqual([
    "VALIDATION_FAILED",
  ]);
  // Longer than the first two retry waits together could ever be.
  await page.waitForTimeout(QUIET_WINDOW_MS);
  expect(attemptsFor(page, delivery.body)).toHaveLength(1);
  await expectRowStatus(page, delivery.body, "Couldn't send");
});

// --- Bounded per-room outbox ----------------------------------------------

Given(
  "the visitor's outbox for this room already holds {int} queued messages",
  async ({ page }, count: number) => {
    await waitForRoomReady(page);
    await interfereWithSends(page, "abort");
    const prefix = uniqueBody("Queued");
    for (let index = 0; index < count; index += 1) {
      // eslint-disable-next-line no-await-in-loop -- each message is composed and sent before the next, as a member would.
      await sendThroughComposer(page, `${prefix} ${index}`);
    }
    const namespace = roomNamespace(await currentUserId(page));
    await expect
      .poll(
        async () =>
          (await storedOutboxRows(page)).filter(
            (row) => row.namespace === namespace,
          ).length,
        { timeout: 30_000 },
      )
      .toBe(count);
  },
);

When("the visitor attempts to queue one more message", async ({ page }) => {
  await sendThroughComposer(page, uniqueBody("One more message"));
});

Then("the new message is not queued", async ({ page }) => {
  await expect(pendingRow(page, delivery.body)).toHaveCount(0);
  const namespace = roomNamespace(await currentUserId(page));
  const rows = (await storedOutboxRows(page)).filter(
    (row) => row.namespace === namespace,
  );
  expect(rows).toHaveLength(100);
  expect(rows.some((row) => row.body === delivery.body)).toBe(false);
  expect(attemptsFor(page, delivery.body)).toHaveLength(0);
});

Then(
  "the composer explains the retry-or-discard remediation",
  async ({ page }) => {
    const remediation = page.locator('[data-role="family-chat-remediation"]');
    await expect(remediation).toBeVisible();
    await expect(remediation).toContainText(/retry/iu);
    await expect(remediation).toContainText(/discard/iu);
  },
);

// --- Resume and the online event ------------------------------------------

Given(
  "the visitor has a queued message left over from a closed session",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    await interfereWithSends(page, "abort");
    await sendThroughComposer(page, uniqueBody("Left over"));
    await expectStored(page, delivery.body);
    // The session ends: its document, and every timer and socket it held,
    // are gone before the network comes back.
    await page.goto("about:blank");
    await stopInterfering(page);
  },
);

Then(
  "the queued message resumes toward Sent without visitor action",
  async ({ page }) => {
    await expectCommitted(page, delivery.body);
  },
);

Given("a queued message is waiting on its backoff timer", async ({ page }) => {
  await waitForRoomReady(page);
  await interfereWithSends(page, "abort");
  await sendThroughComposer(page, uniqueBody("Backing off"));
  // Four failures: the next automatic try is 8 s (at least 6.4 s) away.
  await awaitAttempts(page, delivery.body, 4, 20_000);
  await stopInterfering(page);
});

When(
  "the browser reports the {string} event",
  async ({ page }, event: string) => {
    // The browser's own connectivity flips, so the event the room hears is
    // the one Chromium fires, not one dispatched by the test. Coming back
    // online is the only event this can produce.
    expect(event).toBe("online");
    attemptsBeforeOnline = attemptsFor(page, delivery.body).length;
    await page.context().setOffline(true);
    await page.context().setOffline(false);
    onlineAt = Date.now();
  },
);

Then(
  "the queued message becomes immediately eligible for retry",
  async ({ page }) => {
    const before = attemptsBeforeOnline;
    await awaitAttempts(page, delivery.body, before + 1, 2_000);
    const retry = attemptsFor(page, delivery.body)[before];
    const lastFailure = attemptsFor(page, delivery.body)[before - 1];
    if (!retry || !lastFailure) throw new Error("no retry was attempted");
    expect(retry.at - onlineAt).toBeLessThan(1_500);
    // Well before the earliest moment the backoff timer could have fired.
    expect(retry.at - lastFailure.at).toBeLessThan(0.8 * 8_000);
    await expectCommitted(page, delivery.body);
  },
);

When(
  "a queued message fails five times with a retryable result",
  async ({ page }) => {
    await waitForRoomReady(page);
    await interfereWithSends(page, "abort");
    await sendThroughComposer(page, uniqueBody("Five failures"));
    await awaitAttempts(page, delivery.body, 6, 60_000);
  },
);

Then(
  "each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds",
  ({ page }) => {
    const times = attemptsFor(page, delivery.body).map((attempt) => attempt.at);
    const waits = BACKOFF_BASES_MS.map(
      (_base, index) => (times[index + 1] ?? 0) - (times[index] ?? 0),
    );
    for (const [index, base] of BACKOFF_BASES_MS.entries()) {
      const wait = waits[index] ?? 0;
      expect(
        wait,
        `wait ${index + 1} of ${JSON.stringify(waits)}`,
      ).toBeGreaterThanOrEqual(0.8 * base - OBSERVATION_SLACK_MS);
      expect(
        wait,
        `wait ${index + 1} of ${JSON.stringify(waits)}`,
      ).toBeLessThanOrEqual(
        Math.min(1.2 * base, 60_000) + OBSERVATION_SLACK_MS,
      );
    }
  },
);
