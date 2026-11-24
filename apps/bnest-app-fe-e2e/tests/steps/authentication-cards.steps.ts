import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The setup-card scenarios (BN-SETUP-01) of authentication.feature. Split out
// of authentication.steps.ts to stay under the repository's 300-line
// step-file budget. The redirect, login, logout, return-path, wrong-login,
// cutover, and setup-warning scenarios stay in authentication.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: The setup page adds and removes family member cards

const { Then, When } = createBdd();

When("the setup page is shown", async ({ page }) => {
  const response = await page.goto("/setup");
  expect(response?.status()).toBe(200);
  await expect(
    page.getByRole("heading", { name: "Create the first family accounts" }),
  ).toBeVisible();
});

Then("it opens with one administrator card", async ({ page }) => {
  await expect(page.locator("[data-account-card]")).toHaveCount(1);
  await expect(
    page.locator("[data-account-card] legend").first(),
  ).toContainText("Initial administrator");
});

Then("the first card offers no remove control", async ({ page }) => {
  await expect(
    page
      .locator("[data-account-card]")
      .first()
      .getByRole("button", { name: "Remove this account" }),
  ).toHaveCount(0);
});

Then("it offers to add another initial account", async ({ page }) => {
  await page
    .getByRole("button", { name: "Add another initial account" })
    .click();
  await expect(page.locator("[data-account-card]")).toHaveCount(2);
});

Then("the card template numbers a new family member card", async ({ page }) => {
  await expect(
    page.locator("[data-account-card]").nth(1).locator("[data-account-number]"),
  ).toHaveText("2");
  await expect(page.getByLabel("Username").nth(1)).toBeFocused();
  await page
    .locator("[data-account-card]")
    .nth(1)
    .getByRole("button", { name: "Remove this account" })
    .click();
  await expect(page.locator("[data-account-card]")).toHaveCount(1);
  await expect(
    page.getByRole("button", { name: "Add another initial account" }),
  ).toBeFocused();
});
