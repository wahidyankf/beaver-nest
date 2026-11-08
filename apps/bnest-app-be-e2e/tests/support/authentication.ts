import { expect, type Browser, type Page } from "@playwright/test";

export type InitialAccount = {
  username: string;
  password: string;
  role: "Children" | "Parents";
  admin: boolean;
};

export type SetupSafetyChecks = {
  sawIrreversibleWarning: boolean;
  passwordRequirementsEnforced: boolean;
  noPasswordLengthRule: boolean;
};

export async function login(
  page: Page,
  identity: { username: string; password: string },
) {
  await page.goto("/login");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Username").fill(identity.username);
  await page.getByLabel("Password").fill(identity.password);
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/", { timeout: 15_000 }),
    page.getByRole("button", { name: "Log in" }).click(),
  ]);
}

// A fresh browser context attempts a login and must be refused, so nothing it holds is shared with `page`.
export async function loginRefused(
  browser: Browser,
  baseURL: string,
  identity: { username: string; password: string },
): Promise<void> {
  const context = await browser.newContext({ baseURL });
  try {
    const page = await context.newPage();
    await page.goto("/login");
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    await page.getByLabel("Username").fill(identity.username);
    await page.getByLabel("Password").fill(identity.password);
    await page.getByRole("button", { name: "Log in" }).click();
    await expect(page.getByRole("alert")).toHaveText(
      "Username or password is not valid.",
    );
    await expect(page).toHaveURL(/\/login/u);
  } finally {
    await context.close();
  }
}

export async function fillInitialAccounts(
  page: Page,
  accounts: InitialAccount[],
  index = 0,
): Promise<void> {
  const account = accounts[index];
  if (!account) return;

  if (index > 0) {
    await page
      .getByRole("button", { name: "Add another initial account" })
      .click();
  }
  await page.getByLabel("Username").nth(index).fill(account.username);
  await page
    .getByLabel("Password", { exact: true })
    .nth(index)
    .fill(account.password);
  await page
    .getByLabel("Confirm password", { exact: true })
    .nth(index)
    .fill(account.password);
  await page.getByLabel(account.role).nth(index).check();
  if (account.admin) await page.getByLabel("Admin").nth(index).check();

  await fillInitialAccounts(page, accounts, index + 1);
}

// No length rule holds only if each password-length account then logs in from a new browser. The caller names that
// account (a synthetic `test-user-` name carrying the instance's short id, with a 3-character password that only a
// character-count rule would refuse). Setup orders card indexes as strings, so an eleventh card would be redrawn out of
// order; a scenario's form stays at four cards (the 131-character case is proven at unit/integration).
export async function submitInitialAccountsWithSafetyChecks(
  page: Page,
  requestedAccounts: InitialAccount[],
  passwordLengthAccount: InitialAccount,
): Promise<SetupSafetyChecks> {
  const passwordLengthAccounts = [passwordLengthAccount];
  const accounts = [...requestedAccounts, ...passwordLengthAccounts];
  const sawIrreversibleWarning = await page.getByRole("note").isVisible();
  const noLengthAttributes = await checkPasswordFormRules(page);

  await fillInitialAccounts(page, accounts);
  await checkInitialAccountCardControls(page, accounts.length);

  await page
    .getByLabel("Confirm password", { exact: true })
    .first()
    .fill("Synthetic mismatched password 123!");
  await confirmAndSubmitSetup(page);
  await expect(page.locator("#setup-error")).toContainText(
    "Each password and confirmation must match.",
  );
  await verifyAndRestorePasswords(page, accounts);

  const passwordRequirementsEnforced = await rejectPasswordMissingRequirement(
    page,
    accounts,
  );

  await setInitialAdmins(page, accounts, false);
  await confirmAndSubmitSetup(page);
  await expect(page).toHaveURL(/\/setup$/u);
  await expect(page.locator("#setup-error")).toBeVisible();
  await expect(page.locator("#bootstrap-form")).toHaveAttribute(
    "aria-describedby",
    "setup-error",
  );
  const accepted = await submitCorrectedSetup(page, accounts);
  const lengthAccountsLoggedIn = accepted
    ? await Promise.all(
        passwordLengthAccounts.map((account) => logsInToHome(page, account)),
      )
    : [false];

  return {
    sawIrreversibleWarning,
    passwordRequirementsEnforced,
    noPasswordLengthRule:
      noLengthAttributes && lengthAccountsLoggedIn.every(Boolean),
  };
}

// Submits the corrected form; a refusal is evidence for the length Then, not a When failure.
async function submitCorrectedSetup(
  page: Page,
  accounts: InitialAccount[],
): Promise<boolean> {
  await verifyAndRestorePasswords(page, accounts);
  await setInitialAdmins(page, accounts, true);
  // The earlier refusal's #setup-error is still on screen until the POST's page loads.
  const answered = page.waitForEvent("load");
  await confirmAndSubmitSetup(page);
  await answered;
  const created = page.getByText(
    "Initial accounts created. Setup is now permanently closed.",
  );
  await expect(created.or(page.locator("#setup-error"))).toBeVisible();
  return created.isVisible();
}

// A login from a fresh browser context, which never touches `page`'s own session.
async function logsInToHome(
  page: Page,
  identity: { username: string; password: string },
): Promise<boolean> {
  const browser = page.context().browser();
  if (!browser) throw new Error("Browser fixture is unavailable");
  const context = await browser.newContext({
    baseURL: new URL(page.url()).origin,
  });

  try {
    const freshPage = await context.newPage();
    await login(freshPage, identity);
    return new URL(freshPage.url()).pathname === "/";
  } catch {
    return false;
  } finally {
    await context.close();
  }
}

async function checkInitialAccountCardControls(
  page: Page,
  accountCount: number,
): Promise<void> {
  const accountCards = page.locator("[data-account-card]");
  await page
    .getByRole("button", { name: "Add another initial account" })
    .click();
  await expect(accountCards).toHaveCount(accountCount + 1);
  await accountCards
    .last()
    .getByRole("button", { name: "Remove this account" })
    .click();
  await expect(accountCards).toHaveCount(accountCount);
}

async function checkPasswordFormRules(page: Page): Promise<boolean> {
  const passwordInputs = page.locator("#bootstrap-form input[type=password]");
  const hasNoLengthRule = await passwordInputs.evaluateAll((inputs) =>
    inputs.every(
      (input) =>
        !input.hasAttribute("minlength") && !input.hasAttribute("maxlength"),
    ),
  );

  await expect(passwordInputs.first()).toHaveAccessibleDescription(
    "Include a letter, number, and punctuation mark, such as _.",
  );

  return hasNoLengthRule;
}

async function rejectPasswordMissingRequirement(
  page: Page,
  accounts: InitialAccount[],
): Promise<boolean> {
  await page.getByLabel("Password", { exact: true }).first().fill("password1");
  await page
    .getByLabel("Confirm password", { exact: true })
    .first()
    .fill("password1");
  await confirmAndSubmitSetup(page);
  const setupError = page.locator("#setup-error");
  await expect(setupError).toContainText(
    "Each password needs a letter, number, and punctuation mark, such as _.",
  );
  const requirementsRejected = await setupError.isVisible();
  await verifyAndRestorePasswords(page, accounts);

  return requirementsRejected;
}

async function confirmAndSubmitSetup(page: Page): Promise<void> {
  await page.getByLabel(/I understand setup closes permanently/u).check();
  await page
    .getByRole("button", { name: "Create accounts and close setup" })
    .click();
}

export async function setInitialAdmins(
  page: Page,
  accounts: InitialAccount[],
  checked: boolean,
  index = 0,
): Promise<void> {
  const account = accounts[index];
  if (!account) return;

  if (account.admin) {
    const admin = page.getByLabel("Admin").nth(index);
    if (checked) await admin.check();
    else await admin.uncheck();
  }
  await setInitialAdmins(page, accounts, checked, index + 1);
}

export async function verifyAndRestorePasswords(
  page: Page,
  accounts: InitialAccount[],
  index = 0,
): Promise<void> {
  const account = accounts[index];
  if (!account) return;

  await expect(page.getByLabel("Username").nth(index)).toHaveValue(
    account.username,
  );
  await expect(page.getByLabel(account.role).nth(index)).toBeChecked();
  await expect(
    page.getByLabel("Password", { exact: true }).nth(index),
  ).toHaveValue("");
  await expect(
    page.getByLabel("Confirm password", { exact: true }).nth(index),
  ).toHaveValue("");
  await page
    .getByLabel("Password", { exact: true })
    .nth(index)
    .fill(account.password);
  await page
    .getByLabel("Confirm password", { exact: true })
    .nth(index)
    .fill(account.password);

  await verifyAndRestorePasswords(page, accounts, index + 1);
}
