import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

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

Then("the chat controls do not overlap", async ({ page }) => {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await expect(page.locator(".theme-dock")).toBeHidden();
  await expect(page.locator(".chat-theme-control")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Use dark theme" }),
  ).toBeVisible();

  const controls = page.locator(".chat-actions > *");
  const rectangles = await controls.evaluateAll((elements) =>
    elements.map((element) => {
      const { bottom, height, left, right, top, width } =
        element.getBoundingClientRect();
      return { bottom, height, left, right, top, width };
    }),
  );

  expect(rectangles).toHaveLength(3);

  for (const rectangle of rectangles) {
    expect(rectangle.width).toBeGreaterThan(0);
    expect(rectangle.height).toBeGreaterThan(0);
  }

  for (let index = 0; index < rectangles.length; index += 1) {
    for (let other = index + 1; other < rectangles.length; other += 1) {
      const first = rectangles[index];
      const second = rectangles[other];

      if (!first || !second) {
        throw new Error("Expected chat control rectangles to be present");
      }

      const overlap =
        first.left < second.right &&
        first.right > second.left &&
        first.top < second.bottom &&
        first.bottom > second.top;

      expect(overlap).toBe(false);
    }
  }
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

When(
  "the visitor types {string} without sending",
  async ({ page }, draft: string) => {
    await page.getByLabel("Message").fill(draft);
  },
);

Then(
  "the message composer contains {string}",
  async ({ page }, draft: string) => {
    await expect(page.getByLabel("Message")).toHaveValue(draft);
  },
);

Then("the current route is {string}", async ({ page }, route: string) => {
  await expect(page).toHaveURL(
    new RegExp(`${route.replaceAll("/", "\\/")}$`, "u"),
  );
});

Then(
  "the page displays the alert {string}",
  async ({ page }, message: string) => {
    await expect(page.getByRole("alert")).toHaveText(message);
  },
);

When("the visitor reconnects after a deployment", async ({ page }) => {
  await page.evaluate(() => {
    const liveSocket = (
      window as unknown as { liveSocket: { disconnect: () => void } }
    ).liveSocket;
    liveSocket.disconnect();
  });
  await expect(page.locator("[data-phx-main]")).not.toHaveClass(
    /phx-connected/u,
  );
  await expect(page.locator("[data-phx-main]")).toHaveClass(
    /phx-client-error/u,
  );
  await page.evaluate(() => {
    const liveSocket = (
      window as unknown as { liveSocket: { connect: () => void } }
    ).liveSocket;
    liveSocket.connect();
  });
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
});

When("the visitor reloads the page", ({ page }) => page.reload());

When("the visitor clears the chat", async ({ page }) => {
  await page.getByRole("button", { name: "Clear chat" }).click();
});
