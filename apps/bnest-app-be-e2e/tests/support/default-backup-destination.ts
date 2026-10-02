import { spawnSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { expect, type Page, type TestInfo } from "@playwright/test";
import { login } from "./authentication";
import { ensureLiveSqlite } from "./live-sqlite";
import { readLivePointer } from "./sqlite-storage";
import { isolatedTestIdentity } from "./test-identity";

// The "Use the Dropbox-synced default" scenario over the live server: the backup
// configuration file it found (null when absent) and restores afterwards, the run's own
// default repository, the folder the page rendered, and the receipt and last result of the backup the save verified.
export type DefaultBackupWorld = {
  configPath?: string;
  configBefore?: string | null | undefined;
  repository?: string;
  renderedDirectory?: string;
  lastResult?: string | undefined;
  receipts?: string[];
  marker?: Record<string, unknown>;
};

const backupScheduleKey = "prod-sqlite-backup-daily";

// The live server's backup configuration file is removed for the scenario, so Backup
// resolves its default: `data/backup` in this run's isolated git repository under
// `~/bnest/data/test/backup-repository/<run id>`, never a checkout. The file's prior bytes
// are restored afterwards by `restoreBackupConfiguration`.
export async function prepareNoBackupOverride(
  page: Page,
  world: DefaultBackupWorld,
  testInfo: TestInfo,
): Promise<void> {
  await page.context().clearCookies();
  await login(page, isolatedTestIdentity(testInfo).admin);
  ensureLiveSqlite();
  expect(readLivePointer()?.["phase"]).toBe("sqlite_primary");
  const configPath = path.join(runtimeRoot(), "storage-config", "backup.json");
  world.configPath = configPath;
  world.configBefore = existsSync(configPath)
    ? readFileSync(configPath, "utf8")
    : null;
  rmSync(configPath, { force: true });
  expect(existsSync(configPath)).toBe(false);
  world.repository = path.join(
    os.homedir(),
    "bnest/data/test/backup-repository",
    runId(),
  );
}

export function restoreBackupConfiguration(world: DefaultBackupWorld): void {
  const before = world.configBefore;
  world.configBefore = undefined;
  if (before === undefined) return;
  const configPath = required(world.configPath, "backup config path");
  if (before === null) rmSync(configPath, { force: true });
  else writeFileSync(configPath, before, { encoding: "utf8", mode: 0o600 });
}

// The schedules page resolves the destination as it mounts and renders it in the override
// field. Saving that folder unchanged queues the first verified backup into it, which is
// awaited as a new receipt in the rendered folder and the backup schedule's last result after
// a reload. A rendered folder outside the marked test data root is never read.
export async function resolveDefaultDestination(
  page: Page,
  world: DefaultBackupWorld,
): Promise<void> {
  await page.goto("/admin/settings/schedules");
  await connected(page);
  const folder = await page
    .getByLabel("Private destination override")
    .inputValue();
  world.renderedDirectory = folder;
  const readable = folder.startsWith(
    path.join(os.homedir(), "bnest/data/test") + path.sep,
  );
  const before = readable ? receiptNames(folder) : [];
  await page
    .getByRole("button", { name: "Save and create first backup" })
    .click();
  await expect(page.getByText(/first verification was queued/u)).toBeVisible();

  if (readable) {
    const created = () =>
      receiptNames(folder).filter((name) => !before.includes(name));
    await expect.poll(() => created().length, { timeout: 60_000 }).toBe(1);
    world.receipts = created().map((name) =>
      readFileSync(path.join(folder, name), "utf8"),
    );
    world.marker = JSON.parse(
      readFileSync(path.join(folder, ".bnest-backup-root.json"), "utf8"),
    ) as Record<string, unknown>;
  }

  await page.reload();
  await connected(page);
  world.lastResult = (
    await page
      .locator(`article[data-schedule-key="${backupScheduleKey}"] dl > div`)
      .filter({ has: page.locator("dt", { hasText: "Last result" }) })
      .locator("dd")
      .textContent()
  )?.trim();
}

// The rendered folder is the run repository's `data/backup`, computed here from the run id,
// and that repository's git ignore rule covers it.
export function expectDefaultBackupFolder(world: DefaultBackupWorld): void {
  const repository = required(world.repository, "default repository");
  const expected = path.join(repository, "data", "backup");
  expect(world.renderedDirectory).toBe(expected);
  expect(expected.startsWith(`${process.cwd()}/`)).toBe(false);
  const ignored = spawnSync(
    "git",
    ["-C", repository, "check-ignore", "-q", "data/backup"],
    { encoding: "utf8" },
  );
  expect(ignored.status, ignored.stderr).toBe(0);
}

// The run's receipt is the default destination's setup run, proved, and neither the
// repository, the backup folder, the live database, the runtime root nor the home directory
// appears in its bytes.
export function expectVerifiedResultWithoutPrivatePath(
  world: DefaultBackupWorld,
): void {
  expect(world.lastResult).toBe("Verified");
  const marker = required(world.marker, "backup marker");
  const pointer = readLivePointer();
  const privatePaths = [
    required(world.repository, "default repository"),
    defaultFolder(world),
    path.join(
      String(pointer?.["databaseDirectory"]),
      String(pointer?.["databaseFilename"]),
    ),
    runtimeRoot(),
    os.homedir(),
  ];
  const receipts = required(world.receipts, "default receipts");
  expect(receipts).toHaveLength(1);
  for (const bytes of receipts) {
    const receipt = JSON.parse(bytes) as Record<string, unknown>;
    expect(receipt["destinationId"]).toBe(marker["destinationId"]);
    expect(receipt["claimKey"]).toBe(
      `setup:${String(marker["destinationId"])}`,
    );
    expect(receipt["quickCheck"]).toBe("ok");
    for (const privatePath of privatePaths)
      expect(bytes).not.toContain(privatePath);
  }
}

function defaultFolder(world: DefaultBackupWorld): string {
  return path.join(
    required(world.repository, "default repository"),
    "data",
    "backup",
  );
}

function receiptNames(folder: string): string[] {
  return existsSync(folder)
    ? readdirSync(folder).filter((name) => name.endsWith(".receipt.json"))
    : [];
}

function connected(page: Page): Promise<void> {
  return expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

function required<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw new Error(`missing ${name}`);
  return value;
}

function runId(): string {
  const id = process.env["BNEST_E2E_RUN_ID"];
  if (id === undefined || id === "")
    throw new Error("missing marked E2E run id");
  return id;
}

function runtimeRoot(): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (root === undefined || root === "")
    throw new Error("missing marked E2E runtime root");
  return root;
}
