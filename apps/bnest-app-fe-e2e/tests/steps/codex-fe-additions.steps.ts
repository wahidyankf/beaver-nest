import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { instanceIdentities } from "../support/instance-identities";

// Step bindings for the phase-8 FE ADD rows about the chat room itself:
// the shared transcript, the Family chat link, signing out, and runner
// failures. Each binding proves its scenario through the real browser
// against the real server.

const { Then, When, After } = createBdd();

// E2E bindings for the phase-8 FE ADD rows about the chat room itself:
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A conversation continues in another tab or browser of the same user
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home hides the Sifat Allah mission entry and keeps the chat entry
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home offers the Family chat link
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A runner exit or invalid runner output shows one fixed line
// --- Second session (BN-DOC-01) --------------------------------------------

let secondContext: import("@playwright/test").BrowserContext | undefined;
let secondPage: import("@playwright/test").Page | undefined;

When(
  "the same user opens {string} in another tab",
  async ({ page: _page, browser }, route: string) => {
    secondContext = await browser.newContext();
    secondPage = await secondContext.newPage();
    await login(secondPage, instanceIdentities().admin);
    await secondPage.goto(route);
    await expect(secondPage.locator("[data-phx-main]")).toHaveClass(
      /phx-connected/u,
    );
  },
);

Then(
  "the other tab shows the visitor message {string}",
  async ({ page: _page }, message: string) => {
    if (secondPage === undefined) throw new Error("no second tab is open");
    await expect(
      secondPage.locator("[data-role=user-message]", { hasText: message }),
    ).toBeVisible();
  },
);

Then("the other tab shows a completed Codex response", async () => {
  if (secondPage === undefined) throw new Error("no second tab is open");
  await expect(
    secondPage.locator("[data-role=assistant-message][data-streaming=false]"),
  ).toHaveCount(1);
});

After(async () => {
  await secondContext?.close();
  secondContext = undefined;
  secondPage = undefined;
});

// --- Family chat link (BN-HOME-03) ------------------------------------------

When("a visitor opens the home page", async ({ page }) => {
  await page.goto("/");
});

Then(
  "the page does not offer the {string} link to {string}",
  async ({ page }, label: string, linkPath: string) => {
    await expect(page.getByRole("link", { name: label })).toHaveCount(0);
    await expect(page.locator(`a[href="${linkPath}"]`)).toHaveCount(0);
  },
);

// --- Sign out (BN-HTTP-14) -------------------------------------------------------

When("the visitor signs out", async ({ page }) => {
  await page.context().clearCookies();
});

// --- Runner failure (BN-CHAT-19) ---------------------------------------------------

When("the runner {string}", async ({ page }, event: string) => {
  const prompt =
    event === "exits with status 3"
      ? "Exit the runner"
      : "Return invalid runner data";
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill(prompt);
  await page.getByRole("button", { name: "Send" }).click();
});

Then(
  "the runner reports {string} to its owner",
  async ({ page }, alert: string) => {
    await expect(page.getByRole("alert")).toHaveText(alert);
  },
);
