import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  realpathSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { expect, type Page, type TestInfo } from "@playwright/test";
import { login } from "./authentication";
import { ensureLiveSqlite, runLiveMix } from "./live-sqlite";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

// Trimmed from bnest-app-e2e's scheduled-backups.ts to this project's one
// owned, non-exempt scenario ("Save a safe override"); the contextual
// schedule/deny/discover scenarios moved to bnest-app-fe-e2e.
export type ScheduledBackupWorld = {
  backupConfig?: Record<string, unknown>;
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
  world.identity = isolatedTestIdentity(testInfo);
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
  ensureLiveSqlite();
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
  world.backupConfigPath = path.join(
    requiredRuntimeRoot(),
    "storage-config",
    "backup.json",
  );
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

  const configPath = required(world.backupConfigPath, "backup config path");
  world.backupConfig = readJson(configPath);
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

export function expectAtomicBackupConfig(world: ScheduledBackupWorld): void {
  const configPath = required(world.backupConfigPath, "backup config path");
  expect(world.backupConfig).toEqual({
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

function requiredRuntimeRoot(): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (root === undefined || root === "")
    throw new Error("missing marked E2E runtime root");
  return root;
}
