import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  boxOf,
  CLEAR,
  openOptionsIfCollapsed,
  TOUCH_TARGET_PX,
  viewportOf,
} from "../support/chat-ui-steps";

// The options-panel contents scenarios of chat.feature. Split out of
// codex-phone-layout.steps.ts to stay under the repository's 300-line
// step-file budget. The conversation-budget, header, and panel-positioning
// scenarios stay in codex-phone-layout.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex options panel holds the model, the effort and Clear chat

const { Then, When } = createBdd();

When("the visitor opens the Codex options panel", async ({ page }) => {
  await openOptionsIfCollapsed(page);
});

Then(
  "the model selector is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator("#model-selector")).toBeVisible();
  },
);

Then(
  "the reasoning effort selector is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator("#effort-selector")).toBeVisible();
  },
);

Then(
  "the Clear chat control is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator(CLEAR)).toBeVisible();
  },
);

Then("the options panel is no wider than the screen", async ({ page }) => {
  const box = await boxOf(page.locator(".chat-actions"), "the options panel");
  expect(box.width).toBeLessThanOrEqual(viewportOf(page).width);
});

Then(
  "every options panel control is at least 44 pixels tall",
  async ({ page }) => {
    const selectors = ["#model-selector", "#effort-selector", CLEAR];
    const boxes = await Promise.all(
      selectors.map((selector) => boxOf(page.locator(selector), selector)),
    );
    for (const [index, box] of boxes.entries()) {
      expect(box.height, `${selectors[index]} height`).toBeGreaterThanOrEqual(
        TOUCH_TARGET_PX,
      );
    }
  },
);
