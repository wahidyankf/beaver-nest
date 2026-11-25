import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  login,
  submitInitialAccountsWithSafetyChecks,
  type InitialAccount,
} from "../support/authentication";
import { ensureCandidate } from "../support/candidate-pool";
import { instanceIdentities } from "../support/instance-identities";
import { candidatePort } from "../support/routed-rollout-env";
import { restorePrimaryRoute } from "../support/routed-rollout";

// Trimmed from bnest-app-e2e's authentication.steps.ts to this project's
// owned scenarios (unauthenticated redirect, logged-out home, the
// recovery-warning half of initial setup, and approved login/logout); the
// password-hashing, session-persistence, and multi-session/multi-role/
// cross-user scenarios moved to bnest-app-be-e2e, and the refused-setup and
// failed-setup-redisplay scenarios live in authentication-setup.steps.ts. The
// setup-card scenarios live in authentication-cards.steps.ts.

const { After, Given, Then, When } = createBdd();

// E2E bindings for the phase-8 FE ADD rows about authentication hardening:
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A login return path stays on this site
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A wrong login stays on the login page and says it is not valid
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: With identity cutover off an unsigned browser acts as the local user
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A logged-out visitor is sent to login from any protected page
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: Approved user logs in and logs out
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: First-time setup warns that accounts cannot be managed or recovered later, then closes

let setupSafetyChecks = { sawIrreversibleWarning: false };

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

Then("the visitor sees no user data", async ({ page }) => {
  await expect(page.locator("body")).not.toContainText(
    instanceIdentities().admin.username,
  );
});

Given("Bnest has not been set up yet", async ({ page }) => {
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

// --- Login return paths (BN-HTTP-05) --------------------------------------------

When(
  "the user logs in with return path {string}",
  async ({ page }, returnTo: string) => {
    const target =
      returnTo === "(empty)"
        ? "/login?return_to="
        : `/login?return_to=${encodeURIComponent(returnTo)}`;
    await page.goto(target);
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    const { admin } = instanceIdentities();
    await page.getByLabel("Username").fill(admin.username);
    await page.getByLabel("Password").fill(admin.password);
    await page.getByRole("button", { name: "Log in" }).click();
  },
);

Then("the user lands on {string}", async ({ page }, path: string) => {
  await page.waitForURL((url) => url.pathname === path, {
    timeout: 15_000,
  });
});

// --- Wrong logins (BN-HTTP-07, BN-AUTH-03) ---------------------------------------

async function attemptLogin(
  page: import("@playwright/test").Page,
  username: string,
  password: string,
): Promise<void> {
  await page.context().clearCookies();
  await page.goto("/login");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Username").fill(username);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Log in" }).click();
}

When("the user logs in with the wrong password", async ({ page }) => {
  const { admin } = instanceIdentities();
  await attemptLogin(page, admin.username, "Definitely the wrong password 0!");
});

When("an unknown user logs in", async ({ page }) => {
  const { admin } = instanceIdentities();
  await attemptLogin(page, "test-user-unknown", admin.password);
});

Then("the login page says the login is not valid", async ({ page }) => {
  await expect(page).toHaveURL(/\/login$/u);
  await expect(
    page.getByText("Username or password is not valid."),
  ).toBeVisible();
});

Then("no identity cookie is set", async ({ page }) => {
  const cookies = await page.context().cookies();
  expect(cookies.filter((cookie) => cookie.name === "_bnest_identity")).toEqual(
    [],
  );
});

// --- Identity cutover (BN-AUTH-11) ------------------------------------------------

// The cutover-off candidate is opened directly instead of routed through
// Caddy: the flag is server-rendered, so the origin only needs to be the
// flag-off server itself.
let cutoverOffBaseURL: string | undefined;

Given("identity cutover is off", async () => {
  await ensureCandidate(candidatePort, false);
  // `localhost`, not `127.0.0.1`: the endpoint's `check_origin` only allows
  // the configured `localhost` host, so the LiveView socket from a
  // `127.0.0.1` page origin is refused and the room never connects.
  cutoverOffBaseURL = `http://localhost:${candidatePort}`;
});

When("the visitor opens this site's home page", async ({ page }) => {
  await page.goto(`${cutoverOffBaseURL ?? ""}/`);
});

Then("the visitor acts as the local browser user", async ({ page }) => {
  await expect(page.locator(".home-status")).toContainText("Local browser");
  await expect(page.getByRole("button", { name: "Log out" })).toHaveCount(0);
  await expect(page.getByText("remain in this browser")).toBeVisible();
});

When("identity cutover is on", async ({ page }) => {
  cutoverOffBaseURL = undefined;
  await restorePrimaryRoute(page);
});

After(() => {
  cutoverOffBaseURL = undefined;
});
