# Product Requirements — Backup Integrity

## Personas

- **Household operator:** the repository owner. Runs Mix tasks on the host, reads the Schedules page, owns Dropbox, and
  approves anything that touches production data.
- **Maintainer (human or agent):** changes Backup code and needs a test that fails when the isolation or retention
  guarantees break.

## User Stories

- As the operator, I can learn which verified runs have no artifact on disk, without reading the database by hand.
- As the administrator, I can see on the Schedules & backups page whether the retained backups are on disk, and which
  dates are not, without running a command.
- As the operator, I can see how the two missing nights were lost, or be told plainly what could not be established
  (the Dropbox event history is unavailable to me, so a Dropbox cause may stay unproven).
- As the operator, I can restore a real backup into a throwaway root and see that its contents are readable.
- As a maintainer, I know a test can never remove or keep a production artifact.

## Scenario Identifiers

Identifiers are stable. Delivery items cite them. Scenarios marked **conditional** apply only on the branch the
Phase 3 verdict selects (or, for AC-BI-14, while its Given holds), and are otherwise recorded `Not applicable` with
that reason. The branch table in [`tech-docs.md`](tech-docs.md#branch-selection) states which verdict selects which
conditional criterion (AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-19).

AC-BI-21 to AC-BI-23 and the page scenario of AC-BI-19 are **UI-affecting**: the owner added an administrator-facing
label on 2026-10-03 (OD-3). Each names its route, rendered states and supported viewport classes, as
[Plan UI Design](../../../repo-governance/conventions/plan-ui-design.md) requires. AC-BI-20 is not used: decision D2
retired it before it was defined, and its number is never reused.

**Pending decisions.** D2 (which retired AC-BI-20), D8 (the re-check after a save in AC-BI-21), D9 (the viewport rows of
AC-BI-23) and D10 (the empty-ledger scenario of AC-BI-17) are agent proposals pending owner confirmation, not owner
decisions, and these criteria change with them.

## Acceptance Criteria

### AC-BI-01 — The investigation changes nothing in production

```gherkin
Scenario: Read-only investigation leaves production untouched
  Given the backup directory listing, the ownership marker bytes, the private configuration directory listing and the
    ledger row count were recorded before Phase 2, between scheduled slots
  And the ledger was read from a scratch copy, so SQLite never opened the production database or touched its
    sidecar files
  And the live reconcile runs of Phase 5 and Phase 13 read the ledger the same way
  When Phase 2 has finished
  Then the same listing, marker bytes, configuration listing and row count are recorded after it, equal under the
    comparison rule
  And no pre-existing file under the backup directory or the private configuration directory has a later
    modification time, except the modification time of the storage lock directory the comparison rule excludes
```

**Comparison rule.** Equality excludes only entries created or removed by a scheduled slot inside the window: the new
artifact and receipt pair whose ledger row carries that slot's `scheduled_for`, the owned pair that slot's retention
removed, and that slot's ledger rows. Each excluded difference must be justified by a ledger row in the window. The
nightly slot is 19:00 UTC, so Phase 2 is started and finished between slots; the rule covers a slot that arrives anyway.

**Amendment (owner decision, 2026-10-04).** The comparison also excludes the modification time of the `storage.json.lock`
directory under the private configuration directory. The running service rewrites that directory's modification time
about every 30 seconds as a heartbeat on its storage lock; it is a service-owned change, not a write by this
execution, and no other entry in either directory is excluded on this ground. Phase 2 found the difference (see
[`learnings.md`](learnings.md), entry V0.12); the owner amended the rule on 2026-10-04. The amendment applies to every
comparison this plan makes: Phase 2, the Phase 5 early live reconcile and the Phase 13 re-run.

### AC-BI-02 — The verdict is evidenced and discriminating

```gherkin
Scenario: The cause verdict eliminates or confirms each hypothesis by named evidence
  Given the investigation evidence is recorded in learnings.md
  When the Phase 3 verdict is read
  Then it names one cause class: retention, Dropbox, other writer or test pollution, different destination, ledger
    anomaly, or unproven
  And each of the five hypotheses H1 to H5 carries the observation that confirmed or eliminated it, or is recorded
    unproven with the observation that would settle it (H3a is a candidate mechanism inside H3)
  And H2 is recorded unproven unless a local signal confirmed it, because the Dropbox event history is unavailable
  And a verdict of unproven states which observation would settle it
```

The owner decided on 2026-10-03 (OD-2) that Dropbox web access is not available, so the deleted-files list, the event
history and the linked-device list cannot be read. H2 can be confirmed only by a local signal (a conflicted copy, a
placeholder or a Dropbox extended attribute) and otherwise ends unproven. An unproven H2 beside eliminated H1, H3, H4
and H5 yields the verdict `C-UNPROVEN`, which is a complete and expected outcome.

### AC-BI-03 — A verified run with no artifact is reported

```gherkin
Scenario: Reconciliation reports a verified run whose artifact is absent
  Given an isolated destination holding two receipts and artifacts for retained dates
  And the ledger holds a third verified run for a retained date whose artifact and receipt are absent
  When reconciliation runs
  Then it reports that run as missing, with its scheduled date and artifact basename
  And it reports the two intact runs as present
```

### AC-BI-04 — A changed artifact is reported

```gherkin
Scenario: Reconciliation reports an artifact whose bytes no longer match the ledger
  Given a verified run whose artifact exists with a different digest from the ledger
  When reconciliation runs
  Then it reports that run as changed
```

### AC-BI-05 — Retention-removed history is not a false alarm

```gherkin
Scenario: Reconciliation ignores verified runs older than the retained dates
  Given a verified run whose WIB date is older than the seven latest retained dates
  And its artifact was legitimately removed by retention
  When reconciliation runs
  Then it does not report that run
```

### AC-BI-06 — Reconciliation is read-only

```gherkin
Scenario: Reconciliation never writes
  Given an isolated destination with a missing artifact and an unknown file
  When reconciliation runs
  Then the destination directory listing and every file's bytes are unchanged
  And the ledger rows are unchanged
```

### AC-BI-07 — The report discloses no private path

```gherkin
Scenario: The report carries no path
  Given reconciliation found a missing artifact
  When the Mix task's printed report and the post-run log line are read
  Then neither contains a filesystem path, a digest, or a destination identifier
```

### AC-BI-08 — Foreign receipts never influence retention (conditional)

```gherkin
Scenario: Receipts and artifacts of another destination or without a valid receipt are never removed or counted
  Given a destination holding owned pairs for eight WIB dates
  And receipts bearing another destination identifier, unreceipted artifacts, and a malformed receipt
  When retention runs
  Then exactly the owned pairs outside the seven latest dates are removed
  And every foreign receipt, unreceipted artifact and malformed receipt is untouched
  And no foreign receipt changes which owned run is kept for a date
```

### AC-BI-09 — A test cannot reach the production backup directory (conditional)

```gherkin
Scenario: The test environment refuses the production backup destination
  Given the test environment
  When a test resolves or writes to the repository's default backup directory
  Then the operation fails closed before any file is created
  And the production directory listing is unchanged
```

### AC-BI-10 — The cause-specific defect is reproduced and removed (conditional)

```gherkin
Scenario: The reproduction from the verdict fails before the fix and passes after it
  Given the Phase 3 verdict names a repository-side cause and its minimal reproduction
  When the reproduction runs against the code before the fix
  Then it fails for the reason the verdict names
  And after the fix the same reproduction passes
```

### AC-BI-11 — A real backup restores into an isolated root

```gherkin
Scenario: The owner restores one production artifact
  Given the owner selected one present production artifact
  When the owner runs the restore drill task against it
  Then the task restores into a fresh isolated root it created
  And it prints redacted evidence of readable rooms, ordered messages and subscription structure
  And the production artifact and the live database are unchanged
```

### AC-BI-12 — The release keeps the service available

```gherkin
Scenario: A Bnest code change is released without interrupting the routed origin
  Given a candidate backend passed local health and a LiveView and WebSocket check
  When Caddy is switched to the candidate with a graceful reload
  Then continuous samples of the exact routed origin show zero failures
  And p95 latency is at most 500 ms and no sample exceeds 2 seconds
  And connected clients reconnect without a manual refresh
  And any nightly slot that falls in the window has exactly one ledger row, whichever backend ran it
```

### AC-BI-13 — The routed backend serves the intended revision

```gherkin
Scenario: The routed backend reports the revision containing the change
  Given the release completed and the drain finished
  When the routed origin and the loopback backend are queried for their revision
  Then both report the release revision
  And no candidate, watcher or temporary proxy remains running
```

### AC-BI-14 — The live detector reports the known gap (conditional on the window)

```gherkin
Scenario: Reconciliation against production reports the two missing nights while they are retained dates
  Given the detector, run from the execution checkout once it exists or from the released revision, and the owner's
    approval for a read-only production run
  And the slots of 2026-09-30T19:00Z and 2026-10-01T19:00Z are still among the seven latest WIB dates
  When reconciliation runs against the production ledger and backup directory
  Then it reports those two slots as missing
  And it reports the other retained verified runs as present
  And the production directory listing is unchanged
```

If the two slots have aged out of the retained window before this runs, the scenario is recorded `Not applicable`
because its Given never arose, and the live proof reduces to the other retained runs being reported present.

### AC-BI-15 — A superseded same-date run is not a false alarm

```gherkin
Scenario: Reconciliation reports only the newest verified run of each retained date
  Given two verified runs share one retained WIB date and only the newer artifact is present
  When reconciliation runs
  Then it reports the newer run as present
  And it does not report the older run
```

### AC-BI-16 — Reconciliation never fails the backup

```gherkin
Scenario: A reconciliation that raises leaves the backup verified
  Given a scheduled backup in an isolated destination whose post-run reconciliation raises
  When the scheduled run completes
  Then the run is recorded verified and its artifact and receipt exist
  And one path-free error line states that reconciliation failed
```

### AC-BI-17 — The reconcile task's exit status follows its report

```gherkin
Scenario: The task exits zero only when at least one expected run exists and every expected run is present
  Given an isolated destination and ledger in which at least one expected run exists and every expected run is present
  When the reconcile task runs
  Then it exits 0 and prints the summary line stating that all N retained backups are present
  And it prints no per-date line
  And it starts no scheduler

Scenario: The task exits non-zero when a run is missing, changed or unreadable
  Given an isolated destination and ledger with one missing run, or one changed run, or an unreadable ledger
  When the reconcile task runs
  Then it exits non-zero
  And the report names the date and state of each problem run, or states a path-free reason when unreadable
  And the report contains no path, digest, destination identifier or run ID

Scenario: The task does not report an empty ledger as present
  Given an isolated destination and a ledger holding no verified backup run
  When the reconcile task runs
  Then it prints that there is no verified backup to check yet
  And it prints no date as present and does not state that backups are present
  And it exits non-zero
  And it starts no scheduler
```

**Reconciliation note (agent-proposed resolution, 2026-10-04, pending owner confirmation).** Gate pass 6 found that
"prints each date as present" contradicted the all-present summary wording `Backup files: all N retained backups are
present`. The first scenario now names the summary line and no per-date line; the Phase 5 RED says the same.

An empty set of expected runs is vacuously all present; the task must not let that read as healthy, so the empty ledger
is neither an exit `0` nor a `present` line (decision D10). The same words are the label's nothing-to-check state, which
the page shows as a neutral designed state rather than an error (AC-BI-21).

### AC-BI-18 — The restore drill refuses a foreign target

```gherkin
Scenario: The restore drill restores only a regular file inside the configured destination
  Given an isolated configured destination, a regular file outside it, and a non-regular entry inside it
  When the restore drill task is run against each
  Then it exits non-zero and restores nothing
  And no restore root is created and the live database is not opened
```

### AC-BI-19 — A destination change is reported for surviving receipts (conditional: C-DEST)

The ledger records no destination, so this criterion sees only receipts that survive on disk. A run lost without a
surviving receipt is reported as missing (AC-BI-03) and is never attributed to a destination.

```gherkin
Scenario: Reconciliation reports a surviving receipt whose destination differs from the current marker's
  Given an isolated destination whose marker names one destination identity
  And a receipt in it, for a retained date, that names a different destination identity
  When reconciliation runs
  Then it reports that receipt's date as a destination mismatch
  And the report names neither identifier
  And the report states that it cannot see runs lost without a surviving receipt
```

The label scenario below is the page-facing half of this criterion and applies on the same branch. Route
`/admin/settings/schedules`; rendered state: destination mismatch; viewport classes: desktop, tablet and mobile.

```gherkin
Scenario: The Schedules page labels a destination mismatch without naming either identity
  Given an administrator and an isolated destination whose marker names one destination identity
  And a receipt in it, for a retained date, that names a different destination identity
  When the administrator opens Schedules & backups
  Then the label lists that date as a destination mismatch
  And the page names neither identifier
  And the label states that runs lost without a surviving receipt cannot be seen this way
```

### AC-BI-21 — The Schedules page labels backup integrity

**Route:** `/admin/settings/schedules` (administrators only). **Rendered states:** checking, all present, needs
attention (a retained date missing or changed), could not be checked, and nothing to check yet. **Viewport classes:**
desktop, tablet and mobile, as defined under AC-BI-23.

**Production proof is partial by design.** Once the two lost nights have aged out of the seven latest retained dates, the
production page will likely show only the all-present state. Needs attention, could not be checked, nothing to check yet
and checking are therefore proved at the isolated exact origin (Phase 10), not on production; the owner's own look in
Phase 13 reports whichever state the label showed and claims no other.

```gherkin
Scenario: The page states that every retained backup is present
  Given an administrator and an isolated destination holding the artifact of every expected verified run
  When the administrator opens Schedules & backups
  Then the Production database backup section carries a backup-files label stating that all retained backups are present
  And the label lists no problem date
```

```gherkin
Scenario: The page names each date whose backup is missing or changed
  Given an isolated ledger holding one verified run whose artifact is absent and one whose bytes differ from the ledger
  When the administrator opens Schedules & backups
  Then the label states how many retained backups need attention
  And it lists each problem as its date and its state, missing or changed
  And the label lists the intact retained dates as present or counts them as present
```

```gherkin
Scenario: The page says plainly when the check could not run
  Given a reconciliation that raises or a ledger that cannot be read
  When the administrator opens Schedules & backups
  Then the label states that the backup files could not be checked
  And the rest of the page is rendered and its forms remain usable
```

```gherkin
Scenario: The page says plainly when there is nothing to check
  Given a ledger holding no verified backup run
  When the administrator opens Schedules & backups
  Then the label states that there is no verified backup to check yet
  And it does not state that the backups are present
```

```gherkin
Scenario Outline: The page checks again after the administrator saves
  Given an administrator who opened Schedules & backups while the label stated that all retained backups are present
  And an expected artifact is then removed from the isolated destination
  When the administrator saves the <form>
  Then the label reads checking until the new result arrives
  And it then states that one retained backup needs attention
  And the focus does not move

Examples:
  | form                          |
  | daily schedule                |
  | backup folder, left unchanged |
```

### AC-BI-22 — The label is read-only, bounded and path-free

**Route:** `/admin/settings/schedules`. **Rendered states:** checking and every result state of AC-BI-21.
**Viewport classes:** desktop, tablet and mobile.

```gherkin
Scenario: Rendering the label never writes
  Given an isolated destination with a missing artifact and an unknown file
  When the administrator opens the page and reloads it
  Then the destination directory listing and every file's bytes are unchanged
  And the ledger rows are unchanged
```

```gherkin
Scenario: The label discloses no private path
  Given reconciliation found a missing artifact
  When the page's rendered text and attributes are read
  Then they contain no filesystem path, digest, destination identifier or run ID
  And they name the same dates and states as the reconcile task's report
```

```gherkin
Scenario: The label does not delay the page
  Given a reconciliation that takes longer than the page's wait ceiling
  When the administrator opens the page
  Then the page and its forms are rendered and usable before the result arrives
  And the label reads checking until the result or the ceiling
  And at the ceiling the label states that the backup files could not be checked
  And the check is cancelled at the ceiling and nothing keeps reading the destination afterwards
```

```gherkin
Scenario: A non-administrator causes no integrity check
  Given a visitor who is not an administrator
  When the visitor opens the schedules route
  Then Bnest returns not found before any protected read
  And no reconciliation is started
```

### AC-BI-23 — The label is usable at every supported width, without a pointer and without colour

**Route:** `/admin/settings/schedules`. **Rendered states:** checking, all present, needs attention, could not be
checked, nothing to check yet (and destination mismatch on the C-DEST branch). **Viewport classes:** desktop, tablet
and mobile, the three the `bnest-app-fe-e2e` projects drive; manual checks use 1440 × 900, 768 × 1024 and 393 × 851,
with the 320 px reflow floor checked inside the mobile class.

```gherkin
Scenario Outline: No horizontal scrolling and no hidden problem appears at any supported width
  Given the Schedules page is open at <viewport> with a label listing two problem dates
  Then the page does not scroll horizontally
  And each problem line is fully visible, wrapped rather than truncated
  And each problem is conveyed by text, not by colour alone

Examples:
  | viewport    |
  | 320 x 568   |
  | 393 x 851   |
  | 768 x 1024  |
  | 1440 x 900  |
```

The browser binding sets the viewport from each Examples row (`page.setViewportSize`), so the 320 x 568 and 1440 x 900
rows run at their own width even though the `bnest-app-fe-e2e` projects default to 1280 x 720, 768 x 1024 and the Pixel 5
profile; no row is exempted from the browser (decision D9). The manual matrix in Phase 10 remains the viewport-class
proof and the executor's inspection of the exact origin.

```gherkin
Scenario: The label is reachable and announced without a pointer
  Given an administrator using only the keyboard and a screen reader
  When the administrator moves through the page in reading order
  Then the label is announced with its name and its state in its place before the forms
  And the focus order of the existing controls is unchanged
  And the change from checking to the result is announced politely and does not move focus
```

## Product Scope

In scope: the criteria above, including the administrator-facing label on the Schedules & backups page that the owner
selected on 2026-10-03 (OD-3). Not in scope: restoring the lost nights; changes to the Schedules page beyond the
integrity label; push or email notification; encrypting artifacts.

## Product Risks

| Risk                                                         | Mitigation                                                                                                            |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| The detector cries wolf on legitimate retention              | AC-BI-05 pins the retained-date window to the same function retention uses                                            |
| The report leaks a path or identifier into a public record   | AC-BI-07; evidence recorded as dates and counts only                                                                  |
| The drill touches the live database                          | AC-BI-11 restores only into a root the task creates; AC-BI-18 refuses any other target                                |
| The detector fails the nightly backup                        | AC-BI-16 wraps reconciliation so it can never change the run's outcome                                                |
| The label slows or breaks the admin page                     | AC-BI-22: the check runs off the render path under a ceiling, and a failure renders the could-not-be-checked state    |
| The label contradicts the Mix task or the log                | AC-BI-22: one wording function serves the label, the log, the telemetry metadata and the task                         |
| The label is unreadable on a phone or without colour         | AC-BI-23 at four widths, with text cues and a polite announcement; Phase 10 inspects every state at the exact origin  |
| An empty ledger reads as healthy                             | AC-BI-17 and AC-BI-21: the empty case prints nothing-to-check, the task exits non-zero, and no surface says `present` |
| The label shows a stale result after the administrator saves | AC-BI-21: the check runs again after every successful save and the label reads checking meanwhile                     |
