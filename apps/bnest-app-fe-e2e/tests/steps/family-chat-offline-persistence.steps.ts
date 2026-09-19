import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

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

const { Given, Then, When } = createBdd();

// "ruang-keluarga" is one shared room whose message history persists across
// every project/run this suite makes (chromium/tablet-chromium/
// mobile-chromium all exercise this same scenario in the same process) --
// a fixed body text would false-positive-match an earlier run's own already-
// committed message, not just this run's, so each run gets its own.
let offlineMessage = "";

Given("a fresh visitor opens {string}", async ({ page }, route: string) => {
  // Every E2E test worker already gets its own isolated `test-user-`
  // identity per test (`isolatedTestIdentity`, via the Background's own "an
  // approved user is logged in" binding) -- "fresh" only matters for
  // FE_UNIT's shared-process namespace (see that layer's own binding); here
  // it is the same real navigation as the plain opener.
  offlineMessage = `Offline reload probe ${crypto.randomUUID().slice(0, 8)}`;
  await page.goto(route);
});

async function outboxStatusMatches(page: Page, status: string) {
  const indicator = page.locator("[data-role=family-chat-outbox-status]");
  if (status === "Sent") {
    await expect(indicator).toHaveText("", { timeout: 10_000 });
    await expect(
      page.locator('[data-role="family-chat-message"]', {
        hasText: offlineMessage,
      }),
    ).toHaveCount(1);
    return;
  }
  await expect(indicator).toHaveText(status, { timeout: 10_000 });
}

When(
  "the visitor sends a family chat message during a retryable network failure",
  async ({ page }) => {
    // Aborting every `SendFamilyChatMessage` call (rather than
    // `page.context().setOffline`) keeps the rest of the page's own
    // requests -- and the reload this scenario does next -- working
    // normally, mirroring `experience-release.steps.ts`'s established
    // "one member queues a message while offline" technique.
    await page.route("**/api/graphql", async (routeHandle) => {
      const body = routeHandle.request().postData() ?? "";
      if (body.includes("SendFamilyChatMessage")) {
        await routeHandle.abort("connectionfailed");
        return;
      }
      await routeHandle.continue();
    });
    await page.getByLabel("Message").fill(offlineMessage);
    await page.getByRole("button", { name: "Send" }).click();
  },
);

Then("the message shows status {string}", async ({ page }, status: string) => {
  await outboxStatusMatches(page, status);
});

Then(
  "the message reaches status {string}",
  async ({ page }, status: string) => {
    await outboxStatusMatches(page, status);
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
        hasText: offlineMessage,
      }),
    ).toHaveCount(1, { timeout: 10_000 });
    await expect(
      page.locator("[data-role=family-chat-outbox-status]"),
    ).not.toHaveText("", { timeout: 10_000 });
  },
);

When("the network recovers", async ({ page }) => {
  await page.unroute("**/api/graphql");
  await page.evaluate(() => window.dispatchEvent(new Event("online")));
});
