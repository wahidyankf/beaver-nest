import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { ensureCandidate } from "../support/candidate-pool";
import { instanceIdentities } from "../support/instance-identities";
import { candidatePort } from "../support/routed-rollout-env";
import { restorePrimaryRoute } from "../support/routed-rollout";

// Step bindings for the phase-8 FE ADD rows about the chat room itself:
// the shared transcript, the Family chat flag, signing out, and runner
// failures. Each binding proves its scenario through the real browser
// against the real server.

const { Given, Then, When, After } = createBdd();

// E2E bindings for the phase-8 FE ADD rows about the chat room itself:
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A conversation continues in another tab or browser of the same user
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home hides the Sifat Allah mission entry and keeps the chat entry
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home shows Family chat only when the room is enabled
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

// --- Family chat flag (BN-HOME-03) ------------------------------------------

// The flag-off candidate is opened directly instead of routed through Caddy,
// which this host does not install: the room flag is server-rendered, so the
// origin needs only to be the flag-off server itself.
let candidateBaseURL: string | undefined;

Given("family chat is {string}", async ({ page }, setting: string) => {
  candidateBaseURL = undefined;
  if (setting === "enabled") {
    await restorePrimaryRoute(page);
    return;
  }
  await ensureCandidate(candidatePort, false);
  // `localhost`, not `127.0.0.1`: the endpoint's `check_origin` only allows
  // the configured `localhost` host, so the LiveView socket from a
  // `127.0.0.1` page origin is refused and the room never connects. No Caddy
  // is involved at this layer: the flag-off candidate is opened directly.
  candidateBaseURL = `http://localhost:${candidatePort}`;
  await page.goto(`${candidateBaseURL}/login`);
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  const identity = instanceIdentities().admin;
  await page.getByLabel("Username").fill(identity.username);
  await page.getByLabel("Password").fill(identity.password);
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/", { timeout: 15_000 }),
    page.getByRole("button", { name: "Log in" }).click(),
  ]);
});

When("a visitor opens the home page", async ({ page }) => {
  await page.goto(`${candidateBaseURL ?? ""}/`);
});

Then(
  "the page does not offer the {string} link to {string}",
  async ({ page }, label: string, linkPath: string) => {
    await expect(
      page.locator(`a[href="${linkPath}"]`).filter({ hasText: label }),
    ).toHaveCount(0);
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
