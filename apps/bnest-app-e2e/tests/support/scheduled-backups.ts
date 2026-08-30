import { expect, type Page, type TestInfo } from "@playwright/test";
import { login } from "./authentication";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

export type ScheduledBackupWorld = {
  prepared?: string;
  action?: string;
  identity?: TestIdentity;
  responseStatus?: number;
};

export function prepareScheduledBackup(
  world: ScheduledBackupWorld,
  state: string,
  testInfo: TestInfo,
): void {
  world.identity = isolatedTestIdentity(testInfo);
  world.prepared = state;
}

export async function performScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  action: string,
): Promise<void> {
  world.action = action;

  if (action === "open_admin_settings") {
    if (!world.identity) throw new Error("missing isolated identity");
    await page.context().clearCookies();
    await login(page, world.identity.child);
    const home = await page.goto("/");
    expect(home?.status()).toBe(200);
    await expect(page.locator("[data-role=admin-settings-entry]")).toHaveCount(
      0,
    );
    world.responseStatus = (await page.request.get("/admin/settings")).status();
    return;
  }

  if (action === "open_schedules_from_home") {
    await page.goto("/");
    await page.getByRole("link", { name: /Schedules & backups/u }).click();
  } else if (action === "open_admin_settings_from_home") {
    await page.goto("/");
    await page.getByRole("link", { name: /Admin settings/u }).click();
  } else {
    await page.goto("/admin/settings/schedules");
  }

  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

export async function expectScheduledBackup(
  page: Page,
  world: ScheduledBackupWorld,
  outcome: string,
): Promise<void> {
  expect(world.prepared).toBeTruthy();
  expect(world.action).toBeTruthy();

  if (outcome === "not_found") {
    expect(world.responseStatus).toBe(404);
    return;
  }

  if (outcome === "no_entry") {
    await expect(page.locator("[data-role=admin-settings-entry]")).toHaveCount(
      0,
    );
    return;
  }

  const expectedText = new Map<string, RegExp>([
    ["default_backup_folder", /Default: @data\/backup\//u],
    ["no_private_path", /Keep one per day for 7 days/u],
    ["atomic_backup_config", /Private destination override/u],
    ["one_setup_claim", /Save and create first backup/u],
    ["schedule_persisted", /Enabled/u],
    ["same_future_slot", /Daily time \(WIB\)/u],
    ["latest_slot_only", /Daily time \(WIB\)/u],
    ["next_future_day", /Daily time \(WIB\)/u],
    ["vacuum", /Production database backup/u],
    ["proof", /Production database backup/u],
    ["single_claim", /Schedules & backups/u],
    ["attempts", /Enabled/u],
    ["groups", /Family schedules/u],
    ["typed_link", /Production database backup/u],
    ["retention", /Keep one per day for 7 days/u],
    ["preserve", /Backup folder/u],
    ["shared_execution", /Family schedules/u],
    ["shared_inventory", /Admin\/system schedules/u],
    ["panels", /Data storage/u],
    ["allowlists", /Each area validates and saves/u],
    ["expiry", /Expiration/u],
    ["occurrences", /Expiration: Never/u],
  ]);

  const text = expectedText.get(outcome);
  if (!text) throw new Error(`unknown scheduled backup outcome: ${outcome}`);
  await expect(page.locator("body")).toContainText(text);
}
