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
  expectNoPresentClaim,
  expectNothingToCheck,
} from "../support/backup-integrity-empty";
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
  openWithTrace,
  walkPage,
} from "../support/backup-integrity-layout";
import {
  expectDestinationUnchanged,
  expectLedgerUnchanged,
  openAndReload,
} from "../support/backup-integrity-writes";

// The `Backup files` label scenarios. Split out of
// scheduled-backups.steps.ts to stay under the repository's 300-line
// step-file budget. The refused saves (BN-ADMIN-05, BN-ADMIN-06) stay in
// scheduled-backups.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The page states that every retained backup is present
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The page names each date whose backup is missing or changed
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The page says plainly when there is nothing to check
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The page checks again after the administrator saves
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: Opening the page leaves the backup folder untouched
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The label discloses no private path
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The label names the same dates and states as the reconcile report
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: No horizontal scrolling and no hidden problem appears at any supported width
// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: The label is reachable and announced without a pointer

const { Given, Then, When } = createBdd();
// The `Backup files` label scenarios keep their own facts, reset by the Given that seeds them.
const integrity: IntegrityWorld = {};

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
  ["a ledger holding no verified backup run", "empty_ledger"],
  [
    "an isolated destination with a missing artifact and an unknown file",
    "missing_and_unknown",
  ],
  [
    "an isolated ledger holding two verified runs whose artifacts are absent or changed",
    "two_problems",
  ],
  ["an administrator using only the keyboard and a screen reader", "missing"],
]);

for (const [text, kind] of integrityStates)
  Given(text, ({ page }) => prepareIntegrity(page, integrity, kind));
Given(
  "an administrator who opened Schedules & backups while the label stated that all retained backups are present",
  ({ page }) => openedWhileAllPresent(page, integrity),
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
    openWithTrace(page, integrity, { height, width }),
);
When("the administrator saves the daily schedule", ({ page }) =>
  saveForm(page, integrity, "daily schedule"),
);
When("the administrator saves the backup folder, left unchanged", ({ page }) =>
  saveForm(page, integrity, "backup folder"),
);
When("the administrator opens the page and reloads it", ({ page }) =>
  openAndReload(page, integrity),
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
Then(
  "the label states that there is no verified backup to check yet",
  ({ page }) => expectNothingToCheck(page, integrity),
);
Then("it does not state that the backups are present", ({ page }) =>
  expectNoPresentClaim(page),
);
Then(
  "the destination directory listing and every file's bytes are unchanged",
  ({ page }) => expectDestinationUnchanged(page, integrity),
);
Then("the ledger rows are unchanged", () => expectLedgerUnchanged(integrity));
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
