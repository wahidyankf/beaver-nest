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
import { ensureLiveSqlite, runLiveMix } from "./routed-rollout";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

export type ScheduledBackupWorld = {
  backupConfig?: Record<string, unknown>;
  backupConfigPath?: string;
  backupDirectory?: string;
  backupMarker?: Record<string, unknown>;
  contextualScheduleKey?: string;
  identity?: TestIdentity;
  responseBody?: string;
  responseStatus?: number;
  setupClaimCount?: number;
};

export async function prepareScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  state: string,
  testInfo: TestInfo,
): Promise<void> {
  world.identity = isolatedTestIdentity(testInfo);

  if (state === "denied_visitor") return;

  await page.context().clearCookies();
  await login(page, world.identity.admin);

  if (state === "admin_opened_schedules")
    return prepareBackupOverride(page, world, testInfo);
  if (state === "contextual_schedules")
    return prepareContextualSchedules(world, testInfo);

  if (state === "typed_panels") return;
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
    `bnest-e2e-backup-${digest}`,
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

function prepareContextualSchedules(
  world: ScheduledBackupWorld,
  testInfo: TestInfo,
): void {
  ensureLiveSqlite();
  const key = `e2e-family-${createHash("sha256")
    .update(testInfo.title)
    .digest("hex")
    .slice(0, 12)}`;
  const result = runLiveMix(
    `:ok = BnestApp.Scheduler.Store.put_test_schedule("${key}", "family", "fixture", DateTime.utc_now()); IO.puts("schedule-created")`,
  );
  expect(result.status, result.stderr).toBe(0);
  expect(result.stdout).toContain("schedule-created");
  world.contextualScheduleKey = key;
}

export async function performScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  action: string,
): Promise<void> {
  if (action === "save_backup_override") return saveBackupOverride(page, world);
  if (action === "open_admin_settings")
    return openDeniedAdminSettings(page, world);

  if (action === "open_schedules_from_home") {
    await page.goto("/");
    await page.getByRole("link", { name: /Schedules & backups/u }).click();
  } else if (action === "open_admin_settings_from_home") {
    await page.goto("/");
    await page.getByRole("link", { name: /Admin settings/u }).click();
  } else {
    throw new Error(`unknown scheduled backup action: ${action}`);
  }

  await connected(page);
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

async function openDeniedAdminSettings(
  page: Page,
  world: ScheduledBackupWorld,
): Promise<void> {
  const identity = required(world.identity, "isolated identity");
  await page.context().clearCookies();
  await login(page, identity.child);
  await page.goto("/");
  await expect(page.locator("[data-role=admin-settings-entry]")).toHaveCount(0);
  const response = await page.request.get("/admin/settings");
  world.responseStatus = response.status();
  world.responseBody = await response.text();
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

export async function expectScheduleGroups(
  page: Page,
  world: ScheduledBackupWorld,
): Promise<void> {
  await expect(
    page.getByRole("heading", { name: "Family schedules" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Admin/system schedules" }),
  ).toBeVisible();
  await expect(
    page.locator(
      `[data-schedule-key="${required(world.contextualScheduleKey, "schedule key")}"]`,
    ),
  ).toContainText(/Enabled|Running|Verified|Never run/u);
}

export async function expectTypedBackupLink(page: Page): Promise<void> {
  await expect(
    page.locator('[data-schedule-key="prod-sqlite-backup-daily"] a'),
  ).toHaveAttribute("href", "/admin/settings/schedules");
}

export function expectDeniedSettings(world: ScheduledBackupWorld): void {
  expect(world.responseStatus).toBe(404);
  expect(world.responseBody).toBe("Not found");
}

export async function expectNoAdminEntry(page: Page): Promise<void> {
  await expect(page.locator("[data-role=admin-settings-entry]")).toHaveCount(0);
  await expect(page.locator("[data-role=admin-schedules-entry]")).toHaveCount(
    0,
  );
}

export async function expectAdminPanels(page: Page): Promise<void> {
  await expect(
    page.getByRole("link", { name: /Data storage/u }),
  ).toHaveAttribute("href", "/storage");
  await expect(
    page.getByRole("link", { name: /Schedules & backups/u }),
  ).toHaveAttribute("href", "/admin/settings/schedules");
}

export async function expectOwnerAllowlists(page: Page): Promise<void> {
  await expect(
    page.getByText(
      /Each area validates and saves only the fields owned by its domain/u,
    ),
  ).toBeVisible();
  const panels = page.locator(".admin-settings-panel");
  await expect(panels).toHaveCount(2);
  await expect(panels.nth(0)).toHaveAttribute("data-editable-fields", "");
  await expect(panels.nth(1)).toHaveAttribute(
    "data-editable-fields",
    "destination_directory,enabled,daily_time_wib",
  );
  await expect(panels.nth(0)).toHaveAttribute(
    "data-config-owner",
    /Storage\.Config/u,
  );
  await expect(panels.nth(1)).toHaveAttribute(
    "data-config-owner",
    /Backup\.Config/u,
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

function requiredRuntimeRoot(): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (root === undefined || root === "")
    throw new Error("missing marked E2E runtime root");
  return root;
}
