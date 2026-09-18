import { createBdd } from "playwright-bdd";
import {
  expectAdminPanels,
  expectDeniedSettings,
  expectNoAdminEntry,
  expectOwnerAllowlists,
  expectScheduleGroups,
  expectTypedBackupLink,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

// Trimmed from bnest-app-e2e's scheduled-backups.steps.ts to this
// project's owned scenarios (contextual schedules, deny access, discover
// typed configuration); the "Save a safe override" scenario moved to
// bnest-app-be-e2e.

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};

const preparations = new Map<string, string>([
  [
    "family and admin-system daily schedules are persisted",
    "contextual_schedules",
  ],
  ["an unauthenticated revoked or non-admin visitor", "denied_visitor"],
  ["multiple domains declare typed admin settings panels", "typed_panels"],
]);

const actions = new Map<string, string>([
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
