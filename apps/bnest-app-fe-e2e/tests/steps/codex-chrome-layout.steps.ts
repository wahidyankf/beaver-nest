import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

import { login } from "../support/authentication";
import { boxOf, CLEAR, openOptionsIfCollapsed } from "../support/chat-ui-steps";
import { instanceIdentities } from "../support/instance-identities";

const { Given, Then } = createBdd();

// The home page header gap (chat.feature, the home page scenario) and the Clear chat hover fill on a touch pointer
// (chat.feature, the Clear chat hover scenario). The Vitest bindings prove the declared CSS; these read painted boxes.

Given("the home page is open at {string}", async ({ page }, spec: string) => {
  const match = /^\w+ (\d+)x(\d+)$/u.exec(spec);
  if (!match) throw new Error(`unreadable viewport ${JSON.stringify(spec)}`);
  await page.setViewportSize({
    width: Number(match[1]),
    height: Number(match[2]),
  });
  await login(page, instanceIdentities().admin);
  await page.goto("/");
});

Then("the header keeps a gap above the hero card", async ({ page }) => {
  const header = await boxOf(page.locator(".home-header"), "the home header");
  const hero = await boxOf(page.locator(".home-hero"), "the hero card");
  expect(
    hero.y - (header.y + header.height),
    "the gap above the hero card",
  ).toBeGreaterThanOrEqual(15.5);
});

// The expectation comes from the scenario's pointer (a Gherkin step), and the page must report that pointer first.
async function hoverFillOf(page: Parameters<typeof openOptionsIfCollapsed>[0]) {
  // On a phone the Clear chat button sits in the Options panel, which stays hidden until the visitor opens it.
  await openOptionsIfCollapsed(page);
  const button = page.locator(CLEAR);
  const rest = await button.evaluate(
    (el) => getComputedStyle(el).backgroundColor,
  );
  await button.hover();
  const hovered = await button.evaluate(
    (el) => getComputedStyle(el).backgroundColor,
  );
  return { rest, hovered };
}

Then("the Clear chat button does not fill on hover", async ({ page }) => {
  const coarse = await page.evaluate(
    () => matchMedia("(pointer: coarse)").matches,
  );
  expect(coarse, "the page does not report a touch pointer").toBe(true);
  const { rest, hovered } = await hoverFillOf(page);
  expect(hovered, "a touch pointer gets no hover fill").toBe(rest);
});

Then("the Clear chat button fills on hover", async ({ page }) => {
  const fine = await page.evaluate(() => matchMedia("(pointer: fine)").matches);
  expect(fine, "the page does not report a fine pointer").toBe(true);
  const { rest, hovered } = await hoverFillOf(page);
  expect(hovered, "the hover fill shows for a fine pointer").not.toBe(rest);
});
