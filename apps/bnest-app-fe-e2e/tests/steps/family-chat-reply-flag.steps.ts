import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { ensureRoomOpen } from "../support/family-chat-reply-room";
import { LIST, MESSAGE } from "../support/family-chat-keyboard";
import {
  promoteCandidateWithReplyFlag,
  restorePrimaryRoute,
} from "../support/routed-rollout";

// family_chat.feature, Rule "Message actions": the actions control is drawn only when the room is served with replies.
// The compatibility build (reply flag off) is routed as a candidate; the global After hook restores the primary route.

const { Given, Then } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Messages have an actions control exactly when replies are on

const MORE = '[data-role="family-chat-message-more"]';

Given(
  "the room is served with replies turned {word}",
  async ({ page }, setting: string) => {
    if (setting === "off") {
      await ensureRoomOpen(page);
      await promoteCandidateWithReplyFlag(page, false);
      return;
    }
    await restorePrimaryRoute(page);
  },
);

Then("no message in the history has an actions control", async ({ page }) => {
  await expect
    .poll(() => page.locator(`${LIST} ${MESSAGE}`).count(), {
      message: "the history has messages",
    })
    .toBeGreaterThan(0);
  expect(
    await page.locator(`${LIST} ${MORE}`).count(),
    "actions controls drawn in the history",
  ).toBe(0);
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
