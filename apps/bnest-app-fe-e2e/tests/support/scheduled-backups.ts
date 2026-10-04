import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { expect, type Page, type TestInfo } from "@playwright/test";
import { login } from "./authentication";
import { ensureLiveSqlite, runLiveMix } from "./routed-rollout";
import { runtimeRoot } from "./routed-rollout-env";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

const backupScheduleKey = "prod-sqlite-backup-daily";

export type ScheduledBackupWorld = {
  contextualScheduleKey?: string;
  identity?: TestIdentity;
  responseBody?: string;
  responseStatus?: number;
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

  if (state === "contextual_schedules")
    return prepareContextualSchedules(world, testInfo);

  // The Backup owner's saves are exercised against the persisted backup schedule.
  if (state === "typed_panels") return ensureLiveSqlite();
  throw new Error(`unknown scheduled backup preparation: ${state}`);
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
    `:ok = BnestApp.Test.Seeds.Schedules.put_test_schedule("${key}", "family", "fixture", DateTime.utc_now()); IO.puts("schedule-created")`,
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

// Each row is looked for inside its own group's section and is absent from the other.
export async function expectScheduleGroups(
  page: Page,
  world: ScheduledBackupWorld,
): Promise<void> {
  const family = page.locator(
    'section[aria-labelledby="family-schedules-title"]',
  );
  const adminSystem = page.locator(
    'section[aria-labelledby="admin-schedules-title"]',
  );
  await expect(
    family.getByRole("heading", { name: "Family schedules" }),
  ).toBeVisible();
  await expect(
    adminSystem.getByRole("heading", { name: "Admin/system schedules" }),
  ).toBeVisible();
  const familyRow = `[data-schedule-key="${required(world.contextualScheduleKey, "schedule key")}"]`;
  const backupRow = `[data-schedule-key="${backupScheduleKey}"]`;
  await expect(family.locator(familyRow)).toContainText(
    /Enabled|Running|Verified|Never run/u,
  );
  await expect(adminSystem.locator(backupRow)).toContainText(
    /Enabled|Running|Verified|Never run/u,
  );
  await expect(adminSystem.locator(familyRow)).toHaveCount(0);
  await expect(family.locator(backupRow)).toHaveCount(0);
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
    /^BnestApp\.Storage$/u,
  );
  await expect(panels.nth(1)).toHaveAttribute(
    "data-config-owner",
    /^BnestApp\.Backup$/u,
  );
  await saveScheduleWithForgedFields(page);
  await refuseRelativeBackupFolder(page);
}

// The fields the backup schedule's owner may change on a save; every other field must
// keep its stored value even when the submitted form carries it.
const scheduleSaveFields = new Set([
  "daily_at_utc",
  "enabled",
  "next_run_at",
  "revision",
  "updated_at",
]);

// The schedule form is submitted with a new daily time and with unlisted schedule fields
// added to it; the stored schedule is read before and after through the live database.
async function saveScheduleWithForgedFields(page: Page): Promise<void> {
  const before = readBackupSchedule();
  await page.goto("/admin/settings/schedules");
  await connected(page);
  const time = page.getByLabel("Daily time (WIB)");
  await time.fill((await time.inputValue()) === "05:17" ? "05:18" : "05:17");
  await page.evaluate(() => {
    const form = document.querySelector('form[phx-submit="save_schedule"]');
    if (form === null) throw new Error("the schedule form is missing");
    const forged: Array<[string, string]> = [
      ["schedule[schedule_key]", "test-user-forged-schedule"],
      ["schedule[handler_key]", "fixture"],
      ["schedule[context]", "family"],
      ["schedule[expiration_kind]", "after_occurrences"],
      ["schedule[max_occurrences]", "1"],
      ["schedule[daily_at_utc]", "00:01"],
    ];
    for (const [name, value] of forged) {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.append(input);
    }
  });
  await page.getByRole("button", { name: "Save schedule" }).click();
  await expect(page.getByText("Daily schedule saved.")).toBeVisible();

  const after = readBackupSchedule();
  const changed = Object.keys({ ...before, ...after }).filter(
    (key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]),
  );
  expect(changed).toContain("daily_at_utc");
  expect(after["daily_at_utc"]).not.toBe("00:01");
  expect(changed.filter((key) => !scheduleSaveFields.has(key))).toEqual([]);
}

// A relative folder is refused with the page's correction, and the backup configuration
// file keeps its bytes (or stays absent).
async function refuseRelativeBackupFolder(page: Page): Promise<void> {
  const configPath = path.join(runtimeRoot, "storage-config", "backup.json");
  const before = fileBytes(configPath);
  await page
    .getByLabel("Private destination override")
    .fill("test-user-relative/backups");
  await page
    .getByRole("button", { name: "Save and create first backup" })
    .click();
  await expect(page.getByRole("alert")).toHaveText(
    "The backup folder could not be saved safely.",
  );
  expect(fileBytes(configPath)).toBe(before);
}

function readBackupSchedule(): Record<string, unknown> {
  const result = runLiveMix(
    `schedule = BnestApp.Scheduler.get_schedule("${backupScheduleKey}") |> Map.delete(:__struct__); IO.puts("schedule-json=" <> Jason.encode!(schedule))`,
  );
  expect(result.status, result.stderr).toBe(0);
  const line = result.stdout
    .split("\n")
    .find((entry) => entry.startsWith("schedule-json="));
  if (line === undefined) throw new Error("the backup schedule was not read");
  return JSON.parse(line.slice("schedule-json=".length)) as Record<
    string,
    unknown
  >;
}

function fileBytes(file: string): string | null {
  return existsSync(file) ? readFileSync(file, "utf8") : null;
}

export function connected(page: Page): Promise<void> {
  return expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

function required<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw new Error(`missing ${name}`);
  return value;
}
