import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then } = createBdd();

Then("the home header and hero do not overlap", async ({ page }) => {
  const header = page.locator(".home-header");
  const hero = page.locator(".home-hero");
  await expect(header).toBeVisible();
  await expect(hero).toBeVisible();

  const [headerBox, heroBox] = await Promise.all([
    header.boundingBox(),
    hero.boundingBox(),
  ]);
  expect(headerBox).not.toBeNull();
  expect(heroBox).not.toBeNull();
  if (!headerBox || !heroBox) throw new Error("Expected home layout boxes");

  expect(headerBox.y + headerBox.height).toBeLessThanOrEqual(heroBox.y);
});
