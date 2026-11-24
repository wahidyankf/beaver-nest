import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { runLiveMix } from "../support/routed-rollout";
import {
  expectAdminPanels,
  expectDeniedSettings,
  expectNoAdminEntry,
  expectNoHostPathOrInventory,
  expectOwnerAllowlists,
  expectScheduleGroups,
  expectTypedBackupLink,
  openDeniedRoute,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

// Trimmed from bnest-app-e2e's scheduled-backups.steps.ts to this
// project's owned scenarios (contextual schedules, deny access, discover
// typed configuration, refused schedule and folder saves); the "Save a safe
// override" scenario moved to bnest-app-be-e2e, and the `Backup files` label
// scenarios live in scheduled-backups-label.steps.ts.

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};

const preparations = new Map<string, string>([
  [
    "family and admin-system daily schedules are persisted",
    "contextual_schedules",
  ],
  ["an unauthenticated revoked or non-admin visitor", "denied_visitor"],
  ["several areas of Bnest offer admin settings panels", "typed_panels"],
]);

const actions = new Map<string, string>([
  [
    "an administrator follows schedules and backups from home",
    "open_schedules_from_home",
  ],
  [
    "an administrator opens admin settings from home",
    "open_admin_settings_from_home",
  ],
]);

for (const [text, state] of preparations)
  Given(text, ({ page, $testInfo }) =>
    prepareScheduledBackup(page, world, state, $testInfo),
  );

for (const [text, action] of actions)
  When(text, ({ page }) => performScheduledBackup(page, action));

Then("both contexts appear in separate groups with safe status", ({ page }) =>
  expectScheduleGroups(page, world),
);
Then("the backup row links to its typed settings", ({ page }) =>
  expectTypedBackupLink(page),
);
When("the visitor opens the route {string}", ({ page }, route: string) =>
  openDeniedRoute(page, world, route),
);
Then("Bnest returns not found before protected reads", () =>
  expectDeniedSettings(world),
);
Then("Bnest reveals no host path or migration inventory", () =>
  expectNoHostPathOrInventory(world),
);
Then("home exposes no admin settings entry", ({ page }) =>
  expectNoAdminEntry(page),
);
Then("every settings panel is listed in admin settings", ({ page }) =>
  expectAdminPanels(page),
);
Then(
  "each settings panel saves only the fields it offers and refuses any other field",
  ({ page }) => expectOwnerAllowlists(page),
);

// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A stale schedule save says to reload and try again
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A bad backup folder gets a plain refusal reason

// The refused schedule and folder saves (BN-ADMIN-05, BN-ADMIN-06). The bad-time
// row (BN-ADMIN-04) is e2e-exempt: a real browser cannot submit a malformed
// `type="time"` value, so it runs at integration and unit only and has no
// binding here.

async function openSchedulesPage(page: import("@playwright/test").Page) {
  await page.goto("/admin/settings/schedules");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

Given(
  "an administrator with a saved daily schedule opens Schedules & backups",
  async ({ page }) => {
    await openSchedulesPage(page);
  },
);

Given("an administrator opens Schedules & backups", async ({ page }) => {
  await openSchedulesPage(page);
});

When(
  "the administrator saves the daily schedule with the time {string}",
  async ({ page }, time: string) => {
    await page.locator("#daily-time-wib").fill(time);
    await page.getByRole("button", { name: "Save schedule" }).click();
  },
);

When(
  "another schedule save moves the daily schedule to {string}",
  async ({ page }, time: string) => {
    const rival = await page.context().newPage();
    try {
      await rival.goto("/admin/settings/schedules");
      await expect(rival.locator("[data-phx-main]")).toHaveClass(
        /phx-connected/u,
      );
      await rival.evaluate((value: string) => {
        const input =
          document.querySelector<HTMLInputElement>("#daily-time-wib");
        if (!input) throw new Error("no daily time input");
        input.value = value;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }, time);
      await rival.getByRole("button", { name: "Save schedule" }).click();
      await expect(rival.locator(".admin-settings-status")).toContainText(
        "Daily schedule saved.",
      );
    } finally {
      await rival.close();
    }
  },
);

When(
  "the administrator saves the backup folder {string}",
  async ({ page }, folder: string) => {
    await page.locator("#backup-directory").fill(folderDirectory(folder));
    await page
      .getByRole("button", { name: "Save and create first backup" })
      .click();
  },
);

// Each outline kind becomes a folder the run owns: the live database's own
// directory for the overlap refusal, a fresh symlink for the link refusal,
// and a relative path for the remaining refusal.
function folderDirectory(folder: string): string {
  if (folder === "inside the live database location") {
    const result = runLiveMix(
      'BnestApp.Storage.database_path() |> Path.dirname() |> Path.join("backups") |> IO.puts()',
    );
    if (result.status !== 0) throw new Error(result.stderr);
    return result.stdout.trim();
  }
  if (folder === "a symbolic link") {
    const root = mkdtempSync(path.join(tmpdir(), "bnest-bad-folder-"));
    const target = path.join(root, "target");
    const link = path.join(root, "link");
    rmSync(link, { force: true, recursive: true });
    symlinkSync(target, link);
    return path.join(link, "backups");
  }
  if (folder === "a relative path") return "relative/backup";
  throw new Error(`unknown backup folder kind: ${folder}`);
}

Then(
  "the schedules page shows the schedule error {string}",
  async ({ page }, message: string) => {
    await expect(page.locator("#settings-error")).toHaveText(message);
  },
);

Then("the other schedule save stays", async ({ page }) => {
  await page.reload();
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await expect(page.locator("#daily-time-wib")).toHaveValue("04:00");
});

Then(
  "the schedules page shows the backup error {string}",
  async ({ page }, message: string) => {
    await expect(page.locator("#settings-error")).toHaveText(message);
  },
);

Then("nothing is saved and no first backup is queued", async ({ page }) => {
  await expect(page.locator(".admin-settings-status")).toHaveCount(0);
  await expect(page.locator("#settings-error")).toBeVisible();
});
