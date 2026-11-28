import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { expect, type Page, type TestInfo } from "@playwright/test";
import { login } from "./authentication";
import { backupConfigPath, runLiveMix } from "./live-sqlite";
import { currentIdentities, type TestIdentity } from "./instance-identities";

// Trimmed from bnest-app-e2e's scheduled-backups.ts to this project's
// "Saving a backup folder confirms the save ..." scenario; "A daily backup with
// no saved folder ..." lives in default-backup-destination.ts, and the
// contextual schedule/deny/discover scenarios moved to bnest-app-fe-e2e.
export type ScheduledBackupWorld = {
  backupConfigPath?: string;
  backupDirectory?: string;
  backupMarker?: Record<string, unknown>;
  identity?: TestIdentity;
  setupClaimCount?: number;
};

export async function prepareScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  state: string,
  testInfo: TestInfo,
): Promise<void> {
  world.identity = currentIdentities();
  await page.context().clearCookies();
  await login(page, world.identity.admin);

  if (state === "admin_opened_schedules")
    return prepareBackupOverride(page, world, testInfo);
  throw new Error(`unknown scheduled backup preparation: ${state}`);
}

async function prepareBackupOverride(
  page: Page,
  world: ScheduledBackupWorld,
  testInfo: TestInfo,
): Promise<void> {
  const digest = createHash("sha256")
    .update(`${testInfo.project.name}:${testInfo.title}`)
    .digest("hex")
    .slice(0, 12);
  const directory = path.join(
    realpathSync(os.tmpdir()),
    `bnest-be-e2e-backup-${digest}`,
  );
  rmSync(directory, { recursive: true, force: true });
  mkdirSync(path.dirname(directory), { recursive: true });
  process.once("exit", () =>
    rmSync(directory, { recursive: true, force: true }),
  );
  world.backupDirectory = directory;
  world.backupConfigPath = backupConfigPath();
  await page.goto("/admin/settings/schedules");
  await connected(page);
}

export function performScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  action: string,
): Promise<void> {
  if (action === "save_backup_override") return saveBackupOverride(page, world);
  throw new Error(`unknown scheduled backup action: ${action}`);
}

async function saveBackupOverride(
  page: Page,
  world: ScheduledBackupWorld,
): Promise<void> {
  const directory = required(world.backupDirectory, "backup directory");
  await page.getByLabel("Private destination override").fill(directory);
  const save = page.getByRole("button", {
    name: "Save and create first backup",
  });
  await save.click();
  await expect(page.getByText(/first verification was queued/u)).toBeVisible();
  await save.click();
  await expect(page.getByText(/first verification was queued/u)).toBeVisible();

  world.backupMarker = readJson(
    path.join(directory, ".bnest-backup-root.json"),
  );
  const destinationId = String(world.backupMarker["destinationId"] ?? "");
  const result = runLiveMix(
    `count = BnestApp.SqliteRepo.query!("SELECT COUNT(*) FROM bnest_schedule_runs WHERE claim_key = ?", ["setup:${destinationId}"]).rows |> hd() |> hd(); IO.puts("claim-count=#{count}")`,
  );
  expect(result.status, result.stderr).toBe(0);
  world.setupClaimCount = Number(
    /claim-count=(\d+)/u.exec(result.stdout)?.[1] ?? "NaN",
  );
}

export function expectOneSetupClaim(world: ScheduledBackupWorld): void {
  expect(world.setupClaimCount).toBe(1);
}

// The configuration file is complete JSON naming the destination, written private (mode 0600),
// with no partial temporary file left beside it.
export function expectAtomicBackupConfig(world: ScheduledBackupWorld): void {
  const configPath = required(world.backupConfigPath, "backup config path");
  expect(readJson(configPath)).toEqual({
    destinationDirectory: world.backupDirectory,
    schemaVersion: 1,
  });
  expect(statSync(configPath).mode & 0o777).toBe(0o600);
  expect(
    readdirSync(path.dirname(configPath)).filter((entry) =>
      entry.startsWith(`${path.basename(configPath)}.partial-`),
    ),
  ).toEqual([]);
}

// The confirmation is still on the page after the double submit. After a reload the page
// shows the saved folder, and the double submit queued exactly one first verification.
export async function expectSavedFolderAndOneCheck(
  page: Page,
  world: ScheduledBackupWorld,
): Promise<void> {
  await expect(page.getByText(/first verification was queued/u)).toBeVisible();
  await page.reload();
  await connected(page);
  await expect(page.getByLabel("Private destination override")).toHaveValue(
    required(world.backupDirectory, "backup directory"),
  );
}

function connected(page: Page): Promise<void> {
  return expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

function readJson(file: string): Record<string, unknown> {
  return JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>;
}

function required<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw new Error(`missing ${name}`);
  return value;
}
