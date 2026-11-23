import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { sendThroughComposer } from "../support/family-chat-delivery";

// Step bindings for the phase-8 FE ADD rows in family_chat.feature: the
// unknown room slug and the empty room state, proved through the real
// browser against the real server.

const { Given, Then, When } = createBdd();

// E2E bindings for the phase-8 FE ADD rows in family_chat.feature:
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: An unknown room slug is a plain not found response
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room shows an empty state before any message
// --- Unknown room slug (BN-HTTP-18) ---

Then(
  "the room answers not found with the body {string}",
  async ({ page }, body: string) => {
    await expect(page.locator("body")).toHaveText(body);
  },
);

Then("the room reveals no room name", async ({ page }) => {
  await expect(page.locator("body")).not.toContainText("Ruang Keluarga");
});

// --- Empty family room (BN-FAM-01) -----------------------------------------------

Given(
  "a visitor opens {string} with no messages",
  async ({ page }, route: string) => {
    await page.goto(route);
    await expect(
      page.locator('[data-role="family-chat-room"]'),
    ).toHaveAttribute("data-connection-state", "ready");
  },
);

Then("the room shows {string}", async ({ page }, text: string) => {
  await expect(page.locator('[data-role="family-chat-empty"]')).toContainText(
    text,
  );
});

When("the first message arrives", async ({ page }) => {
  await sendThroughComposer(page, "Hello from home");
});

Then("the empty state notice is gone", async ({ page }) => {
  await expect(page.locator('[data-role="family-chat-empty"]')).toBeHidden();
});
