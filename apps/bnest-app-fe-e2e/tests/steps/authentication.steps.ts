import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  login,
  runtimeDigest,
  submitInitialAccountsWithSafetyChecks,
  type InitialAccount,
} from "../support/authentication";
import {
  initialTestIdentities,
  isolatedTestIdentity,
  testIdentityForProject,
  userDataRelativePath,
  type TestIdentity,
} from "../support/test-identity";

// Trimmed from bnest-app-e2e's authentication.steps.ts to this project's
// owned scenarios (unauthenticated redirect, logged-out home, the
// recovery-warning half of initial setup, and approved login/logout); the
// password-hashing, session-persistence, and multi-session/multi-role/
// cross-user scenarios moved to bnest-app-be-e2e.

const { Given, Then, When } = createBdd();

let setupSafetyChecks = { sawIrreversibleWarning: false };
let userDataBefore = "";
let activeIdentity: TestIdentity = testIdentityForProject("chromium");

Given("an approved user is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await login(page, activeIdentity.admin);
});

Given("an approved admin is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await login(page, activeIdentity.admin);
});
Given("an approved parent is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await login(page, activeIdentity.parent);
});

Given("an approved child is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await login(page, activeIdentity.child);
});

Given(
  "an approved child administrator is logged in",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await login(page, activeIdentity.childAdmin);
  },
);

Given(
  "a visitor has no authenticated Bnest session",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    userDataBefore = runtimeDigest(
      userDataRelativePath(activeIdentity.admin.username),
    );
  },
);

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
  expect(
    runtimeDigest(userDataRelativePath(activeIdentity.admin.username)),
  ).toBe(userDataBefore);
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
    const accounts: InitialAccount[] = initialTestIdentities.flatMap(
      (identity) => [
        { ...identity.admin, role: "Parents", admin: true },
        { ...identity.child, role: "Children", admin: false },
        { ...identity.parent, role: "Parents", admin: false },
      ],
    );
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

Given("an approved user account exists", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await page.context().clearCookies();
  await page.goto("/login");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
});

When("the user logs in with valid credentials", async ({ page }) => {
  await page.getByLabel("Username").fill(activeIdentity.admin.username);
  await page.getByLabel("Password").fill(activeIdentity.admin.password);
  await page.getByRole("button", { name: "Log in" }).click();
});

Then("the protected home page is available", async ({ page }) => {
  await expect(
    page.getByRole("heading", { name: "Beaver Nest" }),
  ).toBeVisible();
  await expect(page.locator(".home-status")).toContainText(
    activeIdentity.admin.username,
  );
});

When("the user logs out from that browser", async ({ page }) => {
  await page.getByRole("button", { name: "Log out" }).click();
});

Then("that browser must log in again", async ({ page }) => {
  await page.goto("/chat");
  await expect(page).toHaveURL(/\/login\?return_to=/u);
});
