import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// Step bindings for the Multiple chat conversations rule of
// specs/apps/bnest/app-fe/behaviours/chat.feature: the rail the server renders,
// with one entry per conversation.
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor starts a second chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor switches between two chats and each keeps its messages
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor deletes a chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor renames a chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor keeps every chat after a reload
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
    // The rail delete is an icon button: its accessible name carries the
    // action, so the locator keys off the stable data-role hook instead.
    await item.locator("[data-role=delete-conversation]").click();
    await expect(item).toHaveCount(0);
  },
);

When(
  "the visitor renames the conversation {string} to {string}",
  async ({ page }, title: string, next: string) => {
    const item = page
      .locator("[data-role=conversation-item]")
      .filter({ hasText: title });
    await item.locator("[data-role=rename-toggle]").click();
    await item.locator("[data-role=rename-input]").fill(next);
    await item.locator("[data-role=rename-submit]").click();
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: next }),
    ).toBeVisible();
  },
);
