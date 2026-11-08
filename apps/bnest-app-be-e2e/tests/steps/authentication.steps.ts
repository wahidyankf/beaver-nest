import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { currentInstance } from "../support/active-instance.mts";
import {
  login,
  submitInitialAccountsWithSafetyChecks,
  type InitialAccount,
  type SetupSafetyChecks,
} from "../support/authentication";
import { currentIdentities, userIdFor } from "../support/instance-identities";
import { instanceRecord } from "../support/instance-records";
import { testUsername } from "../support/test-instance-lifecycle.mts";

// Trimmed from bnest-app-e2e's authentication.steps.ts to this project's owned scenarios (password hashing, session
// persistence, independent browser sessions, and the accounts/password-policy half of initial setup); the
// unauthenticated-redirect and approved-login/logout scenarios moved to bnest-app-fe-e2e. Every account here is the
// current test instance's own (ADR 001, section 2), never a shared one.

const { Given, Then, When } = createBdd();

let browserBContext: BrowserContext | undefined;
let browserBPage: Page | undefined;
let restartedContext: BrowserContext | undefined;
let restartedPage: Page | undefined;
let droppedSessionCookies: string[] = [];
let setupSafetyChecks: SetupSafetyChecks = {
  sawIrreversibleWarning: false,
  passwordRequirementsEnforced: false,
  noPasswordLengthRule: false,
};

Given("an approved user is logged in", async ({ page }) => {
  await login(page, currentIdentities().admin);
});

Given("Bnest has no bootstrap journal", async ({ page }) => {
  const response = await page.goto("/setup");
  expect(response?.status()).toBe(200);
  await expect(
    page.getByRole("heading", { name: "Create the first family accounts" }),
  ).toBeVisible();
});

// The setup accounts are the instance's planned identities: the administrator and the two members, then one
// password-length account. None is shared with another scenario, because each carries this instance's short id.
When(
  "the maintainer submits all initial accounts including an administrator",
  async ({ page }) => {
    const identities = currentIdentities();
    const accounts: InitialAccount[] = [
      { ...identities.admin, role: "Parents", admin: true },
      { ...identities.child, role: "Children", admin: false },
      { ...identities.parent, role: "Parents", admin: false },
    ];
    const passwordLengthAccount: InitialAccount = {
      username: testUsername("short-pass", currentInstance().instanceId),
      password: "a_1",
      role: "Children",
      admin: false,
    };
    setupSafetyChecks = await submitInitialAccountsWithSafetyChecks(
      page,
      accounts,
      passwordLengthAccount,
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

// The seeded admin account, read through production's record read, holds an Argon2id verifier.
Given(
  "an approved user account exists with an Argon2id verifier",
  async ({ page }) => {
    const account = instanceRecord(
      "account",
      userIdFor(currentIdentities().admin.username),
    );
    expect(String(account["passwordVerifier"])).toMatch(
      /^\$argon2id\$v=19\$/u,
    );
    await page.context().clearCookies();
    await page.goto("/login");
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  },
);

When("the user logs in with valid credentials", async ({ page }) => {
  const identity = currentIdentities().admin;
  await page.getByLabel("Username").fill(identity.username);
  await page.getByLabel("Password").fill(identity.password);
  await page.getByRole("button", { name: "Log in" }).click();
});

// The login must have reached the protected home. The stored account holds only the Argon2id verifier, and neither
// the home it rendered nor the login page holds the password. The webServer's log stream is outside this project's
// steps and support; the unit and integration layers capture the login's log and assert the password is absent
// from it.
Then(
  "no plaintext password is stored, logged, or rendered",
  async ({ page }) => {
    const identity = currentIdentities().admin;
    const password = identity.password;
    await expect(page).toHaveURL(/\/$/u);
    await expect(page.locator(".home-status")).toContainText(identity.username);
    const accountText = JSON.stringify(
      instanceRecord("account", userIdFor(identity.username)),
    );
    expect(accountText).toMatch(/"passwordVerifier":"\$argon2id\$/u);
    expect(accountText).not.toContain(password);
    expect(await page.content()).not.toContain(password);
    const loginPage = await page.request.get("/login");
    expect(await loginPage.text()).not.toContain(password);
  },
);

// A reload, then a browser restart: a new browser context opened from the saved storage state without the cookies
// that end with the browser session.
When(
  "the user reloads and reopens Bnest in the same browser",
  async ({ page }) => {
    const identity = currentIdentities().admin;
    await page.reload();
    await expect(page.locator(".home-status")).toContainText(identity.username);
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
    currentIdentities().admin.username,
  );
  await restartedContext.close();
  restartedContext = undefined;
  restartedPage = undefined;
});

Given(
  "one approved user is logged in on browser A and browser B",
  async ({ page }) => {
    const identity = currentIdentities().admin;
    await login(page, identity);
    const browser = page.context().browser();
    if (!browser) throw new Error("Browser fixture is unavailable");
    browserBContext = await browser.newContext({
      baseURL: new URL(page.url()).origin,
    });
    browserBPage = await browserBContext.newPage();
    await login(browserBPage, identity);
  },
);

When("the user logs out from browser A", async ({ page }) => {
  await page.getByRole("button", { name: "Log out" }).click();
  // Logging out first clears this member's queued messages from the device, so the form is submitted a moment after
  // the click; a member is logged out once the server's redirect to the login page has landed, not when the button
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
    currentIdentities().admin.username,
  );
  await browserBContext.close();
  browserBContext = undefined;
  browserBPage = undefined;
});
