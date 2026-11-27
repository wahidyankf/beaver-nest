import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { recordSnapshot, setSources } from "../support/centralized-data";
import { currentIdentities, userIdFor } from "../support/instance-identities";

// Bindings for the no-explicit-theme scenario of centralized_data.feature. Split from centralized_data.steps.ts to keep
// each file within the lint line limit.
//
// @scenario specs/apps/bnest/app-be/behaviours/centralized_data.feature: Importing with no explicit browser theme leaves the theme at the system default

const { Given, Then } = createBdd();

let beforeThemeSnapshot = "";

function adminId(): string {
  return userIdFor(currentIdentities().admin.username);
}

Given("the browser has no explicit theme source", async ({ page }) => {
  await setSources(page, { chat: null, learning: null, theme: null });
  beforeThemeSnapshot = recordSnapshot("theme", adminId());
});

Then(
  "Bnest reports the theme import as accepted with nothing for the browser to clear",
  async ({ page }) => {
    await expect(
      page.getByText("Theme preference: accepted and verified"),
    ).toBeVisible();
  },
);

Then("Bnest creates no explicit theme preference", () => {
  expect(recordSnapshot("theme", adminId())).toBe(beforeThemeSnapshot);
});
