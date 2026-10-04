import { createBdd } from "playwright-bdd";
import {
  expectCheckingThenResult,
  expectFocusStays,
  expectMatchesReport,
  expectOneNeedsAttention,
  expectPrivateFree,
  readReport,
} from "../support/backup-integrity-change";
import {
  expectAllPresent,
  expectAttentionCount,
  expectIntactCounted,
  expectNoProblemDate,
  expectProblemLines,
  openedWhileAllPresent,
  openSchedules,
  prepareIntegrity,
  readLabelHtml,
  removeExpectedArtifact,
  saveForm,
  type IntegrityWorld,
} from "../support/backup-integrity-label";
import {
  expectAnnouncedInPlace,
  expectFocusOrderUnchanged,
  expectNoHorizontalScroll,
  expectPoliteAnnouncement,
  expectProblemLinesWhole,
  expectProblemsInText,
  walkPage,
} from "../support/backup-integrity-layout";
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
// The `Backup files` label scenarios keep their own facts, reset by the Given that seeds them.
const integrity: IntegrityWorld = {};

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

// Each Given seeds the routed run's isolated ledger and backup directory in the named state.
const integrityStates = new Map<string, string>([
  [
    "an administrator and an isolated destination holding the artifact of every expected verified run",
    "all_present",
  ],
  [
    "an isolated ledger holding one verified run whose artifact is absent and one whose bytes differ from the ledger",
    "missing_and_changed",
  ],
  ["reconciliation found a missing artifact", "missing"],
  [
    "an isolated ledger holding two verified runs whose artifacts are absent or changed",
    "two_problems",
  ],
  ["an administrator using only the keyboard and a screen reader", "missing"],
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

for (const [text, kind] of integrityStates)
  Given(text, ({ page, $testInfo }) =>
    prepareIntegrity(page, integrity, kind, $testInfo),
  );
Given(
  "an administrator who opened Schedules & backups while the label stated that all retained backups are present",
  ({ page, $testInfo }) => openedWhileAllPresent(page, integrity, $testInfo),
);
Given(
  "an expected artifact is then removed from the isolated destination",
  () => removeExpectedArtifact(integrity),
);

When("the administrator opens Schedules & backups", ({ page }) =>
  openSchedules(page, integrity),
);
When(
  "the administrator opens Schedules & backups at {int} x {int}",
  ({ page }, width: number, height: number) =>
    openSchedules(page, integrity, { height, width }),
);
When("the administrator saves the daily schedule", ({ page }) =>
  saveForm(page, integrity, "daily schedule"),
);
When("the administrator saves the backup folder, left unchanged", ({ page }) =>
  saveForm(page, integrity, "backup folder"),
);
When("the page's rendered text and attributes are read", ({ page }) =>
  readLabelHtml(page, integrity),
);
When("the administrator moves through the page in reading order", ({ page }) =>
  walkPage(page, integrity),
);

Then(
  "the Production database backup section carries a backup-files label stating that all retained backups are present",
  ({ page }) => expectAllPresent(page, integrity),
);
Then("the label lists no problem date", ({ page }) =>
  expectNoProblemDate(page),
);
Then("the label states how many retained backups need attention", ({ page }) =>
  expectAttentionCount(page, integrity),
);
Then(
  "it lists each problem as its date and its state, missing or changed",
  ({ page }) => expectProblemLines(page, integrity),
);
Then(
  "the label lists the intact retained dates as present or counts them as present",
  ({ page }) => expectIntactCounted(page, integrity),
);
Then("the label reads checking until the new result arrives", ({ page }) =>
  expectCheckingThenResult(page, integrity),
);
Then("it then states that one retained backup needs attention", ({ page }) =>
  expectOneNeedsAttention(page, integrity),
);
Then("the focus does not move", ({ page }) =>
  expectFocusStays(page, integrity),
);
Then(
  "they contain no filesystem path, digest, destination identifier or run ID",
  () => expectPrivateFree(integrity),
);
Then(
  "they name the same dates and states as the reconcile task's report",
  async ({ page }) => {
    readReport(integrity);
    await expectMatchesReport(page, integrity);
  },
);
Then("the page does not scroll horizontally", ({ page }) =>
  expectNoHorizontalScroll(page, integrity),
);
Then(
  "each problem line is fully visible, wrapped rather than truncated",
  ({ page }) => expectProblemLinesWhole(page, integrity),
);
Then("each problem is conveyed by text, not by colour alone", ({ page }) =>
  expectProblemsInText(page, integrity),
);
Then(
  "the label is announced with its name and its state in its place before the forms",
  ({ page }) => expectAnnouncedInPlace(page, integrity),
);
Then("the focus order of the existing controls is unchanged", ({ page }) =>
  expectFocusOrderUnchanged(page),
);
Then(
  "the change from checking to the result is announced politely and does not move focus",
  ({ page }) => expectPoliteAnnouncement(page),
);
