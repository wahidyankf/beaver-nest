import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  attemptsFor,
  delivery,
  expectCommitted,
  expectRowStatus,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import {
  expectServiceWorkerControl,
  expectStored,
  storedRowFor,
} from "../support/family-chat-outbox-store";
import {
  expectMenuOpenFor,
  messageById,
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

// Replies queued offline, in a real browser: the browser really is offline
// (`setOffline`, so the room hears the real `offline`/`online` events), the
// queue is the browser's own IndexedDB, and reopening while offline is a real
// navigation the service worker answers.

const { Given, Then, When } = createBdd();

const OFFLINE_BANNER = '[data-role="family-chat-offline-banner"]';

async function goOfflineWithCommittedTarget(
  page: Page,
  testInfo: Parameters<typeof ensureRoomOpen>[1],
): Promise<void> {
  await ensureRoomOpen(page, testInfo);
  scenario.targetBody = uniqueBody("Offline reply target");
  scenario.targetId = await postMessage(page, scenario.targetBody);
  await waitForMessage(page, scenario.targetId);
  // Reopening offline only reaches the app if the worker already controls it.
  await expectServiceWorkerControl(page);
  await page.context().setOffline(true);
  await expect(page.locator(OFFLINE_BANNER)).toBeVisible();
}

async function replyToTarget(page: Page): Promise<void> {
  await openMenuWithKeyboard(page, scenario.targetId);
  await expectMenuOpenFor(page, scenario.targetId);
  await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
  await expect(page.locator(REPLY_STRIP)).not.toHaveAttribute("hidden", /.*/u);
  await sendThroughComposer(page, uniqueBody("Offline reply"));
}

Given("the visitor is offline with the room open", async ({ page, $testInfo }) => {
  await goOfflineWithCommittedTarget(page, $testInfo);
});

When("the visitor replies to a committed message", async ({ page }) => {
  await replyToTarget(page);
});

Given("an offline reply is queued", async ({ page, $testInfo }) => {
  await goOfflineWithCommittedTarget(page, $testInfo);
  await replyToTarget(page);
  await expectRowStatus(page, delivery.body, "Waiting for connection");
  await expectStored(page, delivery.body);
});

Then(
  "the queued message shows status {string}",
  async ({ page }, status: string) => {
    await expectRowStatus(page, delivery.body, status);
    expect(attemptsFor(page, delivery.body)).toHaveLength(0);
  },
);

Then("the queued record carries the reply target", async ({ page }) => {
  const row = await expectStored(page, delivery.body);
  expect(row.replyToMessageId).toBe(scenario.targetId);
});

When(
  "the visitor reopens {string} while still offline",
  async ({ page }, route: string) => {
    await page.goto(route);
  },
);

Then(
  "the queued reply is still present with its target",
  async ({ page }) => {
    // This is the reopened document -- the worker's offline page, since no
    // signed-in page is ever cached -- reading the same origin's IndexedDB.
    await expect(page.getByText("You are offline.")).toBeVisible();
    const row = await storedRowFor(page, delivery.body);
    expect(row?.replyToMessageId).toBe(scenario.targetId);
  },
);

Then(
  "the reply reaches status {string} exactly once",
  async ({ page }, status: string) => {
    // Committing is how a message reaches "Sent"; any other status named
    // here would need its own observation, so it fails closed.
    expect(status).toBe("Sent");
    const committedId = await expectCommitted(page, delivery.body);
    await expect(
      page
        .locator('[data-role="family-chat-message"]')
        .filter({ hasText: delivery.body }),
    ).toHaveCount(1);
    const committed = attemptsFor(page, delivery.body).filter(
      (attempt) => attempt.committedId !== "",
    );
    expect(new Set(committed.map((attempt) => attempt.committedId))).toEqual(
      new Set([committedId]),
    );
    scenario.replyId = committedId;
  },
);

Then("the committed message renders its quote", async ({ page }) => {
  const quote = messageById(page, scenario.replyId).locator(QUOTE);
  await expect(quote).toBeVisible();
  await expect(quote).toContainText(scenario.targetBody.slice(0, 40));
});

Given(
  "the outbox holds a queued message stored with no reply target field",
  async ({ page, $testInfo }) => {
    await goOfflineWithCommittedTarget(page, $testInfo);
    await sendThroughComposer(page, uniqueBody("Plain offline message"));
    // An ordinary message is stored without the key at all
    // (`persistence_indexeddb.js` `toRow`), byte for byte the row a bundle
    // from before replies wrote.
    const row = await expectStored(page, delivery.body);
    expect(Object.hasOwn(row, "replyToMessageId")).toBe(false);
  },
);

Then("that message reaches status {string}", async ({ page }, status: string) => {
  expect(status).toBe("Sent");
  scenario.replyId = await expectCommitted(page, delivery.body);
});

Then("it commits as an ordinary message", async ({ page }) => {
  expect(
    attemptsFor(page, delivery.body).map((attempt) => attempt.replyToMessageId),
  ).not.toContain(scenario.targetId);
  expect(
    attemptsFor(page, delivery.body).every(
      (attempt) => attempt.replyToMessageId === null,
    ),
  ).toBe(true);
  await expect(messageById(page, scenario.replyId).locator(QUOTE)).toHaveCount(
    0,
  );
});
