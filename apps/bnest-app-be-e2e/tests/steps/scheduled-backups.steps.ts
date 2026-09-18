import { createBdd } from "playwright-bdd";
import {
  expectAtomicBackupConfig,
  expectOneSetupClaim,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

// Trimmed from bnest-app-e2e's scheduled-backups.steps.ts to this
// project's one owned, non-exempt scenario ("Save a safe override"); the
// contextual-schedules, deny-access, and typed-configuration scenarios
// moved to bnest-app-fe-e2e.

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};

Given("an administrator opened schedules and backups", ({ page, $testInfo }) =>
  prepareScheduledBackup(page, world, "admin_opened_schedules", $testInfo),
);

When("the administrator saves a safe backup override", ({ page }) =>
  performScheduledBackup(page, world, "save_backup_override"),
);

Then("Bnest stores the private backup configuration atomically", () =>
  expectAtomicBackupConfig(world),
);
Then("Bnest creates one idempotent setup claim for that destination", () =>
  expectOneSetupClaim(world),
);
