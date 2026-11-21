import { createBdd } from "playwright-bdd";
import {
  expectDefaultBackupFolder,
  expectVerifiedResultWithoutPrivatePath,
  prepareNoBackupOverride,
  resolveDefaultDestination,
  type DefaultBackupWorld,
} from "../support/default-backup-destination";
import {
  expectSavedFolderAndOneCheck,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

// Trimmed from bnest-app-e2e's scheduled-backups.steps.ts to this
// project's owned, non-exempt scenarios ("A daily backup with no saved
// folder is written to the repository backup folder" and "Saving a backup
// folder confirms the save and queues one first check, however often it is
// submitted"); the contextual-schedules, deny-access, and typed-configuration
// scenarios moved to bnest-app-fe-e2e.

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};
const defaultWorld: DefaultBackupWorld = {};

Given("no backup override exists", ({ page }) =>
  prepareNoBackupOverride(page, defaultWorld),
);

When("the daily backup runs", ({ page }) =>
  resolveDefaultDestination(page, defaultWorld),
);

Then(
  "the backup and its receipt appear in the ignored repository folder and the receipt holds no private path",
  () => {
    expectDefaultBackupFolder(defaultWorld);
    expectVerifiedResultWithoutPrivatePath(defaultWorld);
  },
);

Given("an administrator opened schedules and backups", ({ page, $testInfo }) =>
  prepareScheduledBackup(page, world, "admin_opened_schedules", $testInfo),
);

When("the administrator saves a safe backup override", ({ page }) =>
  performScheduledBackup(page, world, "save_backup_override"),
);

Then(
  "the page shows the saved confirmation, shows the folder when reopened, and one first verification runs for a double submit",
  ({ page }) => expectSavedFolderAndOneCheck(page, world),
);
