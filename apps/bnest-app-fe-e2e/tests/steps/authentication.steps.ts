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
// cross-user scenarios moved to bnest-app-be-e2e.

const { After, Given, Then, When } = createBdd();

// E2E bindings for the phase-8 FE ADD rows about authentication hardening:
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A login return path stays on this site
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A wrong login stays on the login page and says it is not valid
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: With identity cutover off an unsigned browser acts as the local user
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: The setup page adds and removes family member cards
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A setup submission that breaks a rule is refused and creates no account
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A failed setup keeps the names and roles and clears every password

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
  await ensureCandidate(candidatePort, undefined, undefined, false);
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

// --- Setup cards (BN-SETUP-01) ----------------------------------------------------

When("the setup page is shown", async ({ page }) => {
  const response = await page.goto("/setup");
  expect(response?.status()).toBe(200);
  await expect(
    page.getByRole("heading", { name: "Create the first family accounts" }),
  ).toBeVisible();
});

Then("it opens with one administrator card", async ({ page }) => {
  await expect(page.locator("[data-account-card]")).toHaveCount(1);
  await expect(
    page.locator("[data-account-card] legend").first(),
  ).toContainText("Initial administrator");
});

Then("the first card offers no remove control", async ({ page }) => {
  await expect(
    page
      .locator("[data-account-card]")
      .first()
      .getByRole("button", { name: "Remove this account" }),
  ).toHaveCount(0);
});

Then("it offers to add another initial account", async ({ page }) => {
  await page
    .getByRole("button", { name: "Add another initial account" })
    .click();
  await expect(page.locator("[data-account-card]")).toHaveCount(2);
});

Then("the card template numbers a new family member card", async ({ page }) => {
  await expect(
    page.locator("[data-account-card]").nth(1).locator("[data-account-number]"),
  ).toHaveText("2");
  await expect(page.getByLabel("Username").nth(1)).toBeFocused();
  await page
    .locator("[data-account-card]")
    .nth(1)
    .getByRole("button", { name: "Remove this account" })
    .click();
  await expect(page.locator("[data-account-card]")).toHaveCount(1);
  await expect(
    page.getByRole("button", { name: "Add another initial account" }),
  ).toBeFocused();
});

// --- Refused setups (BN-SETUP-03, BN-SETUP-04, BN-SETUP-06) ------------------------

const setupPassword = "Setup password 1!";

async function fillSetupCard(
  page: import("@playwright/test").Page,
  index: number,
  username: string,
  password: string,
  confirmation: string,
): Promise<void> {
  await page.getByLabel("Username").nth(index).fill(username);
  await page.getByLabel("Password", { exact: true }).nth(index).fill(password);
  await page
    .getByLabel("Confirm password", { exact: true })
    .nth(index)
    .fill(confirmation);
}

async function submitSetupForm(
  page: import("@playwright/test").Page,
): Promise<void> {
  await page
    .locator("#bootstrap-form")
    .evaluate((form) => (form as HTMLFormElement).submit());
  await page.waitForURL(/\/setup$/u, { timeout: 15_000 });
}

When(
  "the maintainer submits the {string} setup",
  async ({ page }, setupCase: string) => {
    await page.goto("/setup");
    await expect(
      page.getByRole("heading", { name: "Create the first family accounts" }),
    ).toBeVisible();

    switch (setupCase) {
      case "no admin": {
        await fillSetupCard(
          page,
          0,
          "test-user-setup-one",
          setupPassword,
          setupPassword,
        );
        await page.getByLabel("Admin").nth(0).uncheck();
        await page.getByLabel("Children").nth(0).check();
        await page.getByLabel(/I understand setup closes permanently/u).check();
        await page
          .getByRole("button", { name: "Create accounts and close setup" })
          .click();
        break;
      }
      case "duplicate username": {
        await page
          .getByRole("button", { name: "Add another initial account" })
          .click();
        await fillSetupCard(
          page,
          0,
          "Test-User-Setup",
          setupPassword,
          setupPassword,
        );
        await fillSetupCard(
          page,
          1,
          "test-user-setup",
          setupPassword,
          setupPassword,
        );
        await page.getByLabel("Admin").nth(1).check();
        await page.getByLabel(/I understand setup closes permanently/u).check();
        await page
          .getByRole("button", { name: "Create accounts and close setup" })
          .click();
        break;
      }
      case "empty username": {
        await fillSetupCard(page, 0, "", setupPassword, setupPassword);
        await page.getByLabel(/I understand setup closes permanently/u).check();
        await submitSetupForm(page);
        break;
      }
      case "long username": {
        // `maxlength` would trim a typed value to 32 characters, so the
        // overlong name is set directly and the form is posted past it.
        await page
          .getByLabel("Password", { exact: true })
          .nth(0)
          .fill(setupPassword);
        await page
          .getByLabel("Confirm password", { exact: true })
          .nth(0)
          .fill(setupPassword);
        await page
          .getByLabel("Username")
          .nth(0)
          .evaluate((input, value) => {
            (input as HTMLInputElement).value = value;
          }, "a".repeat(33));
        await page.getByLabel(/I understand setup closes permanently/u).check();
        await submitSetupForm(page);
        break;
      }
      case "password mismatch": {
        await fillSetupCard(
          page,
          0,
          "test-user-setup-one",
          setupPassword,
          "A different password 0!",
        );
        await page.getByLabel(/I understand setup closes permanently/u).check();
        await page
          .getByRole("button", { name: "Create accounts and close setup" })
          .click();
        break;
      }
      case "unchecked box": {
        await fillSetupCard(
          page,
          0,
          "test-user-setup-one",
          setupPassword,
          setupPassword,
        );
        await submitSetupForm(page);
        break;
      }
      default: {
        throw new Error(`unknown setup case ${setupCase}`);
      }
    }
  },
);

Then("setup stays open with {string}", async ({ page }, message: string) => {
  await expect(page).toHaveURL(/\/setup$/u);
  await expect(page.locator("#setup-error")).toContainText(message);
});

Then("no account is created", async ({ page }) => {
  await expect(page.locator("#bootstrap-form")).toBeVisible();
  expect((await page.request.get("/setup")).status()).toBe(200);
});

// --- Failed setup redisplay (BN-SETUP-07) --------------------------------------------

When(
  "the maintainer submits two accounts with mismatched passwords",
  async ({ page }) => {
    await page.goto("/setup");
    await expect(
      page.getByRole("heading", { name: "Create the first family accounts" }),
    ).toBeVisible();
    await page
      .getByRole("button", { name: "Add another initial account" })
      .click();
    await fillSetupCard(
      page,
      0,
      "test-user-setup-one",
      "Setup password 1!",
      "Setup mismatch 9!",
    );
    await page.getByLabel("Children").nth(0).check();
    await fillSetupCard(
      page,
      1,
      "test-user-setup-two",
      "Setup password 2!",
      "Setup mismatch 8!",
    );
    await page.getByLabel("Admin").nth(1).check();
    await page.getByLabel(/I understand setup closes permanently/u).check();
    await page
      .getByRole("button", { name: "Create accounts and close setup" })
      .click();
  },
);

Then(
  "the setup form keeps both usernames and ticked roles",
  async ({ page }) => {
    await expect(page.getByLabel("Username").nth(0)).toHaveValue(
      "test-user-setup-one",
    );
    await expect(page.getByLabel("Username").nth(1)).toHaveValue(
      "test-user-setup-two",
    );
    await expect(page.getByLabel("Children").nth(0)).toBeChecked();
    await expect(page.getByLabel("Admin").nth(1)).toBeChecked();
  },
);

Then("every password field is empty", async ({ page }) => {
  for (const label of ["Password", "Confirm password"]) {
    for (const index of [0, 1]) {
      // eslint-disable-next-line no-await-in-loop -- two cards read in order so a failure names its field.
      await expect(
        page.getByLabel(label, { exact: true }).nth(index),
      ).toHaveValue("");
    }
  }
});

Then("the refusal shows in an alert", async ({ page }) => {
  await expect(page.locator("#setup-error")).toContainText(
    "Each password and confirmation must match.",
  );
  await expect(page.locator("#setup-error")).toHaveAttribute("role", "alert");
});
