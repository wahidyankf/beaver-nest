import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Completed browser migration is not offered from the home page

Then("the page does not offer browser-data migration", async ({ page }) => {
  await expect(page.locator("[data-role=data-migration-entry]")).toHaveCount(0);
});
