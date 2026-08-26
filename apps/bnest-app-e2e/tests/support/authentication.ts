import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";

export type InitialAccount = {
  username: string;
  password: string;
  role: "Children" | "Parents";
  admin: boolean;
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

export function runtimeDigest(relative: string): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E runtime root");

  const files = jsonFiles(path.join(root, relative)).toSorted();
  const hash = createHash("sha256");
  for (const file of files) hash.update(readFileSync(file));
  return hash.digest("hex");
}

export function jsonFiles(directory: string): string[] {
  if (!existsSync(directory)) return [];

  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) return jsonFiles(candidate);
    return entry.isFile() && entry.name.endsWith(".json") ? [candidate] : [];
  });
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

export async function submitInitialAccountsWithSafetyChecks(
  page: Page,
  accounts: InitialAccount[],
): Promise<boolean> {
  const sawIrreversibleWarning = await page.getByRole("note").isVisible();
  await fillInitialAccounts(page, accounts);

  const accountCards = page.locator("[data-account-card]");
  await page
    .getByRole("button", { name: "Add another initial account" })
    .click();
  await expect(accountCards).toHaveCount(accounts.length + 1);
  await accountCards
    .last()
    .getByRole("button", { name: "Remove this account" })
    .click();
  await expect(accountCards).toHaveCount(accounts.length);

  await page
    .getByLabel("Confirm password", { exact: true })
    .first()
    .fill("Synthetic mismatched password 123!");
  await confirmAndSubmitSetup(page);
  await expect(page.locator("#setup-error")).toContainText(
    "Each password and confirmation must match.",
  );
  await verifyAndRestorePasswords(page, accounts);

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

  return sawIrreversibleWarning;
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
