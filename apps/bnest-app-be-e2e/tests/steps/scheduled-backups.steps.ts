import { createBdd } from "playwright-bdd";
import {
  expectDefaultBackupFolder,
  expectVerifiedResultWithoutPrivatePath,
  prepareNoBackupOverride,
  resolveDefaultDestination,
  restoreBackupConfiguration,
  type DefaultBackupWorld,
} from "../support/default-backup-destination";
import {
  expectAtomicBackupConfig,
  expectOneSetupClaim,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

// Trimmed from bnest-app-e2e's scheduled-backups.steps.ts to this
// project's owned, non-exempt scenarios ("Use the Dropbox-synced default"
// and "Save a safe override"); the contextual-schedules, deny-access, and
// typed-configuration scenarios moved to bnest-app-fe-e2e.

const { After, Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};
const defaultWorld: DefaultBackupWorld = {};

After(() => restoreBackupConfiguration(defaultWorld));

Given("no backup override exists", ({ page, $testInfo }) =>
  prepareNoBackupOverride(page, defaultWorld, $testInfo),
);

When("the daily backup destination resolves", ({ page }) =>
  resolveDefaultDestination(page, defaultWorld),
);

Then("Bnest uses the ignored repository backup folder", () =>
  expectDefaultBackupFolder(defaultWorld),
);
Then("the verified result exposes no private path", () =>
  expectVerifiedResultWithoutPrivatePath(defaultWorld),
);

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
