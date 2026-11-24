import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The refused-setup and failed-setup-redisplay scenarios. Split out of
// authentication.steps.ts to stay under the repository's 300-line step-file
// budget. The login, logout, return-path, cutover, and setup-card scenarios
// stay in authentication.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A setup submission that breaks a rule is refused and creates no account
// @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A failed setup keeps the names and roles and clears every password

const { Then, When } = createBdd();

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

async function openSetupPage(
  page: import("@playwright/test").Page,
): Promise<void> {
  await page.goto("/setup");
  await expect(
    page.getByRole("heading", { name: "Create the first family accounts" }),
  ).toBeVisible();
}

async function acknowledgeAndCreate(
  page: import("@playwright/test").Page,
): Promise<void> {
  await page.getByLabel(/I understand setup closes permanently/u).check();
  await page
    .getByRole("button", { name: "Create accounts and close setup" })
    .click();
}

async function submitNoAdminSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  await fillSetupCard(
    page,
    0,
    "test-user-setup-one",
    setupPassword,
    setupPassword,
  );
  await page.getByLabel("Admin").nth(0).uncheck();
  await page.getByLabel("Children").nth(0).check();
  await acknowledgeAndCreate(page);
}

async function submitDuplicateUsernameSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  await page
    .getByRole("button", { name: "Add another initial account" })
    .click();
  await fillSetupCard(page, 0, "Test-User-Setup", setupPassword, setupPassword);
  await fillSetupCard(page, 1, "test-user-setup", setupPassword, setupPassword);
  await page.getByLabel("Admin").nth(1).check();
  await acknowledgeAndCreate(page);
}

async function submitEmptyUsernameSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  await fillSetupCard(page, 0, "", setupPassword, setupPassword);
  await page.getByLabel(/I understand setup closes permanently/u).check();
  await submitSetupForm(page);
}

async function submitLongUsernameSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  // `maxlength` would trim a typed value to 32 characters, so the
  // overlong name is set directly and the form is posted past it.
  await page.getByLabel("Password", { exact: true }).nth(0).fill(setupPassword);
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
}

async function submitPasswordMismatchSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  await fillSetupCard(
    page,
    0,
    "test-user-setup-one",
    setupPassword,
    "A different password 0!",
  );
  await acknowledgeAndCreate(page);
}

async function submitUncheckedBoxSetup(
  page: import("@playwright/test").Page,
): Promise<void> {
  await fillSetupCard(
    page,
    0,
    "test-user-setup-one",
    setupPassword,
    setupPassword,
  );
  await submitSetupForm(page);
}

When(
  "the maintainer submits the {string} setup",
  async ({ page }, setupCase: string) => {
    await openSetupPage(page);

    switch (setupCase) {
      case "no admin": {
        await submitNoAdminSetup(page);
        break;
      }
      case "duplicate username": {
        await submitDuplicateUsernameSetup(page);
        break;
      }
      case "empty username": {
        await submitEmptyUsernameSetup(page);
        break;
      }
      case "long username": {
        await submitLongUsernameSetup(page);
        break;
      }
      case "password mismatch": {
        await submitPasswordMismatchSetup(page);
        break;
      }
      case "unchecked box": {
        await submitUncheckedBoxSetup(page);
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
    await openSetupPage(page);
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
    await acknowledgeAndCreate(page);
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
