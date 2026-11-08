import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  instanceDatabaseDigest,
  login,
  submitInitialAccountsWithSafetyChecks,
  type InitialAccount,
} from "../support/authentication";
import { instanceIdentities } from "../support/instance-identities";

// Trimmed from bnest-app-e2e's authentication.steps.ts to this project's
// owned scenarios (unauthenticated redirect, logged-out home, the
// recovery-warning half of initial setup, and approved login/logout); the
// password-hashing, session-persistence, and multi-session/multi-role/
// cross-user scenarios moved to bnest-app-be-e2e.

const { Given, Then, When } = createBdd();

let setupSafetyChecks = { sawIrreversibleWarning: false };
let databaseBefore = "";

Given("an approved user is logged in", async ({ page }) => {
  await login(page, instanceIdentities().admin);
});

Given("an approved admin is logged in", async ({ page }) => {
  await login(page, instanceIdentities().admin);
});
Given("an approved parent is logged in", async ({ page }) => {
  await login(page, instanceIdentities().parent);
});

Given("an approved child is logged in", async ({ page }) => {
  await login(page, instanceIdentities().child);
});

Given("an approved child administrator is logged in", async ({ page }) => {
  await login(page, instanceIdentities().childAdmin);
});

Given("a visitor has no authenticated Bnest session", async ({ page }) => {
  await page.context().clearCookies();
  databaseBefore = instanceDatabaseDigest();
});

When(
  "the visitor opens the protected route {string}",
  async ({ page }, route: string) => {
    await page.goto(route);
  },
);

Then("Bnest redirects the visitor to login", async ({ page }) => {
  await expect(page).toHaveURL(/\/login\?return_to=/u);
});

Then("the login form replaces protected home actions", async ({ page }) => {
  await expect(page.locator("#login-form")).toBeVisible();
  await expect(page.locator("[data-role=chat-entry]")).toHaveCount(0);
  await expect(page.locator("[data-role=admin-settings-entry]")).toHaveCount(0);
  await expect(page.locator("[data-role=admin-schedules-entry]")).toHaveCount(
    0,
  );
});

Then("Bnest does not read or write user data", ({ page }) => {
  void page;
  expect(instanceDatabaseDigest()).toBe(databaseBefore);
});

Given("Bnest has no bootstrap journal", async ({ page }) => {
  const response = await page.goto("/setup");
  expect(response?.status()).toBe(200);
  await expect(
    page.getByRole("heading", { name: "Create the first family accounts" }),
  ).toBeVisible();
});

When(
  "the maintainer submits all initial accounts including an administrator",
  async ({ page }) => {
    const identities = instanceIdentities();
    const accounts: InitialAccount[] = [
      { ...identities.admin, role: "Parents", admin: true },
      { ...identities.child, role: "Children", admin: false },
      { ...identities.parent, role: "Parents", admin: false },
    ];
    setupSafetyChecks = await submitInitialAccountsWithSafetyChecks(
      page,
      accounts,
    );
  },
);

Then(
  "Bnest warns that later account management and password recovery are unavailable",
  ({ page }) => {
    void page;
    expect(setupSafetyChecks.sawIrreversibleWarning).toBe(true);
  },
);

Then(
  "setup and public registration are unavailable afterward",
  async ({ page }) => {
    expect((await page.request.get("/setup")).status()).toBe(404);
    expect((await page.request.get("/register")).status()).toBe(404);
  },
);

Given("an approved user account exists", async ({ page }) => {
  await page.context().clearCookies();
  await page.goto("/login");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
});

When("the user logs in with valid credentials", async ({ page }) => {
  const { admin } = instanceIdentities();
  await page.getByLabel("Username").fill(admin.username);
  await page.getByLabel("Password").fill(admin.password);
  await page.getByRole("button", { name: "Log in" }).click();
});

Then("the protected home page is available", async ({ page }) => {
  await expect(
    page.getByRole("heading", { name: "Beaver Nest" }),
  ).toBeVisible();
  await expect(page.locator(".home-status")).toContainText(
    instanceIdentities().admin.username,
  );
});

When("the user logs out from that browser", async ({ page }) => {
  await page.getByRole("button", { name: "Log out" }).click();
  // Logging out first clears this member's queued messages from the device, so
  // the form is submitted a moment after the click; a member is logged out once
  // the server's redirect to the login page has landed, not when the button
  // was pressed.
  await page.waitForURL(/\/login$/u);
});

Then("that browser must log in again", async ({ page }) => {
  await page.goto("/chat");
  await expect(page).toHaveURL(/\/login\?return_to=/u);
});
