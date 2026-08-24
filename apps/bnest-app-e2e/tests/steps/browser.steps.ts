import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

const availableModels = [
  "GPT-5.6-Sol",
  "GPT-5.6-Terra",
  "GPT-5.6-Luna",
  "GPT-5.5",
  "GPT-5.4",
  "GPT-5.4-Mini",
  "GPT-5.3-Codex-Spark",
];

When("a visitor opens {string}", async ({ page }, route: string) => {
  await page.goto(route);
});

Then(
  "the page displays the heading {string}",
  async ({ page }, heading: string) => {
    await expect(
      page.getByRole("heading", { exact: true, name: heading }),
    ).toBeVisible();
  },
);

Then("the page displays the text {string}", async ({ page }, text: string) => {
  await expect(page.getByText(text, { exact: true })).toBeVisible();
});

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
  await expect(page.getByLabel("Model")).toHaveValue(modelId);
  await expect(
    page.locator(`.model-badge[data-model="${modelId}"]`),
  ).toBeVisible();
});

Then("the model selector is available", async ({ page }) => {
  await expect(page.getByLabel("Model")).toBeEnabled();
});

Then("the model selector is unavailable", async ({ page }) => {
  await expect(page.getByLabel("Model")).toBeDisabled();
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

Then("the conversation is empty", async ({ page }) => {
  await expect(page.locator("[data-role=message]")).toHaveCount(0);
});

Then("the message composer is available", async ({ page }) => {
  await expect(page.getByLabel("Message")).toBeEnabled();
  await expect(page.locator(".send-button")).toBeEnabled();
});

Then("the message composer is unavailable", async ({ page }) => {
  await expect(page.getByLabel("Message")).toBeDisabled();
  await expect(page.locator(".send-button")).toBeDisabled();
});

Then("the clear chat control is available", async ({ page }) => {
  await expect(page.getByRole("button", { name: "Clear chat" })).toBeEnabled();
});

When("the visitor attempts to send an empty message", async ({ page }) => {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill("   ");
  await page.locator(".send-button").click();
});

When("the visitor sends {string}", async ({ page }, message: string) => {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill(message);
  await page.getByRole("button", { name: "Send" }).click();
});

When(
  "the visitor submits {string} with Shift+Enter",
  async ({ page }, message: string) => {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    const composer = page.getByLabel("Message");
    await composer.fill(message);
    await composer.press("Shift+Enter");
  },
);

When(
  "the visitor attempts to send {string} before Codex finishes",
  async ({ page }, message: string) => {
    const composer = page.getByLabel("Message");
    const sendButton = page.locator(".send-button");

    await expect(composer).toBeDisabled();
    await expect(sendButton).toBeDisabled();
    await composer.fill(message, { force: true });
    await sendButton.click({ force: true });
  },
);

Then(
  "the conversation displays the visitor message {string}",
  async ({ page }, message: string) => {
    await expect(
      page.locator("[data-role=user-message]", { hasText: message }),
    ).toBeVisible();
  },
);

Then(
  "the conversation does not display the visitor message {string}",
  async ({ page }, message: string) => {
    await expect(
      page.locator("[data-role=user-message]", { hasText: message }),
    ).toHaveCount(0);
  },
);

Then("a Codex response appears incrementally", async ({ page }) => {
  const response = page.locator("[data-role=assistant-message]").last();
  await expect(response).toHaveAttribute("data-streaming", "false");
  await expect
    .poll(async () => Number(await response.getAttribute("data-update-count")))
    .toBeGreaterThanOrEqual(2);
});

Then("the conversation displays a second Codex response", async ({ page }) => {
  await expect(page.locator("[data-role=assistant-message]")).toHaveCount(2);
});

Then(
  "the conversation displays one completed Codex response",
  async ({ page }) => {
    await expect(
      page.locator("[data-role=assistant-message][data-streaming=false]"),
    ).toHaveCount(1);
  },
);

When(
  "Codex rejects the visitor message {string}",
  async ({ page }, message: string) => {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    await page.getByLabel("Message").fill(message);
    await page.locator(".send-button").click();
  },
);

When("Codex reports the error {string}", async ({ page }, message: string) => {
  await expect(page.getByRole("alert")).toHaveText(message);
});

Then(
  "the page displays the alert {string}",
  async ({ page }, message: string) => {
    await expect(page.getByRole("alert")).toHaveText(message);
  },
);

When("the visitor reloads the page", async ({ page }) => {
  await page.reload();
});

When("the visitor clears the chat", async ({ page }) => {
  await page.getByRole("button", { name: "Clear chat" }).click();
});
