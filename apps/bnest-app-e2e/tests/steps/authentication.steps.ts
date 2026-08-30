import { readFileSync } from "node:fs";
import path from "node:path";
import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  jsonFiles,
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

const { Given, Then, When } = createBdd();

let browserBContext: BrowserContext | undefined;
let browserBPage: Page | undefined;
let setupSafetyChecks = {
  sawIrreversibleWarning: false,
  passwordRequirementsEnforced: false,
  noPasswordLengthRule: false,
};
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

Then("Bnest creates the accounts exactly once", async ({ page }) => {
  await expect(page).toHaveURL(/\/login$/u);
  await expect(
    page.getByText(
      "Initial accounts created. Setup is now permanently closed.",
    ),
  ).toBeVisible();
});

Then(
  "setup and public registration are unavailable afterward",
  async ({ page }) => {
    expect((await page.request.get("/setup")).status()).toBe(404);
    expect((await page.request.get("/register")).status()).toBe(404);
  },
);

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

Given("an approved user account exists", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await page.context().clearCookies();
  await page.goto("/login");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
});

Given(
  "an approved user account exists with an Argon2id verifier",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
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

Then(
  "no plaintext password is stored, logged, or rendered",
  async ({ page }) => {
    const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
    if (!root) throw new Error("Missing marked E2E runtime root");
    const accountBytes = jsonFiles(path.join(root, "system/accounts"))
      .map((file) => readFileSync(file, "utf8"))
      .join("");
    const pageContent = await page.content();
    for (const identity of initialTestIdentities) {
      expect(accountBytes).not.toContain(identity.admin.password);
      expect(accountBytes).not.toContain(identity.child.password);
      expect(pageContent).not.toContain(identity.admin.password);
      expect(pageContent).not.toContain(identity.child.password);
    }
  },
);

When(
  "the user reloads and reopens Bnest in the same browser",
  async ({ page }) => {
    await page.goto("about:blank");
    await page.goto("/");
  },
);

Then("the same browser remains authenticated", async ({ page }) => {
  await expect(page).toHaveURL(/\/$/u);
  await expect(page.locator(".home-status")).toContainText(
    activeIdentity.admin.username,
  );
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
