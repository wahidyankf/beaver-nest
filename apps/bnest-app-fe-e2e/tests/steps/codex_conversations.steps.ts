import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// Step bindings for the Multiple chat conversations rule of
// specs/apps/bnest/app-fe/behaviours/chat.feature: the rail the server renders,
// with one entry per conversation.
const { Then, When } = createBdd();

When("the visitor starts a new chat", async ({ page }) => {
  await page.getByRole("button", { name: "New chat" }).click();
  await expect(
    page
      .locator("[data-role=select-conversation]")
      .filter({ hasText: "New chat" }),
  ).toBeVisible();
});

Then(
  "the conversation list shows {string}",
  async ({ page }, title: string) => {
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: title }),
    ).toBeVisible();
  },
);

Then(
  "the conversation list does not show {string}",
  async ({ page }, title: string) => {
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: title }),
    ).toHaveCount(0);
  },
);

When(
  "the visitor opens the conversation {string}",
  async ({ page }, title: string) => {
    await page
      .locator("[data-role=select-conversation]")
      .filter({ hasText: title })
      .click();
    await expect(page).toHaveURL(/conversation=/u);
  },
);

When(
  "the visitor deletes the conversation {string}",
  async ({ page }, title: string) => {
    const item = page
      .locator("[data-role=conversation-item]")
      .filter({ hasText: title });
    await item.getByRole("button", { name: "Delete" }).click();
    await expect(item).toHaveCount(0);
  },
);
