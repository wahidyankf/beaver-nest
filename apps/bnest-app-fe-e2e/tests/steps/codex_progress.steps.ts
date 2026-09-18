import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

When("Codex reports public progress", async ({ page }) => {
  await expect(
    page.locator("[data-role=codex-reasoning-summary]", {
      hasText: "Fixture reasoning summary",
    }),
  ).toBeVisible();
});

Then(
  "the conversation shows the public Codex reasoning summary",
  async ({ page }) => {
    await expect(
      page.locator("[data-role=codex-reasoning-summary]", {
        hasText: "Fixture reasoning summary",
      }),
    ).toBeVisible();
  },
);

Then(
  "the conversation preserves the Codex progress beside the final answer",
  async ({ page }) => {
    await expect(
      page.locator("[data-role=codex-progress-item]", {
        hasText: "Fixture progress",
      }),
    ).toBeVisible();
    await expect(
      page.locator("[data-role=assistant-message]", {
        hasText: "Fixture final answer",
      }),
    ).toBeVisible();
  },
);
