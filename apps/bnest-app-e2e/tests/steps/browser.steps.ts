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

When("a visitor opens {string}", async ({ page }, route: string) => {
  await page.goto(route);
});

Then("the page displays the Beaver Nest logo", async ({ page }) => {
  await expect(page.getByAltText("Beaver Nest logo")).toBeVisible();
});

Then("Beaver Nest is ready to install as an app", async ({ page }) => {
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
    "href",
    "/manifest.webmanifest",
  );

  const manifest = await page.evaluate(async () => {
    const response = await fetch("/manifest.webmanifest");
    return response.json() as Promise<{
      name: string;
      display: string;
      icons: Array<{ src: string; sizes: string }>;
    }>;
  });

  expect(manifest.name).toBe("Beaver Nest");
  expect(manifest.display).toBe("standalone");
  expect(manifest.icons).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        src: "/images/beaver-nest-192.png",
        sizes: "192x192",
      }),
      expect.objectContaining({
        src: "/images/beaver-nest-512.png",
        sizes: "512x512",
      }),
    ]),
  );

  await expect
    .poll(() =>
      page.evaluate(async () => {
        const registration = await navigator.serviceWorker.ready;
        return registration.active?.scriptURL ?? "";
      }),
    )
    .toMatch(/\/service-worker\.js$/u);
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
  "the page offers the {string} link to {string}",
  async ({ page }, label: string, path: string) => {
    await expect(page.getByRole("link", { name: label })).toHaveAttribute(
      "href",
      path,
    );
  },
);

When("the visitor follows the Beaver Nest home link", async ({ page }) => {
  const homeLink = page.getByRole("link", { name: "Beaver Nest home" });
  await expect(homeLink).toHaveAttribute("href", "/");
  await homeLink.click();
  await expect(page).toHaveURL(/\/$/u);
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

When("the visitor reconnects after a deployment", ({ page }) => page.reload());

When("the visitor reloads the page", ({ page }) => page.reload());

When("the visitor clears the chat", async ({ page }) => {
  await page.getByRole("button", { name: "Clear chat" }).click();
});
