import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { LIST, MESSAGE } from "../support/family-chat-keyboard";
import { restorePrimaryRoute } from "../support/routed-rollout";

// family_chat.feature, Rule "Message actions": the room always serves replies, so every message draws an actions
// control. The global After hook restores the primary route.

const { Given, Then } = createBdd();

const MORE = '[data-role="family-chat-message-more"]';

Given("the room is served with replies turned on", async ({ page }) => {
  await restorePrimaryRoute(page);
});

Then(
  "every message in the history has an actions control",
  async ({ page }) => {
    await expect
      .poll(() => page.locator(`${LIST} ${MESSAGE}`).count(), {
        message: "the history has messages",
      })
      .toBeGreaterThan(0);
    const messages = await page.locator(`${LIST} ${MESSAGE}`).count();
    expect(
      await page.locator(`${LIST} ${MESSAGE} ${MORE}`).count(),
      "messages that have an actions control",
    ).toBe(messages);
  },
);
