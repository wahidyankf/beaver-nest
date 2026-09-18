import { chmodSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { isolatedTestIdentity } from "../support/test-identity";
import { readLivePointer } from "../support/sqlite-storage";
import {
  captureStorageAuthority,
  restoreStorageAuthority,
} from "../support/storage-authority";

// Admin storage LiveView folder-selection flows (feature scenarios 2 through 4).
// Split out of sqlite_storage.steps.ts to stay under the repository's
// 300-line step-file budget.

const { After, Given, Then, When } = createBdd();

const repositoryRoot = process.cwd();

let customFolder = "";
let customFolderCleanupRoot = "";
let livePointerBefore: Record<string, unknown> | undefined;
let adminStorageAuthorityCaptured = false;

After(() => {
  try {
    if (customFolderCleanupRoot !== "") {
      rmSync(customFolderCleanupRoot, { recursive: true, force: true });
    }
  } finally {
    customFolderCleanupRoot = "";
    if (adminStorageAuthorityCaptured) {
      adminStorageAuthorityCaptured = false;
      restoreStorageAuthority();
    }
  }
});

async function persistCustomFolder(page: Page): Promise<void> {
  await page
    .getByRole("textbox", { name: "Database folder" })
    .fill(customFolder);
  await page.getByRole("button", { name: "Check folder" }).click();
  await expect(page.getByText("Folder looks safe to use.")).toBeVisible();
  await page.getByRole("button", { name: "Create database" }).click();
  // create_database is a LiveView event; its persist happens server-side
  // after the click resolves client-side, so poll for the write to land.
  await expect
    .poll(() => readLivePointer()?.["databaseDirectory"])
    .toBe(path.resolve(customFolder));
}

// --- Scenario 2: admin selects a valid custom folder ------------------------

Given(
  "an authenticated user with the admin role opened storage settings",
  async ({ page, $testInfo }) => {
    captureStorageAuthority();
    adminStorageAuthorityCaptured = true;
    const identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, identity.admin);
    livePointerBefore = readLivePointer();
    const response = await page.goto("/storage");
    expect(response?.status()).toBe(200);
    await expect(
      page.getByRole("heading", { name: "Storage setup" }),
    ).toBeVisible();
  },
);

Given("migration has not started", async ({ page }) => {
  await expect(page.getByText("Status:")).toContainText("Not started");
});

When(
  "the administrator enters a writable private server-local folder",
  async ({ page }) => {
    customFolder = mkdtempSync(
      path.join(os.tmpdir(), "bnest-e2e-storage-custom-"),
    );
    customFolderCleanupRoot = customFolder;

    await persistCustomFolder(page);
  },
);

When(
  "the administrator enters a private folder beneath a sticky shared directory",
  async ({ page }) => {
    const shared = mkdtempSync(
      path.join(os.tmpdir(), "bnest-e2e-storage-shared-"),
    );
    customFolderCleanupRoot = shared;
    chmodSync(shared, 0o1777);
    customFolder = path.join(shared, "private");
    mkdirSync(customFolder, { mode: 0o700 });

    await persistCustomFolder(page);
  },
);

Then(
  "Bnest normalizes the folder and appends the fixed database filename",
  () => {
    const pointer = readLivePointer();
    expect(pointer?.["databaseDirectory"]).toBe(path.resolve(customFolder));
    expect(pointer?.["databaseFilename"]).toBe("bnest.sqlite3");
  },
);

Then(
  "Bnest stores only the validated absolute location in private machine state",
  () => {
    const pointer = readLivePointer();
    expect(Object.keys(pointer ?? {}).toSorted()).toEqual(
      [
        "databaseDirectory",
        "databaseFilename",
        "migrationId",
        "phase",
        "schemaVersion",
      ].toSorted(),
    );
    expect(String(pointer?.["databaseDirectory"])).toMatch(/^\//u);
  },
);

// --- Scenario 3: unsafe folder rejected without mutation --------------------

When(
  "the folder is relative, symlinked, world-writable, inside the repository, or overlaps a migration source",
  async ({ page }) => {
    livePointerBefore = readLivePointer();
    const unsafeFolder = path.join(repositoryRoot, "data");
    await page
      .getByRole("textbox", { name: "Database folder" })
      .fill(unsafeFolder);
    await page.getByRole("button", { name: "Check folder" }).click();
  },
);

Then("Bnest explains the safe correction", async ({ page }) => {
  await expect(page.getByRole("alert")).toContainText(
    "That folder overlaps the application or a migration source.",
  );
});

Then("Bnest creates no database or storage configuration", () => {
  expect(readLivePointer()).toEqual(livePointerBefore);
});
