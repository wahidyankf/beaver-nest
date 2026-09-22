import { existsSync } from "node:fs";
import { composerInput } from "../support/family-chat";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  chatPayload,
  confirmImports,
  setSources,
  userPath,
} from "../support/centralized-data";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";

// Trimmed from bnest-app-e2e's centralized_data.steps.ts to this project's
// owned scenarios (the browser-key-clearing half of accepted import, and the
// fresh-conversation-report half of Codex-thread resume); the server-side
// persistence scenarios moved to bnest-app-be-e2e.

const { Given, Then, When } = createBdd();

let activeIdentity: TestIdentity;

Given(
  "a recognized browser source and an unrelated browser key exist",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await page.evaluate(() =>
      localStorage.setItem("unrelated.test-key", "keep-me"),
    );
  },
);

When("Bnest accepts and reads back the normalized record", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest clears only the accepted source key", async ({ page }) => {
  expect(
    await page.evaluate(() => sessionStorage.getItem("bnest.chat.v1")),
  ).toBeNull();
  expect(
    await page.evaluate(() => localStorage.getItem("unrelated.test-key")),
  ).toBe("keep-me");
});

Given(
  "centralized chat contains a transcript and an unavailable Codex thread",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, activeIdentity.child);

    const unavailable = JSON.stringify({
      ...JSON.parse(chatPayload),
      thread_id: "unavailable-thread",
      messages: [
        {
          id: 1,
          role: "visitor",
          content: "Original question",
          update_count: 0,
        },
        {
          id: 2,
          role: "assistant",
          content: "Original answer",
          update_count: 1,
        },
      ],
    });
    await setSources(page, { chat: unavailable, learning: null, theme: null });
    await confirmImports(page);
  },
);

When("the authenticated user continues the chat", async ({ page }) => {
  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await composerInput(page).fill("Continue after resume");
  await page.getByRole("button", { name: "Send" }).click();
});

Then("Bnest reports a fresh Codex conversation", async ({ page }) => {
  await expect(page.getByRole("alert")).toContainText(
    "transcript is preserved in a fresh conversation",
  );
  expect(
    existsSync(userPath("chat/current.json", activeIdentity.child.username)),
  ).toBe(true);
});
