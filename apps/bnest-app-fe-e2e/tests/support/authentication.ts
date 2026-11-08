import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { expect, type Page } from "@playwright/test";
import { currentInstance } from "./active-instance";
import { runConfigPaths } from "./test-instance-lifecycle.mts";
import { deriveTestInstancePaths } from "./test-instance-paths.mts";
import { runId } from "./routed-rollout-env";

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

// The digest of the current instance's database file and its WAL, so a scenario can show that Bnest read
// and wrote no user data. The derived paths are the server's own (`BnestApp.TestInstance.Paths`), so the
// digest covers exactly the database this scenario uses.
export function instanceDatabaseDigest(): string {
  const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
  if (runtimeRoot === "") throw new Error("Missing marked E2E runtime root");
  const derived = deriveTestInstancePaths({
    flatRunRoot: runtimeRoot,
    sqliteRunRoot: runConfigPaths({
      runId,
      home: process.env["HOME"] ?? "",
    }).sqliteRunRoot,
    runId,
    instanceId: currentInstance().instanceId,
  });
  if (!derived.ok) {
    throw new Error(`the instance paths are invalid: ${derived.error}`);
  }

  const hash = createHash("sha256");
  for (const file of [derived.paths.dbFile, `${derived.paths.dbFile}-wal`]) {
    if (existsSync(file)) hash.update(file).update(readFileSync(file));
  }
  return hash.digest("hex");
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

// The warning is the setup form's note naming the lost-password outcome, beside the
// confirmation that setup closes for good; any other note does not count.
async function sawIrreversibleSetupWarning(page: Page): Promise<boolean> {
  const note = page.getByRole("note");
  return (
    (await note.isVisible()) &&
    (await note.innerText()).includes(
      "This is irreversible: losing a password makes that account unavailable.",
    ) &&
    (await page
      .getByLabel(
        "I understand setup closes permanently after this submission.",
      )
      .isVisible())
  );
}

export async function submitInitialAccountsWithSafetyChecks(
  page: Page,
  accounts: InitialAccount[],
): Promise<SetupSafetyChecks> {
  const sawIrreversibleWarning = await sawIrreversibleSetupWarning(page);
  const noPasswordLengthRule = await checkPasswordFormRules(page);

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
  await verifyAndRestorePasswords(page, accounts);
  await setInitialAdmins(page, accounts, true);
  await confirmAndSubmitSetup(page);

  return {
    sawIrreversibleWarning,
    passwordRequirementsEnforced,
    noPasswordLengthRule,
  };
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
