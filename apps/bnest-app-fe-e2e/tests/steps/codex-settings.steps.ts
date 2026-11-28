import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { openOptionsIfCollapsed } from "../support/chat-ui-steps";

const { Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A model change falls back to Max from an unsupported reasoning effort
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A child, or a child administrator, is limited to read-only Luna at medium effort
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A parent chooses Luna or Terra at medium effort
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: An administrator turns repository writes on and off
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Repository access returns to read-only after a reload or after clearing the chat
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor opens a fresh chat

const modelIdsByName: Record<string, string> = {
  "GPT-6.1-Sol": "gpt-6.1-sol",
  "GPT-6.1 Terra": "gpt-6.1-terra",
  "GPT-6-Luna": "gpt-6-luna",
};

const supportedEfforts: Record<string, string[]> = {
  "gpt-6.1-sol": ["Low", "Medium", "High", "XHigh", "Max", "Ultra"],
  "gpt-6.1-terra": ["Low", "Medium", "High", "XHigh", "Max", "Ultra"],
  "gpt-6-luna": ["Low", "Medium", "High", "XHigh", "Max"],
};

// The names are listed in the picker's order, separated by ", ". The admin's picker lists the latest Sol, Terra and
// Luna highest tier first, whatever order Codex lists them in (ADR 006).
Then(
  "the model selector lists only {string}",
  async ({ page }, names: string) => {
    await expect(page.getByLabel("Model").locator("option")).toHaveText(
      names.split(", "),
    );
  },
);

Then("the selected model is {string}", async ({ page }, model: string) => {
  const modelId = modelIdsByName[model];
  if (!modelId) throw new Error(`No fixture model id for ${model}`);
  const selector = page.getByLabel("Model");
  if (await selector.count()) await expect(selector).toHaveValue(modelId);
  await expect(
    page.locator(`.model-badge[data-model="${modelId}"]`),
  ).toBeVisible();
});

Then(
  "the reasoning effort selector lists every effort supported by the selected model",
  async ({ page }) => {
    const modelId = await page.getByLabel("Model").inputValue();
    const efforts = supportedEfforts[modelId];

    if (!efforts) {
      throw new Error(`No fixture efforts configured for model ${modelId}`);
    }

    await expect(
      page.getByLabel("Reasoning effort").locator("option"),
    ).toHaveText(efforts);
  },
);

Then(
  "the selected reasoning effort is {string}",
  async ({ page }, effort: string) => {
    const value = effort.toLowerCase();
    const selector = page.getByLabel("Reasoning effort");
    if (await selector.count()) await expect(selector).toHaveValue(value);
    await expect(
      page.locator(`.model-badge[data-reasoning-effort="${value}"]`),
    ).toBeVisible();
  },
);

Then("the model selector is available", async ({ page }) => {
  await expect(page.getByLabel("Model")).toBeEnabled();
});

Then("the model selector is unavailable", async ({ page }) => {
  await expect(page.getByLabel("Model")).toBeDisabled();
});

Then("the model selector is not shown", async ({ page }) => {
  await expect(page.getByLabel("Model")).toHaveCount(0);
});

Then("the reasoning effort selector is available", async ({ page }) => {
  await expect(page.getByLabel("Reasoning effort")).toBeEnabled();
});

Then("the reasoning effort selector is unavailable", async ({ page }) => {
  await expect(page.getByLabel("Reasoning effort")).toBeDisabled();
});

Then("the reasoning effort selector is not shown", async ({ page }) => {
  await expect(page.getByLabel("Reasoning effort")).toHaveCount(0);
});

Then("repository access is shown as read-only", async ({ page }) => {
  await expect(
    page.locator("[data-role=repository-access][data-mode=read-only]"),
  ).toContainText("Repo read-only");
});

Then("repository access is shown as write enabled", async ({ page }) => {
  await expect(
    page.locator("[data-role=repository-access][data-mode=workspace-write]"),
  ).toContainText("Repo write enabled");
});

Then("the repository write control is available", async ({ page }) => {
  await expect(
    page.locator("[data-role=repository-write-toggle]"),
  ).toBeEnabled();
});

Then("the repository write control is not shown", async ({ page }) => {
  await expect(page.locator("[data-role=repository-write-toggle]")).toHaveCount(
    0,
  );
});

When("the visitor enables repository writes", async ({ page }) => {
  await page.getByRole("button", { name: "Enable repo writes" }).click();
});

When("the visitor disables repository writes", async ({ page }) => {
  await page.getByRole("button", { name: "Disable repo writes" }).click();
});

When(
  "the visitor selects the model {string}",
  async ({ page }, model: string) => {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    // On a phone the model and effort selects sit in the collapsed Options panel (ADR 005).
    await openOptionsIfCollapsed(page);
    const selector = page.getByLabel("Model");
    await selector.selectOption({ label: model });
    const modelId = await selector
      .locator("option:checked")
      .getAttribute("value");
    expect(modelId).not.toBeNull();
    await expect(
      page.locator(`.model-badge[data-model="${modelId}"]`),
    ).toBeVisible();
  },
);

When(
  "the visitor selects the reasoning effort {string}",
  async ({ page }, effort: string) => {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    await openOptionsIfCollapsed(page);
    const selector = page.getByLabel("Reasoning effort");
    await selector.selectOption({ label: effort });
    const value = effort.toLowerCase();
    await expect(
      page.locator(`.model-badge[data-reasoning-effort="${value}"]`),
    ).toBeVisible();
  },
);
