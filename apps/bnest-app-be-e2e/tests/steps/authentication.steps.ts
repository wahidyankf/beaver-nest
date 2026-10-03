import { readFileSync } from "node:fs";
import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  login,
  storedAccountFile,
  submitInitialAccountsWithSafetyChecks,
  type InitialAccount,
} from "../support/authentication";
import {
  initialTestIdentities,
  isolatedTestIdentity,
  testIdentityForProject,
  type TestIdentity,
} from "../support/test-identity";

// Trimmed from bnest-app-e2e's authentication.steps.ts to this project's
// owned scenarios (password hashing, session persistence, independent
// browser sessions, and the accounts/password-policy half of initial
// setup); the unauthenticated-redirect and approved-login/logout scenarios
// moved to bnest-app-fe-e2e.

const { Given, Then, When } = createBdd();

let browserBContext: BrowserContext | undefined;
let browserBPage: Page | undefined;
let restartedContext: BrowserContext | undefined;
let restartedPage: Page | undefined;
let droppedSessionCookies: string[] = [];
let setupSafetyChecks = {
  sawIrreversibleWarning: false,
  passwordRequirementsEnforced: false,
  noPasswordLengthRule: false,
};
let activeIdentity: TestIdentity = testIdentityForProject("chromium");

Given("an approved user is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await login(page, activeIdentity.admin);
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

Then("Bnest creates the accounts exactly once", async ({ page }) => {
  await expect(page).toHaveURL(/\/login$/u);
  await expect(
    page.getByText(
      "Initial accounts created. Setup is now permanently closed.",
    ),
  ).toBeVisible();
});

Then(
  "Bnest accepts the passwords without a character-count rule",
  ({ page }) => {
    void page;
    expect(setupSafetyChecks.noPasswordLengthRule).toBe(true);
  },
);

Then(
  "Bnest rejects a password missing a letter, number, or punctuation mark",
  ({ page }) => {
    void page;
    expect(setupSafetyChecks.passwordRequirementsEnforced).toBe(true);
  },
);

// The account the identity's username index names stores an Argon2id verifier.
Given(
  "an approved user account exists with an Argon2id verifier",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    const account = JSON.parse(
      readFileSync(storedAccountFile(activeIdentity.admin.username), "utf8"),
    ) as { passwordVerifier: string };
    expect(account.passwordVerifier).toMatch(/^\$argon2id\$v=19\$/u);
    await page.context().clearCookies();
    await page.goto("/login");
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  },
);

When("the user logs in with valid credentials", async ({ page }) => {
  await page.getByLabel("Username").fill(activeIdentity.admin.username);
  await page.getByLabel("Password").fill(activeIdentity.admin.password);
  await page.getByRole("button", { name: "Log in" }).click();
});

// The login must have reached the protected home. Its account still holds only the Argon2id
// verifier, and neither the home it rendered nor the login page holds the password. The
// webServer's log stream is outside this project's steps and support; the unit and
// integration layers capture the login's log and assert the password is absent from it.
Then(
  "no plaintext password is stored, logged, or rendered",
  async ({ page }) => {
    const password = activeIdentity.admin.password;
    await expect(page).toHaveURL(/\/$/u);
    await expect(page.locator(".home-status")).toContainText(
      activeIdentity.admin.username,
    );
    const accountBytes = readFileSync(
      storedAccountFile(activeIdentity.admin.username),
      "utf8",
    );
    expect(accountBytes).toMatch(/"passwordVerifier":"\$argon2id\$/u);
    expect(accountBytes).not.toContain(password);
    expect(await page.content()).not.toContain(password);
    const loginPage = await page.request.get("/login");
    expect(await loginPage.text()).not.toContain(password);
  },
);

// A reload, then a browser restart: a new browser context opened from the saved storage
// state without the cookies that end with the browser session.
When(
  "the user reloads and reopens Bnest in the same browser",
  async ({ page }) => {
    await page.reload();
    await expect(page.locator(".home-status")).toContainText(
      activeIdentity.admin.username,
    );
    const state = await page.context().storageState();
    droppedSessionCookies = state.cookies
      .filter((cookie) => cookie.expires === -1)
      .map((cookie) => cookie.name);
    const browser = page.context().browser();
    if (!browser) throw new Error("Browser fixture is unavailable");
    restartedContext = await browser.newContext({
      baseURL: new URL(page.url()).origin,
      storageState: {
        ...state,
        cookies: state.cookies.filter((cookie) => cookie.expires !== -1),
      },
    });
    restartedPage = await restartedContext.newPage();
    await restartedPage.goto("/");
  },
);

Then("the same browser remains authenticated", async ({ page }) => {
  void page;
  if (!restartedPage || !restartedContext)
    throw new Error("The browser was not restarted");
  expect(droppedSessionCookies).toContain("_bnest_app_key");
  await expect(restartedPage).toHaveURL(/\/$/u);
  await expect(restartedPage.locator(".home-status")).toContainText(
    activeIdentity.admin.username,
  );
  await restartedContext.close();
  restartedContext = undefined;
  restartedPage = undefined;
});

Given(
  "one approved user is logged in on browser A and browser B",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await login(page, activeIdentity.admin);
    const browser = page.context().browser();
    if (!browser) throw new Error("Browser fixture is unavailable");
    browserBContext = await browser.newContext({
      baseURL: new URL(page.url()).origin,
    });
    browserBPage = await browserBContext.newPage();
    await login(browserBPage, activeIdentity.admin);
  },
);

When("the user logs out from browser A", async ({ page }) => {
  await page.getByRole("button", { name: "Log out" }).click();
  // Logging out first clears this member's queued messages from the device, so
  // the form is submitted a moment after the click; a member is logged out once
  // the server's redirect to the login page has landed, not when the button
  // was pressed.
  await page.waitForURL(/\/login$/u);
});

Then("browser A must log in again", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/login/u);
});

Then("browser B remains authenticated", async ({ page }) => {
  void page;
  if (!browserBPage || !browserBContext)
    throw new Error("Browser B was not created");
  await browserBPage.goto("/");
  await expect(browserBPage.locator(".home-status")).toContainText(
    activeIdentity.admin.username,
  );
  await browserBContext.close();
  browserBContext = undefined;
  browserBPage = undefined;
});
