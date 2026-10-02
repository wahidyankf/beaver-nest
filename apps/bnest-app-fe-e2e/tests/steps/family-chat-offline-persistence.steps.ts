import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  delivery,
  expectOutboxStatus,
  interfereWithSends,
  OUTBOX_STATUS,
  sendThroughComposer,
  stopInterfering,
} from "../support/family-chat-delivery";

// family_chat.feature's "Rule: Resume, online reaction, backoff, and
// seven-day expiry" -- "A queued message survives a real browser reload
// while offline" is the one scenario in that rule needing a real browser:
// AC-FC-12's promised cross-reload IndexedDB durability (tech-doc 003) is
// invisible to the frontend Vitest+Gherkin harness (Node has no real
// `indexedDB`), and a real `page.reload()` (browser.steps.ts's "the visitor
// reloads the page") discards the JS module's in-memory outbox state
// exactly like a real closed tab would -- so a message still shown queued
// after reload can only have come back from the browser's own IndexedDB,
// never from memory.
//
// The status Thens here are shared with every delivery scenario
// (`family-chat-delivery.steps.ts`): they judge `delivery.body`, whichever
// step sent it.

const { Given, Then, When } = createBdd();

Given("a fresh visitor opens {string}", async ({ page }, route: string) => {
  // Every E2E test worker already gets its own isolated `test-user-`
  // identity per test (`isolatedTestIdentity`, via the Background's own "an
  // approved user is logged in" binding) -- "fresh" only matters for
  // FE_UNIT's shared-process namespace (see that layer's own binding); here
  // it is the same real navigation as the plain opener.
  await page.goto(route);
});

When(
  "the visitor sends a family chat message during a retryable network failure",
  async ({ page }) => {
    // Aborting every `SendFamilyChatMessage` call (rather than
    // `page.context().setOffline`) keeps the rest of the page's own
    // requests -- and the reload this scenario does next -- working
    // normally, mirroring `experience-release.steps.ts`'s established
    // "one member queues a message while offline" technique.
    await interfereWithSends(page, "abort");
    // "ruang-keluarga" is one shared room whose history persists across
    // every project this suite runs, so each run's body is its own.
    await sendThroughComposer(
      page,
      `Offline reload probe ${crypto.randomUUID().slice(0, 8)}`,
    );
  },
);

Then("the message shows status {string}", async ({ page }, status: string) => {
  await expectOutboxStatus(page, status);
});

Then(
  "the message reaches status {string}",
  async ({ page }, status: string) => {
    await expectOutboxStatus(page, status);
  },
);

Then(
  "the message is durably queued for a closed tab to resume",
  async ({ page }) => {
    // The real proof: a page reload just destroyed and recreated the whole
    // JS runtime (`initRoomFromDocument` re-ran from scratch), so this
    // message being visible and still (re-)resuming at all can only have
    // come from the browser's own IndexedDB, never from the prior runtime's
    // now-gone in-memory outbox namespace.
    await expect(
      page.locator('[data-role="family-chat-message"]', {
        hasText: delivery.body,
      }),
    ).toHaveCount(1, { timeout: 10_000 });
    await expect(page.locator(OUTBOX_STATUS)).not.toHaveText("", {
      timeout: 10_000,
    });
  },
);

When("the network recovers", async ({ page }) => {
  // Both ways a scenario takes the network away are given back: the
  // browser's own offline state, which fires a real `online` event, and the
  // failing sends. Nothing is dispatched by hand; a queue that only drained
  // on a synthetic event would not drain for a member.
  await stopInterfering(page);
  await page.context().setOffline(false);
});
