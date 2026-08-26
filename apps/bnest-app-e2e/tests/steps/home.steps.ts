import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then } = createBdd();

Then("the page does not offer browser-data migration", async ({ page }) => {
  await expect(page.locator("[data-role=data-migration-entry]")).toHaveCount(0);
});
