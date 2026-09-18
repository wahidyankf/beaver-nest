import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

const availableModels =
  "GPT-5.6-Sol,GPT-5.6-Terra,GPT-5.6-Luna,GPT-5.5,GPT-5.4,GPT-5.4-Mini,GPT-5.3-Codex-Spark".split(
    ",",
  );

const supportedEfforts: Record<string, string[]> = {
  "gpt-5.6-sol": ["Low", "Medium", "High", "XHigh", "Max", "Ultra"],
  "gpt-5.6-terra": ["Low", "Medium", "High", "XHigh", "Max", "Ultra"],
  "gpt-5.6-luna": ["Low", "Medium", "High", "XHigh", "Max"],
  "gpt-5.5": ["Low", "Medium", "High", "XHigh"],
  "gpt-5.4": ["Low", "Medium", "High", "XHigh"],
  "gpt-5.4-mini": ["Low", "Medium", "High", "XHigh"],
  "gpt-5.3-codex-spark": ["Low", "Medium", "High", "XHigh"],
};

Then(
  "the model selector lists every available Codex model",
  async ({ page }) => {
    await expect(page.getByLabel("Model").locator("option")).toHaveText(
      availableModels,
    );
  },
);

Then("the selected model is {string}", async ({ page }, model: string) => {
  const modelId = model === "GPT-5.6-Luna" ? "gpt-5.6-luna" : "gpt-5.6-terra";
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
    const selector = page.getByLabel("Reasoning effort");
    await selector.selectOption({ label: effort });
    const value = effort.toLowerCase();
    await expect(
      page.locator(`.model-badge[data-reasoning-effort="${value}"]`),
    ).toBeVisible();
  },
);
