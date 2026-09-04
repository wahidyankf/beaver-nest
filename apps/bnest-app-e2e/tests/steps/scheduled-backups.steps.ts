import { createBdd } from "playwright-bdd";
import {
  expectAdminPanels,
  expectAtomicBackupConfig,
  expectDeniedSettings,
  expectNoAdminEntry,
  expectOneSetupClaim,
  expectOwnerAllowlists,
  expectScheduleGroups,
  expectTypedBackupLink,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};

const preparations = new Map<string, string>([
  ["an administrator opened schedules and backups", "admin_opened_schedules"],
  [
    "family and admin-system daily schedules are persisted",
    "contextual_schedules",
  ],
  ["an unauthenticated revoked or non-admin visitor", "denied_visitor"],
  ["multiple domains declare typed admin settings panels", "typed_panels"],
]);

const actions = new Map<string, string>([
  ["the administrator saves a safe backup override", "save_backup_override"],
  [
    "an administrator follows schedules and backups from home",
    "open_schedules_from_home",
  ],
  ["the visitor opens an admin settings route", "open_admin_settings"],
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
  When(text, ({ page }) => performScheduledBackup(page, world, action));

Then("Bnest stores the private backup configuration atomically", () =>
  expectAtomicBackupConfig(world),
);
Then("Bnest creates one idempotent setup claim for that destination", () =>
  expectOneSetupClaim(world),
);
Then("both contexts appear in separate groups with safe status", ({ page }) =>
  expectScheduleGroups(page, world),
);
Then("the backup row links to its typed settings", ({ page }) =>
  expectTypedBackupLink(page),
);
Then("Bnest returns not found before protected reads", () =>
  expectDeniedSettings(world),
);
Then("home exposes no admin settings entry", ({ page }) =>
  expectNoAdminEntry(page),
);
Then("every declared panel is discoverable", ({ page }) =>
  expectAdminPanels(page),
);
Then("each owner validates and saves only its allowlisted fields", ({ page }) =>
  expectOwnerAllowlists(page),
);
