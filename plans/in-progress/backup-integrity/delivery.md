# Delivery

## Execution Status and Authority

**In progress (2026-10-04).** Phases 1 and 2 were executed on 2026-10-04 (pre-state 07:28Z, post-state 07:37Z, between
the slots of 2026-10-03T19:00Z and 2026-10-04T19:00Z); Phases 3 to 5 were executed the same day (V1 recorded, the specifications and the detector built, the early live reconcile run at 09:21Z); Phase 6 is not started and waits for the owner's confirmation of V1. The plan sits in
`plans/in-progress/`; the gate verdict is recorded in the first Phase 1 item (`PASS_WITH_FINDINGS`, gate pass 6). Read all six plan
documents and the [plan-execution workflow](../../../repo-governance/workflows/plan/plan-execution.md) first. Start only
from a current, explicitly authorized, non-blocking verdict (`PASS`, or `PASS_WITH_FINDINGS` with every finding
recorded). Phase 1 moves the folder to `plans/in-progress/` once execution is authorized.

**Schedule pressure.** The two lost nights stay reportable by the live detector only while they are among the seven
latest WIB dates, which ends for the first of them when the run of WIB 2026-10-08 (the slot of 2026-10-07T19:00Z)
finishes retention; the second lost night follows one slot later. Phases 1 to 5 are therefore ordered first. None of their
items waits on a UI item or on the owner's confirmation of the verdict (agent proposal D11, pending owner confirmation),
and the idea brief waits until after Phase 5. The admin-page label (OD-3) has its design assets in this plan (the owner's
F1 resolution, carried out by D6): Phase 8 reconciles their copy
and records the owner's design review, Phase 9 builds the label and Phase 10 inspects it, all after Phase 7. The early
live reconcile in Phase 5 never waits on the label. The [Dated Preconditions](#dated-preconditions) before Phase 1 give
the latest authorization and Phase 2 completion dates, and Phase 5 states the dispositions recorded if the window is at
risk.

**Plan Quality Gate.** **No verdict is current for the folder as it now stands.** Gate pass 5 of 2026-10-04 returned
`plan-quality-gate: PASS_WITH_FINDINGS` (M1 and M2 Medium, L1 to L5 Low) on the folder as it stood after the fourth
propagation; a fifth propagation then changed it. Three plan-checker passes ran on 2026-10-03 against the draft that
preceded the expansion; the third returned `PASS_WITH_FINDINGS`. The owner then decided OD-1 to OD-4
([`tech-docs.md`](tech-docs.md#owner-decisions-of-2026-10-03)), and OD-3 expanded the plan with the UI Design section,
Phases 8 to 10, acceptance criteria AC-BI-21 to AC-BI-23, and file, README and phase-numbering changes. Those earlier
results describe a different folder and do not carry over. Pass 4 ran on the expanded folder and returned `BLOCKED` on
one High finding, F1: the UI design assets were deferred to Phase 8 although the convention requires them in the plan.
The owner resolved F1 by having them drawn in the plan now (D6 carries this out), and a fourth propagation produced the
twelve assets with their README and comparison and repaired F2 to F7 with agent proposals D8 to D11 that the owner has
not yet confirmed. The fifth propagation applied the seven findings of pass 5 within the recorded decisions: M1, the
Shape Choice of `tech-docs.md` rewritten against the owner as a distinct reader of the UI Design and the decision
tables, the file kept as one; M2, the [Dated Preconditions](#dated-preconditions) before Phase 1 and the Phase 2
dispositions (an extension of agent proposal D11); L1, the PRD preamble note that D2 and D8 to D10 are pending; L2, the
BRD risk row; L3, the backlog index summary; L4, a Phase 4 Rule pinning the state-to-wording mapping, with the Phase 5
wording items citing AC-BI-07 and AC-BI-17 only; and L5, the Phase 9 styling item labelled as format and lint proof. The
gate has not been re-run on the folder as the fifth propagation left it; the first Phase 1 item records its terminal
verdict line, which is the proof, and stays unticked. The owner's confirmation of the items in
[Pending Owner Confirmation](tech-docs.md#pending-owner-confirmation) is also pending; the reads R1 to R4 are the
exception, confirmed on 2026-10-03 ([Confirmed by the Owner](tech-docs.md#confirmed-by-the-owner)).

Authority is split. On 2026-10-03 the owner approved the read-only production reads (OD-1) and the four reads that its
enumeration does not name (R1 to R4), decided that Dropbox web access is not available (OD-2), selected the admin-page
label (OD-3) and approved an idea brief for an off-Dropbox second copy (OD-4). The repository owner still authorizes
execution and is the authority for: confirming the verdict V1 (proposed in D11 to fall before Phase 6 and before the
Phase 12 release), the design review of Phase 8, the restore drill, the owner's own look at the label on the live
origin, and any write to the production backup directory or `~/.config/bnest/*`. **No item in this plan writes to either
of those two locations.** If execution finds that one must, it stops and asks.

**Decision provenance.** The decisions the owner actually made are OD-1 to OD-4, the reads R1 to R4, D1 and the
resolution of F1 (the UI design assets drawn in the plan now, carried out by D6). Everything else is an agent proposal
pending owner confirmation, as [`tech-docs.md`](tech-docs.md#pending-owner-confirmation) lists: D2 to D5, D6 beyond the
F1 resolution, D7 to D11 (including the Dated Preconditions and the fallback decision point of 2026-10-07T12:00Z in
Phase 5), and the gate resolutions G1 to G12 and P1 to P6. "Decision Dn" elsewhere in this file points at a row of the decision record and says
nothing about who made it.

Every test item follows the project rule: Gherkin, then bindings, then an Nx red, then code, then smoke. A pin that is
expected to pass on its first run is a characterization test: it predeclares a mutation, and the failing mutated run is
its red-equivalent. Test data uses isolated roots and synthetic `test-user-` identities; cleanup runs in `on_exit` or
`finally`. Never read or mutate production user or message data. Investigation reads are not tests and record dates,
counts and yes/no observations only.

Every command runs at the repository root with `rtk`. Restartable Nx work has one outer checksum-pinned `./hippo`
guard; self-guarded `test:e2e`, `serve` and `release:run` targets get no second guard. Exit `75` is requeued only when
its receipt says `never-started`; exit `73` cleans owned storage; exit `78` stops for replanning.

Commits follow [thematic commits](../../../repo-governance/conventions/thematic-commits.md) and are made only when
authorized or plan-approved under [commit authorization](../../../repo-governance/conventions/commit-authorization.md).
Each unit ends with a commit item that records the authorization or `No commit authorized`.

## Canonical Commands

| ID                | Exact command                                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `BE_UNIT`         | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit:be`                |
| `INTEGRATION`     | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`            |
| `BEHAVIOUR`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour`     |
| `APP_QUICK`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:quick`                  |
| `RELEASE_TEST`    | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`                |
| `REPO`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`              |
| `FE_E2E_COVERAGE` | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-fe-e2e -t test:coverage:behaviour` |
| `FE_E2E_CASE`     | `rtk npm run test:e2e:fe -- -- --grep "<scenario title>"`                                                                                    |

`test:quick` never runs integration or E2E. Before relying on a row, confirm the target still exists with
`rtk npm exec -- nx show project bnest-app` (and `bnest-app-fe-e2e` for the last two rows); a renamed target is corrected
here, not worked around. `FE_E2E_CASE` runs the root script, which already opens its own HIPPO boundary and owns its
port lease, so it gets no second guard: the first `--` ends npm's options and the second reaches Playwright through Nx.
Substitute the affected scenario titles and run nothing else. It drives the desktop, tablet and mobile projects.

### Investigation commands (read-only)

These are the only production-touching commands in Phases 1 and 2 and in the ledger-row item of Phase 12. They derive locations from the documented
configuration keys, hold them in shell variables, and never print them. Output goes to ignored `local-tmp/` and is
summarized in `learnings.md` as dates, counts and yes/no only.

| ID             | Exact command or procedure                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LOCATE`       | `STORAGE_POINTER="${BNEST_STORAGE_CONFIG:-$HOME/.config/bnest/storage.json}"; DB="$(jq -r '.databaseDirectory + "/" + .databaseFilename' "$STORAGE_POINTER")"; DEST="$(jq -r '.destinationDirectory // empty' "${BNEST_BACKUP_CONFIG:-$HOME/.config/bnest/backup.json}")"`. An empty `DEST` means the default `data/backup` under the permanent runtime checkout (`BNEST_REPOSITORY_ROOT`). Do not `echo` either variable.                                                                                                                                                                                                                                                                                                                                                                              |
| `LEDGER_COPY`  | `mkdir -p local-tmp/backup-integrity/ledger && for n in a b; do cp -p "$DB" local-tmp/backup-integrity/ledger/ledger-$n.db && { [ ! -f "$DB-wal" ] \|\| cp -p "$DB-wal" local-tmp/backup-integrity/ledger/ledger-$n.db-wal; }; done`. A plain file read: the production database is never opened by SQLite, so no `-shm` or `-wal` file beside it is created or touched. A copy's `-wal` keeps the copy's own base name plus `-wal` (`ledger-a.db-wal` beside `ledger-a.db`), the name SQLite looks for, so a copy is never renamed apart from its `-wal`. The database and its `-wal` are copied non-atomically while the service may write, so accept the pair only when `LEDGER_CHECK` prints `stable`; otherwise recopy, at most twice, then record `Unavailable: ledger unstable`. Query copy `a`. |
| `LEDGER_CHECK` | `L=local-tmp/backup-integrity/ledger; Q="SELECT COUNT(*), SUM(state = 'verified'), MAX(finished_at) FROM bnest_schedule_runs"; A="$(sqlite3 -readonly "$L/ledger-a.db" "$Q")"; B="$(sqlite3 -readonly "$L/ledger-b.db" "$Q")"; if [ -n "$A" ] && [ "$A" = "$B" ]; then echo stable; else echo unstable; fi`. The equal-count acceptance check on the two scratch copies: it compares the total run count, the verified run count and the latest `finished_at` of copy `a` and copy `b`. `stable` accepts the pair; `unstable`, or an empty read, triggers the recopy in `LEDGER_COPY`. It prints only `stable` or `unstable`, never the values.                                                                                                                                                         |
| `LEDGER_QUERY` | `sqlite3 -readonly local-tmp/backup-integrity/ledger/ledger-a.db "SELECT r.scheduled_for, r.state, r.attempt, r.started_at, r.finished_at, r.artifact_basename, r.artifact_bytes FROM bnest_schedule_runs r JOIN bnest_schedules s USING (schedule_key) WHERE s.handler_key = 'prod_sqlite_backup' AND r.scheduled_for >= '2026-09-18' ORDER BY r.scheduled_for;"`. SQLite reads the `ledger-a.db-wal` beside it, so the file name must be `ledger-a.db`, the copy `LEDGER_COPY` writes. When no `-wal` was copied, open it instead as `sqlite3 -readonly "file:$PWD/local-tmp/backup-integrity/ledger/ledger-a.db?immutable=1" "<the same query>"`.                                                                                                                                                    |
| `DIR_LISTING`  | `stat -f '%N %z %m %B' "$DEST"/* "$DEST"/.bnest-backup-root.json` for names, sizes, modification and birth times, and `xattr -l` on the same entries for extended attributes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `MARKER_HASH`  | `shasum -a 256 "$DEST/.bnest-backup-root.json"`; record only whether the pre and post values are equal.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `SERVICE_LOGS` | The service and release logs are under `<deploy-root>/logs/` and `<deploy-root>/metrics/`, where [Releasing Bnest](../../../docs/how-to-guides/releasing-bnest.md) derives `<deploy-root>` from the running deployment. If the slot's log is not retained there, record `No log retained`. Read with `grep` and `sed -n` only.                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

## Execution Checkout

Execution happens in a **new** worktree, `worktrees/backup-integrity-exec`, created from current `origin/main` on a
fresh branch after the planning branch `backup-integrity-plan` has been integrated; the planning worktree
(`worktrees/backup-integrity`) is not reused and is deleted after its merge. Pass the
[integration path](../../../repo-governance/conventions/integration-path.md) sync gate before any mutation. Use
`/usr/bin/git` where the worktree guard of `rtk` blocks git. Never `cd` the session outside its worktree. Scratch lives
in ignored `local-tmp/`; it never holds a copy of this checklist.

## Delivery Units

| Unit | Owner | Testable outcome                                                                                                                                    | Rollback                                                                  |
| ---- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| U1   | AI    | Evidence and the AI-recorded cause verdict V1 (Phases 1 to 3); no repository code changes                                                           | Nothing to roll back: read-only                                           |
| U2   | AI    | Specifications and the reconciliation detector (Phases 4, 5)                                                                                        | Revert the unit's commits                                                 |
| U3   | AI    | The owner-confirmed verdict, the idea brief, and the cause-specific regression test and fix if the verdict selects it (Phase 6)                     | Revert the unit's commits; revert the idea-brief commit if rejected       |
| U4   | AI    | Restore-drill task and guide (Phase 7)                                                                                                              | Revert the unit's commits                                                 |
| U5   | AI    | The Schedules-page integrity label: copy reconciliation and design review, specification, implementation and rendered verification (Phases 8 to 10) | Revert the unit's commits                                                 |
| U6   | AI    | Documentation, rules propagation and the repository gates for U2 to U5 (Phase 11)                                                                   | Revert the unit's commits                                                 |
| U7   | AI    | The routed backend serves the release revision (Phase 12)                                                                                           | Route Caddy back to the previous healthy backend                          |
| U8   | AI    | The live detector re-run read-only and the sanitized records of the drill and the label look (the `[AI]` items of Phase 13)                         | Nothing to roll back: read-only                                           |
| U9   | Owner | One real production artifact restored and the label viewed on the live origin (the `[HUMAN]` items of Phase 13)                                     | Nothing to roll back: restore is into a root the task creates and removes |

## Pause Safety

At a pause, record in this file: the last ticked item, the branch and head commit, the verdict if Phase 3 passed, the
state of any started candidate, proxy or isolated inspection origin (port and purpose), and the pre-state snapshot's `local-tmp/` location. A
resuming executor re-verifies the baseline before the next item and never trusts a cached health result.

## Dated Preconditions

The live detector can report the two lost nights only inside a calendar window, so this plan states dates, not how long
any phase takes. Times are UTC, and the nightly backup slot is 19:00 UTC. The dates and the dispositions are part of
agent proposal D11, pending owner confirmation
([`tech-docs.md`](tech-docs.md#decisions-recorded-at-plan-quality-gate-pass-4-2026-10-04)). A missed date never skips a
phase and never brings a production read forward: it selects the recorded disposition, and the plan continues. The
disposition names are exact strings, so a later reader finds them by search.

| Date (UTC)        | Precondition                                                                                                                                                                                                                                                                                                 | Disposition recorded if it is missed                                                                                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-10-06T19:00Z | Latest authorization: execution is authorized, and the Phase 1 gate verdict, the OD-1 line and the R1 to R4 lines are current, so that Phase 2 can start once this slot's ledger row is terminal (the timing item of Phase 1). This slot is the last one before the Phase 2 completion date in the next row. | `Late authorization: <date>`, recorded in the timing item of Phase 1. Authorization is not refused; the next two rows decide what is still reachable.                                                              |
| 2026-10-07T12:00Z | Latest Phase 2 completion: the Phase 2 blocking checkpoint has passed. This is also the Phase 5 decision point.                                                                                                                                                                                              | Phase 2 finished but the early live reconcile has not run: `Detector not ready: Phase 2 table stands`. Phase 2 not finished: `Detector not ready: Phase 2 only`. See [Phase 5](#phase-5--reconciliation-detector). |
| 2026-10-07T19:00Z | Phase 2 has started, so the Phase 1 pre-state is captured, before this slot starts. Once this slot finishes retention, the first lost night leaves the seven latest WIB dates.                                                                                                                               | `Phase 2 not run by the slot`, with AC-BI-14 `Not applicable: aged out` and each uncaptured pruned observation `Unavailable: pruned before capture`. See [Phase 5](#phase-5--reconciliation-detector).             |

## Phase 1 — Authorization, Preflight and Baseline

- [x] `[AI]` Re-run the plan quality gate on the folder as the fifth propagation left it (the 2026-10-03 expansion for
      the owner decisions OD-1 to OD-4, the UI design assets, the repairs of F1 to F7 of gate pass 4, which returned
      `BLOCKED`, and the repairs of M1, M2 and L1 to L5 of gate pass 5, which returned `PASS_WITH_FINDINGS`, both on
      2026-10-04) with mode normal and record its terminal verdict line here. Execution does not start before a
      non-blocking verdict. **Proof:** the `plan-quality-gate:` verdict line.
      **Evidence 2026-10-04:** `plan-quality-gate: PASS_WITH_FINDINGS` (gate pass 6, on the folder as the fifth
      propagation left it). Findings recorded for resolution when Phase 4 writes the Gherkin; neither is edited now:
      **Medium**, AC-BI-17 "prints each date as present" contradicts the all-present summary wording `Backup files: all N
retained backups are present` in the PRD AC-BI-17 and the Phase 5 RED; **Low**, there is no PRD reconciliation note.
      Non-blocking, so execution may start.
- [x] `[HUMAN] [AC-BI-01]` The owner approves, as a dated line here naming what was put to them, the production reads
      Phase 2 and Phase 5 perform and nothing else: a plain file read of the production SQLite database and its `-wal`
      sidecar into scratch copies that are then queried `SELECT`-only (`LEDGER_COPY`, `LEDGER_CHECK`, `LEDGER_QUERY`), so
      SQLite never opens the production file; directory listings and file metadata (names, sizes, times, extended
      attributes) of the backup directory; the ownership marker's hash (equality only recorded); reading service and slot
      logs; and one read-only run of `mix bnest.backup.reconcile` against production in Phase 5 and one in Phase 13, which
      reads the ledger through its own scratch copy and never opens the production database (so no `-shm` or `-wal` file
      is created or touched). Reason for `[HUMAN]`: external authority. **Proof:** the dated approval line, or `Declined`
      with the reads excluded. **Recorded approval (OD-1, 2026-10-03): Approved.** Put to the owner and approved:
      read-only production reads in Phase 2 (a scratch copy of the production database and its `-wal` sidecar that is then
      queried; the backup directory listing and file metadata; the ownership marker hash; the service logs) and the two
      read-only `mix bnest.backup.reconcile` runs against the scratch copy. No write to `data/backup` or to
      `~/.config/bnest/*`. The executor confirms this line is current before Phase 2 and ticks the item then. **Scope
      check, confirmed by the owner:** the approval's enumeration does not name the following reads, which the plan's items
      perform (see [Confirmed by the Owner](tech-docs.md#confirmed-by-the-owner)). **R1** locating the database and the
      destination from the two documented configuration files (`LOCATE`) and listing `~/.config/bnest` for the AC-BI-01
      baseline; **R2** reading the marker's and the surviving receipts' destination identity to compare equality (H4);
      **R3** the host-wide search for the two lost basenames (Trash, the Dropbox cache, any prior destination); **R4** the
      Phase 12 scratch-copy ledger read that proves one row per slot. **Recorded confirmations:**
      `Confirmed 2026-10-03: R1`, `Confirmed 2026-10-03: R2`, `Confirmed 2026-10-03: R3` and
      `Confirmed 2026-10-03: R4`, the owner's reply "Setujui keempatnya" ("Approve all four"), asked and answered in the
      2026-10-03 session and recorded here on 2026-10-04. The executor confirms these lines are
      current before the first read of each; a read the owner has since withdrawn is recorded
      `Unavailable: not approved` for the affected observation and is not performed.
      **Evidence 2026-10-04:** the approval line above (OD-1, 2026-10-03: Approved) was confirmed current by the owner's
      authority relayed to the executor on 2026-10-04 (execution authorized; OD-1 approved; R1 to R4 approved). Reads R1 to
      R4 are current: `Confirmed 2026-10-03: R1`, `R2`, `R3` and `R4` stand; none withdrawn, none recorded `Unavailable: not
approved`. No write to the backup directory or `~/.config/bnest/*` was made.
- [x] `[AI] [AC-BI-02]` Record OD-2: the owner decided on 2026-10-03 that Dropbox web access is not available, so the
      deleted-files list, the event history and the list of devices linked to the backup folder cannot be read. No item in
      this plan needs the owner's Dropbox view. **Proof:** the dated line `Unavailable (OD-2, 2026-10-03)` in
      `learnings.md`, with the consequence stated: H2 can end only `unproven` unless a local signal confirms it.
      **Evidence 2026-10-04:** `Unavailable (OD-2, 2026-10-03)` recorded in `learnings.md` entry V0.2, with the consequence
      stated: H2 can end only `unproven` unless a local signal confirms it.
- [x] `[AI]` Authorization recorded: move this folder unchanged from `plans/backlog/` to `plans/in-progress/`, update its
      status, and update both stage indexes in the same change. **Proof:** the folder exists under one root only and
      both READMEs list it correctly.
      **Evidence 2026-10-04:** `git mv` from `plans/backlog/backup-integrity` to `plans/in-progress/backup-integrity`; the
      folder exists under one root only; `plans/backlog/README.md` no longer lists it, `plans/in-progress/README.md` lists it
      in its Active Plan and Directory Map sections, this file's status now reads in progress, and the idea-brief link that
      pointed at the backlog path is updated.
- [x] `[AI]` Create the new execution worktree and branch from current `origin/main`, pass the integration sync gate,
      and confirm a clean tree. Command: `rtk git status` (fall back to `/usr/bin/git status` in a worktree). **Proof:**
      worktree, branch name, head commit and clean status recorded.
      **Evidence 2026-10-04:** worktree `worktrees/backup-integrity-exec`, branch `backup-integrity-exec`, head
      `351f10434` (equal to `origin/main` after `git fetch origin`; `git merge-base --is-ancestor origin/main HEAD`
      succeeded), dependencies installed before execution; `git status` clean at start (run with `/usr/bin/git` because of
      the `rtk` worktree guard).
- [x] `[AI] [AC-BI-12]` Identify the active Bnest backend and proxy and record safe local and routed health. Phase 2 is
      read-only, so no continuity budget applies yet; this item records the baseline Phase 12 compares against. Follow
      [live-service continuity](../../../repo-governance/development/live-service-continuity.md). **Proof:** active
      port, proxy upstream, and an HTTP status for the loopback and routed origins; no identifiers.
      **Evidence 2026-10-04:** active backend: the green slot on loopback port 4001 (port 4000 idle); proxy: Caddy on
      loopback port 4100 routing to it. HTTP status of `/health/ready`: loopback 4001 200, loopback 4100 200, routed origin
      200 on five consecutive samples (0.02 to 0.04 s). The body reports `ready`, scheduler and SQLite ready, and release
      revision `e92f1ec2c82e9ee42fa535cd5ac2a1c1a2592b3e`. No identifiers recorded. See `learnings.md` V0.1.
- [x] `[AI] [AC-BI-01]` Prerequisite timing: the pre-state, Phase 2 and the post-state run between scheduled slots. The
      backup slot is daily at 19:00 UTC, so start only after the latest slot's ledger row is terminal (`verified`,
      `failed` or `skipped`), so the next slot is about a day away, and record the start and end times. **Proof:** both
      times, and that no 19:00 UTC slot lies between them. If one unavoidably does, the comparison rule below applies
      and the exclusion is recorded. Also record the authorization date against the
      [Dated Preconditions](#dated-preconditions): `Late authorization: <date>` when it is after 2026-10-06T19:00Z.
      **Evidence 2026-10-04:** latest slot 2026-10-03T19:00Z is `verified` (finished 19:00:39Z). Start 07:28Z (pre-state),
      end 07:37Z (post-state); no 19:00Z slot lies between them (the next is 2026-10-04T19:00Z). Authorization date
      2026-10-04 is before 2026-10-06T19:00Z, so no `Late authorization` is recorded.
- [x] `[AI] [AC-BI-01]` Capture the pre-state with `LOCATE`, `DIR_LISTING` and `MARKER_HASH`, plus a listing of the
      private configuration directory (`~/.config/bnest`) and the ledger row count of the backup schedule from
      `LEDGER_COPY`, `LEDGER_CHECK` and `LEDGER_QUERY`, all into `local-tmp/backup-integrity/pre-state.txt`. `LOCATE` and the
      configuration listing are read R1 of the scope check above. Read-only commands only.
      **Proof:** the file exists; `learnings.md` records counts and a yes/no for each item, never names.
      **Evidence 2026-10-04T07:28Z:** `pre-state.txt` exists in the ignored scratch area. `learnings.md` V0.3 records counts
      and yes/no: 27 directory entries, extended attributes present on all, the marker hashed, 3 entries in the private
      configuration directory, 53 ledger runs of which 39 verified and 38 for the backup schedule, ledger copy pair
      `stable` on the first attempt. Read-only commands only; the production database was copied, not opened.
- [x] `[AI] [AC-BI-01]` **Blocking checkpoint — Phase 1.** Approvals recorded (or declined with the reads removed from
      Phase 2), the scope-check reads R1 to R4 (confirmed 2026-10-03) current or recorded `Unavailable: not approved` if
      withdrawn, baseline recorded, pre-state captured, timing prerequisite satisfied.
      **Checkpoint passed 2026-10-04:** approvals current, R1 to R4 current, baseline recorded, pre-state captured at
      07:28Z, timing prerequisite satisfied.

## Phase 2 — Read-Only Investigation

Every item here is read-only and runs at most once; an item that errors is retried at most twice, then recorded
`Unavailable` with the error class. A read marked R1 to R4 in the Phase 1 scope check runs under the owner's
confirmation recorded there (2026-10-03), once the executor has confirmed it current. Results go to `learnings.md` as sanitized entries (dates, counts, yes/no). The
discriminating predictions are in [`tech-docs.md`](tech-docs.md#hypotheses-and-discriminating-checks).
The surviving pairs for the earliest dates are pruned by later nightly runs, so capture their metadata in the
Phase 1 pre-state before anything else in Phase 2 depends on them.

**Comparison rule.** AC-BI-01's rule in [`prd.md`](prd.md#ac-bi-01--the-investigation-changes-nothing-in-production)
is the single statement; this phase applies it and does not restate it. The owner amended it on 2026-10-04 to exclude
the storage lock directory's modification time (a service-owned heartbeat); the Phase 2 items below were executed
before the amendment and recorded that difference as a deviation, which the amendment now covers.

- [x] `[AI] [AC-BI-02]` **H5, H4 data.** Run `LEDGER_COPY`, `LEDGER_CHECK` and `LEDGER_QUERY` (the query covers every backup-schedule
      row since 2026-09-18: slot, state, attempt, `finished_at`, the artifact basename's timestamp, bytes), then
      compare against `DIR_LISTING` and record whether each surviving receipt's destination identity equals the present
      marker's (read R2; equality only; the ledger records no destination, so a lost run is not attributed this way). Query output stays in `local-tmp/`. **Proof:** a per-date table of present/absent on disk next
      to the ledger state, with the lost dates marked.
      **Evidence 2026-10-04:** per-date table in `learnings.md` V0.4. Slots 2026-09-25 to 09-29, 10-02 and 10-03 are
      present with bytes and digests equal to the ledger; 2026-09-30 and 2026-10-01 are absent (artifact and receipt);
      2026-09-18 to 09-24 are absent as retention's oldest dates. All 7 surviving receipts name the present marker's
      destination (equality only).
- [x] `[AI] [AC-BI-02]` **H5.** Compare each lost row to its intact neighbours on slot versus `finished_at`, attempt
      count, name timestamp versus slot, and byte-size progression (both lost rows are exactly 684032 bytes).
      **Proof:** one line per compared field stating "indistinguishable" or the difference.
      **Evidence 2026-10-04:** `learnings.md` V0.5: slot versus `finished_at` indistinguishable; attempt count
      indistinguishable; name timestamp versus slot indistinguishable; byte size indistinguishable and not unique (684032
      bytes is also the size of three intact runs). H5 eliminated by the plan's rule.
- [x] `[AI] [AC-BI-02]` **H4.** Search the host (read R3) for the two lost basenames, including the user Trash, the Dropbox
      cache folder and any prior destination the logs name, with read-only commands (`find`, `mdfind`), and read the
      service logs for a saved destination override around the two slots. H4 is discriminated by this search, the logs
      and the surviving receipts only. **Proof:** found/not found per location class, and override seen or not seen per
      slot.
      **Evidence 2026-10-04:** `learnings.md` V0.6: neither lost name found in the Trash, the Dropbox cache (also searched by
      content digest), the Dropbox folder, the whole home directory, temporary directories or mounted volumes; override seen:
      no (configuration file unchanged since 2026-08-30; no log line). H4 eliminated, with the limit that the logs carry no
      dates.
- [x] `[AI] [AC-BI-02]` **H3.** Read birth and modification times of the twelve fixtures and the surviving pairs
      (`DIR_LISTING`), search the repository for every writer of `bnest-prod-` names, and tabulate the commits that
      touched Backup, the Scheduler and `config/test.exs` per WIB date from 2026-09-18 with `/usr/bin/git log`.
      **Proof:** a per-WIB-date table of fixture birth times, test-guard landing times (`c6f654ec8`, `ca0e437e9`) and
      the lost nights.
      **Evidence 2026-10-04:** per-WIB-date table in `learnings.md` V0.7: twelve fixtures all born WIB 2026-09-18, none on the
      lost nights; commits per WIB date 09-19: 5, 09-22: 1, 10-01: 4, 10-02: 12; guards `c6f654ec8` and `ca0e437e9` landed
      WIB 2026-10-02 07:18 and 09:12 (author dates). H3 not eliminated: temporal overlap, no direct evidence.
- [x] `[AI] [AC-BI-02]` **H1 and H3a.** In `local-tmp/`, replay the real `Retention.retained_run_ids/1` over
      receipt histories reconstructed from the ledger with synthetic receipts only. Run (a) production runs alone, (b)
      production runs plus a synthetic newer same-date owned receipt on each lost WIB date, (c) production runs plus
      twelve synthetic fixture receipts dated 2026-09-18. **Proof:** for each reconstruction, whether the lost nights
      are removed. Reconstruction (a) is expected to keep them; a reconstruction that loses exactly the two nights and
      keeps the rest is the finding.
      **Evidence 2026-10-04:** `learnings.md` V0.8. (a) production runs alone: lost nights kept; (b) plus a synthetic newer
      same-date receipt on each lost date: lost nights removed, but 09-25 and 09-26 also pruned, so the disk is not
      reproduced; (c) plus twelve fixture receipts dated 2026-09-18: lost nights kept. Extra labelled probe: the disk is
      reproduced only by a removal between the retention of the 2026-10-01T19:00Z slot and that of 2026-10-02T19:00Z.
- [x] `[AI] [AC-BI-02]` Read the service and slot logs (`SERVICE_LOGS`) for the two lost slots and the following runs:
      backup start and stop telemetry, retain events, errors, destination changes, restarts. **Proof:** per slot, the
      sequence of events (names of event kinds and times only) or `No log retained`.
      **Evidence 2026-10-04:** `learnings.md` V0.9: both slots `No log retained`: the logs hold a time of day without a date and
      no line naming a backup, retention, destination or verified run.
- [x] `[AI] [AC-BI-02]` **H2 local.** Read extended attributes (`xattr -l`) and Dropbox metadata of the folder and
      surviving files, and look for conflicted-copy or placeholder files. These are the only H2 signals available, because
      the Dropbox web history is not (OD-2). **Proof:** found/not found per signal.
      **Evidence 2026-10-04:** `learnings.md` V0.10: extended attributes uniform on all 28 entries (found: both Dropbox and
      provenance attributes, no difference); conflicted copies in the backup directory or repository folder: not found;
      placeholder or partial files: not found; local cache copy of a lost artifact: not found.
- [x] `[AI] [AC-BI-02]` **H2 disposition (OD-2).** The Dropbox deleted-files list, event history and linked-device list
      are unavailable, so H2 cannot be eliminated. Record H2 as `confirmed` only when the H2 local item above found a
      signal; otherwise record it `unproven` together with the observation that would settle it: the folder's Dropbox
      event history around the two slots. **Proof:** the H2 line in `learnings.md`: `confirmed` with the local signal, or
      `unproven` with the settling observation.
      **Evidence 2026-10-04:** `learnings.md` V0.11: H2 `unproven`; the settling observation is the Dropbox event history of the
      backup folder between 2026-10-02 02:00 WIB and 2026-10-03 02:00 WIB, unavailable under OD-2.
- [x] `[AI] [AC-BI-01]` Capture the post-state with the commands used for the pre-state and compare under the comparison
      rule above. Command: `diff` of the two files, then the rule's justification per difference. **Proof:** the
      listing, marker hash, directory listing and row count are equal under the rule; an unjustified difference stops
      the plan and is reported to the owner.
      **Evidence 2026-10-04T07:37Z:** `diff` of `pre-state.txt` and `post-state.txt`: directory listing, extended attributes,
      marker hash, configuration listing and file hashes, and ledger row counts are equal. One difference: the modification
      time of the storage lock directory in the private configuration directory, a heartbeat the running service rewrites
      about every 30 seconds (seen advancing between two `stat` reads 20 seconds apart). It is not a slot-related
      difference, so the rule's exclusions do not cover it; recorded as a deviation (`learnings.md` V0.12) and judged
      service-owned, not a write by this execution. No pre-existing backup-directory file has a later modification time.
- [x] `[AI] [AC-BI-01, AC-BI-02]` **Blocking checkpoint — Phase 2.** Every hypothesis has either an eliminating or a
      confirming observation recorded, or a stated `Unavailable`; H2 is `unproven` unless a local signal confirmed it;
      AC-BI-01's comparison is clean under the rule.
      **Checkpoint passed 2026-10-04 with one recorded deviation:** H1 eliminated for production writers alone, H2
      `unproven`, H3 not eliminated, H4 eliminated, H5 eliminated (table in `learnings.md`); AC-BI-01's comparison is clean
      under the rule except the service-owned lock-directory mtime, reported to the owner. Phase 3 is not started.

## Phase 3 — Cause Verdict and Branch Selection

This phase records the AI's verdict V1. The owner's confirmation of V1 is not a precondition of Phases 4 and 5
(decision D11): it is the first item of Phase 6 and is also required before the Phase 12 release. The dispositions and the
label's state set below are provisional until then.

- [x] `[AI] [AC-BI-02]` Write learnings entry V1: the verdict (`C-TEST`, `C-RET`, `C-DROPBOX`, `C-DEST`, `C-LEDGER`,
      `C-UNPROVEN` or a union), the observation that confirmed or eliminated each of H1 to H5, and, for `C-UNPROVEN`,
      the observation that would settle it. H2 is `unproven` unless an H2 local signal confirmed it (OD-2); a verdict that
      eliminates H1, H3, H4 and H5 and leaves only H2 open is `C-UNPROVEN`, which is expected in that case. If H1, H3a or
      H5 is the cause, also record the minimal reproduction Phase 6 will test. **Proof:** the entry exists and satisfies
      AC-BI-02.
      **Evidence 2026-10-04:** `learnings.md` entry V1 (AI-recorded, pending owner confirmation): verdict `C-UNPROVEN` with
      `C-DROPBOX` (H2 unproven) and `C-TEST` (H3 not eliminated) open and none confirmed; H1 eliminated for production
      writers alone, H3a not reproduced, H4 and H5 eliminated, each with its observation; the Phase 2 loss window (WIB
      2026-10-02 02:00 to 2026-10-03 02:00, a single-instant removal assumption, 7 h 12 min of it before the test guards)
      is stated as keeping H3 open without making it likely; the observations that would settle H2 and H3 are named; no
      minimal reproduction is recorded because no repository-side cause is confirmed.
- [x] `[AI] [AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-19]` Mark each conditional item in Phases 4, 6, 9, 10 and 11 as
      applicable or `Not applicable` **provisionally** from V1, per the branch table in
      [`tech-docs.md`](tech-docs.md#branch-selection), with the reason. **Proof:** every conditional item carries a
      provisional disposition.
      **Evidence 2026-10-04:** 21 items carry a `Provisional disposition (V1, ...)` line: AC-BI-08 and AC-BI-09
      applicable (H3 open, defence in depth; the GREEN items act only if the unmodified characterization fails);
      AC-BI-10 reproduction and fix items `Not applicable` (no repository-side cause), with the C-DROPBOX or C-UNPROVEN
      routing item applicable; AC-BI-19 items in Phases 4, 6, 9 and 10 `Not applicable` (C-DEST not selected, H4
      eliminated); the Phase 11 rules propagation provisionally `Not applicable`.
- [x] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Fix the label's state set provisionally from V1: all present, needs
      attention, could not be checked and nothing to check yet, plus the destination-mismatch state only on C-DEST. Record
      it in the [UI Design section](tech-docs.md#ui-design) of `tech-docs.md`. The label itself is decided (OD-3) and is not
      conditional on the verdict. **Proof:** the section lists the state set and names the verdict that fixed it.
      **Evidence 2026-10-04:** the [UI Design section](tech-docs.md#states-and-real-copy) now lists the provisional state
      set (checking as page-only, all present, needs attention, could not be checked, nothing to check yet) and names V1
      `C-UNPROVEN` as the verdict that fixed it; the destination-mismatch state is excluded unless the confirmed verdict
      is `C-DEST`.
- [x] `[AI]` Commit the learnings entries when authorized (see Execution Status and Authority). **Proof:** the
      authorization line and the commit subject, or `No commit authorized`.
      **Evidence 2026-10-04:** authorized by the owner's execution authority relayed to the executor (thematic commit per
      unit). Subject: `docs(plans): record the backup integrity cause verdict V1 and the AC-BI-01 amendment`.
- [x] `[AI] [AC-BI-02]` **Blocking checkpoint — Phase 3.** V1 recorded, provisional dispositions made and the label's
      state set fixed provisionally. The owner's confirmation and the idea brief are Phase 6 items.
      **Checkpoint passed 2026-10-04:** V1 recorded as AI-recorded and pending owner confirmation, provisional
      dispositions made, label state set fixed provisionally. The owner's confirmation and the idea brief stay in Phase 6.

## Phase 4 — Specifications

This phase specifies the backend scenarios. It starts on the Phase 3 verdict V1 as the AI recorded it (decision D11):
conditional Rules follow V1's provisional dispositions, and if the owner's confirmation in Phase 6 changes a verdict,
the affected Rules are added or removed as their own Gherkin, binding and red cycle. The Schedules-page scenarios
(AC-BI-21 to AC-BI-23) wait for the design review and are specified in Phase 9, after Phase 8.

- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19]` Add the `Rule`s to
      `specs/apps/bnest/app-be/behaviours/scheduled_backups.feature` transcribing the backend-observable criteria:
      AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-11 (against an isolated destination standing for the owner's
      artifact), AC-BI-15, AC-BI-16, AC-BI-17 and AC-BI-18, plus the conditional AC-BI-08, AC-BI-09, AC-BI-10 (rewritten
      with the reproduction V1 recorded) and AC-BI-19 (C-DEST), each `@e2e-exempt` with an `Exemption(e2e)` comment naming its
      `bnest-app:test:integration` alternative. Omit a conditional criterion its Phase 3 disposition marked
      `Not applicable`. Add one further Rule, tagged the same way, that pins the state-to-wording mapping of the task's
      printed report, which the log line and the label render from the same function. It transcribes AC-BI-07 and
      AC-BI-17 (and AC-BI-19 on C-DEST), with the draft copy of
      [States and Real Copy](tech-docs.md#states-and-real-copy) as its contract, and has one scenario for each state
      the report can show: all present, needs attention in the plural and, for one problem, the singular, could not be
      checked for an unreadable ledger, nothing to check yet, and on C-DEST the mismatch line with its footer. Each
      scenario seeds an isolated ledger and destination, runs the task and names the report's first line and its
      problem lines. The page-only `checking` state and the split into label, summary, problem lines and footer are
      pinned by the Phase 5 unit cases and, on the page, by AC-BI-21 and AC-BI-22 in Phase 9. **Proof:** each scenario
      names an outcome visible in a report, an exit status or a directory listing, and the wording Rule names the
      report line for each state; no placeholder, no-op or outcome table.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** AC-BI-08 and AC-BI-09 applicable (H3 stays open, so they apply as defence in depth); AC-BI-10 `Not applicable` (no repository-side cause and no verdict-named reproduction); AC-BI-19 `Not applicable` (C-DEST not selected, H4 eliminated), so the wording Rule omits the mismatch scenario and footer.
      **Evidence 2026-10-04:** 8 Rules and 19 scenarios appended, each `@e2e-exempt` with an `Exemption(e2e)` comment naming
      its `bnest-app:test:integration` alternative (comment and scenario names checked equal): reconciliation missing,
      changed, older-than-retained, newest-of-date and never-writes (AC-BI-03, 04, 05, 15, 06); the wording Rule with one
      scenario each for all present, several need attention, one needs attention, could not run and nothing to check
      (AC-BI-07, 17); no private value (AC-BI-07); a raising reconciliation never fails the backup (AC-BI-16); the task exit
      status (AC-BI-17: all present exits 0 with the summary line and no per-date line, missing, changed, unreadable
      ledger, empty ledger); AC-BI-08 and AC-BI-09 as applicable. The singular forms (`1 of 7 retained backups needs
  attention`) are agent proposals for Phase 8 to review. **Deviation (recorded):** the AC-BI-11 and AC-BI-18 Rules are
      not written now but as the first cycle of Phase 7 (Gherkin, bindings, red, code), because their task is built
      only in Phase 7 and the Phase 5 checkpoint requires green `BE_UNIT`, `INTEGRATION` and `BEHAVIOUR`; the Phase 5
      item that lists AC-BI-18 among the scenarios made green is therefore satisfied for AC-BI-18 in Phase 7. AC-BI-10
      and AC-BI-19 omitted (`Not applicable`). No placeholder, no-op or outcome table.
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18]` Update `specs/apps/bnest/app-be/architecture.md` as
      [`tech-docs.md`](tech-docs.md#specification-changes) states: Component View for reconciliation, the Scheduler
      read and the Mix tasks; Constraints for read-only reconciliation that never opens the production database. Record the Container View
      as deliberately unchanged. **Proof:** those locations changed and no other.
      **Evidence 2026-10-04:** changed locations only: Component View (the Backup node text and its accessible description, and
      a paragraph on reconciliation, the Scheduler `verified_runs/1` read and the two Mix tasks) and Constraints (one
      bullet: reconciliation is read-only, never opens the production database, starts no Scheduler). Container View
      deliberately unchanged.
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19]` Bind the new scenarios in
      `apps/bnest-app/test/behaviour/steps/scheduled_backup_steps.exs` against isolated destinations, then capture the
      behavioural **RED**. Command: `BEHAVIOUR`. **Proof:** it fails because reconciliation and the Mix tasks do not exist, not because of compilation or configuration.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** about 50 steps bound; both drivers
      (unit in-memory, integration real filesystem and SQLite ledger with synthetic roots) and new test-support modules
      call the final Phase 5 API (`Scheduler.verified_runs/1`, `Backup.reconcile/2`, `Reconciliation.report/1` and
      `render/1`, `Mix.Tasks.Bnest.Backup.Reconcile.execute/1`); no production code written. `BEHAVIOUR` exit 0
      (13 features, 182 scenarios, 1087 steps, 492 bindings per layer; no unbound, ambiguous or unused step). **RED:** the
      canonical `BE_UNIT` and `INTEGRATION` fail at compile under `--warnings-as-errors` on 7 undefined-production-function
      warnings (the intended red; recorded honestly as a compile-time failure). The behavioural red, run without
      `--warnings-as-errors`: unit 639 tests, 17 failures (16 on `Scheduler.verified_runs/1` undefined, 1 missing log
      line for the raising-reconciliation scenario); integration 17 of 31 feature tests (10 on the undefined Mix task, 6
      on `verified_runs/1`, 1 missing log line). AC-BI-08 and AC-BI-09 pass on unmodified code, as characterization pins
      whose mutation runs are the Phase 6 items; every pre-existing test still passes. **Deviation:** `BEHAVIOUR` is a
      binding-coverage verifier, so it passes; the red is in the scenario runs.
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19]` Run the repository specification-map gate. Command: `REPO`. **Proof:** it
      passes and the record names every specification file changed.
      **Evidence 2026-10-04:** `REPO` passed (directory-map, quality-gates, harness-adapters, internal-links, mermaid).
      Specification files changed: `specs/apps/bnest/app-be/behaviours/scheduled_backups.feature` and
      `specs/apps/bnest/app-be/architecture.md`; the behaviours README map is unchanged (no file added).
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19]` **Blocking checkpoint — Phase 4.** Specifications describe the intended
      behaviour, the behavioural red is on record, `REPO` is green, and no production code has changed.
      **Checkpoint passed 2026-10-04 with the recorded deviations:** specifications describe the intended behaviour, the
      behavioural red is on record, `REPO` is green, and no production code (`lib/`) has changed.

## Phase 5 — Reconciliation Detector

**Schedule pressure.** No item in Phases 1 to 5 depends on a UI item or on the owner's confirmation of V1 (decision
D11). The early live reconcile below must finish before the nightly slot of 2026-10-07T19:00Z completes retention; the
label is Phase 8 onward and never delays it.

**Fallback timing for that window (agent proposal D11, pending owner confirmation).** The decision point is
2026-10-07T12:00Z, seven hours before the slot, and the [Dated Preconditions](#dated-preconditions) give the dates it
rests on. At that point the executor stops waiting for the detector and records one of these, by what has happened:

1. **Phase 2 finished, early live reconcile not run** (the reconcile task is not green, the gate has not passed, or the
   Phase 1 confirmations are not current). The gap is recorded from the Phase 2 evidence instead: its per-date
   present/absent table already names the two nights against the ledger and needs no detector. That table is then the
   AC-BI-14 proof, recorded as `Detector not ready: Phase 2 table stands` with the time of the decision.
2. **Phase 2 not finished.** Phases 3 to 5 follow Phase 2, so the detector is out of reach for the slot. Record
   `Detector not ready: Phase 2 only` with the time of the decision. Phase 2 continues, because it only reads: the
   ledger rows of the two nights and the absence of their artifacts do not expire, so its present/absent table, when it
   completes, is the only record of the gap. AC-BI-01's comparison rule covers a slot that arrives while Phase 2 runs.
3. **Phase 2 not started when the slot of 2026-10-07T19:00Z starts.** Record `Phase 2 not run by the slot` with the
   time, in place of the records above, and AC-BI-14 as `Not applicable: aged out`. A surviving pair removed by this
   slot's retention before any pre-state captured its file times can no longer give them, so each H3 observation that
   needed those times is recorded `Unavailable: pruned before capture`. The ledger, git, host-search, log and
   local-signal observations do not expire and are gathered as the Phase 2 items say.

In every case the ledger rows persist after the window, so Phase 2 may still run later; only the proof that the live
detector reported the gap is lost. Once the slot of 2026-10-07T19:00Z has finished retention, AC-BI-14 is recorded
`Not applicable: aged out` for the first lost night as the early-read item below states, and one slot later for the
second.

- [x] `[AI] [AC-BI-03, AC-BI-05, AC-BI-15]` **RED** — create
      `apps/bnest-app/test/unit/bnest_app/backup/reconciliation_test.exs`: a missing artifact is `:missing`; a run
      older than the seven latest WIB dates is `:not_expected`; of two verified runs on one date only the newest is
      expected; a run whose slot (16:59Z) and `finished_at` (17:01Z) fall on different WIB dates is grouped by
      `finished_at`, the date `Retention` gives its receipt's `createdAt`. **Proof:** `BE_UNIT` fails naming the undefined `Reconciliation`. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `reconciliation_test.exs` written first; with a temporary
      wrong-value stub (an undefined function is not a red) 12 assertions failed behaviourally (missing, not-expected, newest
      of a date, `finished_at` grouping). Extra cases: changed by digest or size, the window counts dates holding a run,
      a setup run (null slot) is dated by `finished_at`, the expected set equals `Retention.retained_run_ids`.
- [x] `[AI] [AC-BI-03, AC-BI-05, AC-BI-15]` **GREEN** — add
      `apps/bnest-app/lib/bnest_app/backup/domain/reconciliation.ex` and expose the WIB-date grouping from
      `retention.ex` so both use one definition. **Proof:** `BE_UNIT` passes. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `Reconciliation.expected/1` and `classify/2` added; `Retention`
      exposes `wib_date/1` and `retained_groups/2`. Deviation: `classify/2`, not the `/3` the design names, because no
      third input exists. Final `BE_UNIT` below: 690 tests, 0 failures.
- [x] `[AI] [AC-BI-05, AC-BI-15]` **REFACTOR** — delete any copy of the window rule, leaving `Retention` its only
      owner. **Proof:** `BE_UNIT` still passes and one grep for the seven-date constant finds one definition.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `retained_run_ids/1` itself goes through `retained_groups/2`; `grep retained_dates` over `lib` finds the constant once.
- [x] `[AI] [AC-BI-04, AC-BI-06]` **RED** — extend `apps/bnest-app/test/unit/bnest_app/backup/backup_test.exs`:
      `Backup.reconcile/2` over the in-memory artifact store reports a changed digest as `:changed`, reports intact
      runs `:present`, and leaves the store's contents byte-identical. **Proof:** `BE_UNIT` fails on the undefined
      `reconcile/2`. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** 6 behavioural failures against a wrong-value stub (changed digest, intact, store byte-identical, unknown file neither read nor listed, invalid directory refused with no store call, read failure propagates).
- [x] `[AI] [AC-BI-04, AC-BI-06]` **GREEN** — add `Backup.reconcile/2` using only `ArtifactStore.regular?/2`,
      `digest/2` and `size/2`. **Proof:** `BE_UNIT` passes. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `Backup.reconcile(directory, runs)` uses only `ArtifactStore.regular?/2`, `digest/2`, `size/2`; returns `{:ok, [%{date, slot, artifact_basename, state}]}`; store failures raise (so the AC-BI-16 guard has something to guard).
- [x] `[AI] [AC-BI-04, AC-BI-06]` **REFACTOR** — compute a digest only for expected runs whose file exists. **Proof:**
      `BE_UNIT` still passes; a test asserts no digest call for a missing file.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** a call-trace test asserts `regular?` is asked only of the 7 expected runs and `digest`/`size` only of the 6 that exist; a mutation check (passing all runs) failed it, then was restored.
- [x] `[AI] [AC-BI-03]` **RED** — extend the Scheduler contract suite for `Scheduler.verified_runs/1`: returns verified
      backup runs with artifact basename, digest, bytes, slot and `finished_at`, excludes failed, skipped and running
      runs, and changes nothing. Run it against the in-memory and the SQLite adapters. **Proof:** `BE_UNIT` and
      `INTEGRATION` fail on the undefined function. Commands: `BE_UNIT`, `INTEGRATION`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** new contract cases run against the in-memory and SQLite adapters failed against a stub: only verified backup runs with run id, slot, `finished_at`, basename, digest and bytes; failed, skipped, running and other-handler runs excluded; nothing changed. Decision: a setup claim has a null `scheduled_for`, so it is included with `slot: nil` and dated by `finished_at`.
- [x] `[AI] [AC-BI-03]` **GREEN** — add `verified_runs/1` to `scheduler.ex`, the `ScheduleStore` port, both adapters.
      **Proof:** both commands pass.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `Scheduler.verified_runs/1` on the facade, the `ScheduleStore` port, `SqliteScheduleStore` and the in-memory store; `BE_UNIT` and `INTEGRATION` pass (final results below).
- [x] `[AI] [AC-BI-03]` **REFACTOR** — share the column list with the existing completion query. **Proof:** both
      commands still pass.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** the SQLite query selects the shared `@run_columns` through one `qualified/2` helper and `Policy.verified_run/1`; both commands still pass.
- [x] `[AI] [AC-BI-07, AC-BI-17]` **RED** — extend
      `apps/bnest-app/test/unit/bnest_app/backup/reconciliation_test.exs` with the full state-to-wording mapping that the
      log, the telemetry metadata, the Mix task and the label all render (one function; see **One wording function** in
      [`tech-docs.md`](tech-docs.md#reconciliation-detector)): `checking` gives `Backup files: checking`; every one of N
      retained runs present gives `Backup files: all N retained backups are present`; k of N runs missing or changed
      gives `Backup files: k of N retained backups need attention` and one `date: file missing` or `date: file changed`
      line per problem; a raise, an unreadable or unstable ledger or the ceiling gives
      `Backup files: could not be checked. Run mix bnest.backup.reconcile on the host.`; and an empty ledger (no verified
      run, so zero expected runs) gives `Backup files: no verified backup to check yet` and never the all-present words
      (the vacuous-truth case). The cases pin the singular and plural forms for k = 1 and N = 1, return the label, summary,
      problem lines and footer as separate parts (the row label renders the term and the description apart), and assert
      that no output contains a path, digest, destination ID or run ID. **Conditional: C-DEST** — from a hand-built
      result, a `date: receipt names another destination` line and, as the footer,
      `Runs lost without a surviving receipt cannot be seen this way`. The Phase 4 wording Rule pins in Gherkin the
      states the task report can show; these unit cases cover every state, `checking` included. **Proof:**
      `BE_UNIT` fails naming the undefined wording function. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** 12 behavioural failures against a stub. Forms agent-proposed, pending Phase 8 review: N=1 `the retained backup is present`; k=1 `1 of N retained backups needs attention`; N=1,k=1 `the retained backup needs attention`; `checking` renders `Backup files: checking` (exit status 1). C-DEST case omitted (`Not applicable` under V1). A leak assertion over every state (no path, digest, destination id, run id) was strengthened after it passed vacuously.
- [x] `[AI] [AC-BI-07, AC-BI-17]` **GREEN** — add the wording function to
      `apps/bnest-app/lib/bnest_app/backup/domain/reconciliation.ex`, mapping a structured result to those parts for every
      state, with an empty set of expected runs yielding the nothing-to-check state and never the all-present state.
      **Proof:** `BE_UNIT` passes, including the empty-ledger case. Command: `BE_UNIT`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** `Reconciliation.report/1` (label, summary, problems, footer, exit status) and `render/1`; empty or all-not-expected results give the nothing-to-check state with exit status 1, never the all-present words; an error's reason is never rendered. `BE_UNIT` passes.
- [x] `[AI] [AC-BI-07, AC-BI-16]` **RED** — add integration cases in
      `apps/bnest-app/test/integration/bnest_app/backup/scheduled_backup_test.exs`: after a scheduled run in an
      isolated destination whose earlier artifact was removed, the task emits one `[:bnest_app, :backup, :integrity]`
      event and one log line naming the date and state and containing no path, digest, destination or run ID; a
      reconciliation that raises leaves the run `verified` with its artifact and receipt present and logs one path-free
      error line. **Proof:** `INTEGRATION` fails on the absent event and on the unguarded raise. Command:
      `INTEGRATION`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** 3 integration cases (removed earlier artifact, all present, raising reconciliation via an unreadable-artifact store wrapper) failed behaviourally: no integrity event, no error line; the unguarded raise escaped `execute/2`.
- [x] `[AI] [AC-BI-07, AC-BI-16]` **GREEN** — call `Backup.reconcile/2` from `ScheduledBackupTask` after retention,
      inside a `rescue`, emitting the telemetry event and the log line. **Proof:** `INTEGRATION` passes. Command:
      `INTEGRATION`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** the task composes `Scheduler.verified_runs/1` and `Backup.reconcile/2` after retention inside a rescue-and-catch, emits one `[:bnest_app, :backup, :integrity]` event and one log entry (info when exit status 0, error otherwise) through `Reconciliation.render`; a raise logs only the could-not-be-checked line. Deviation: one multi-line log entry per run rather than one line per problem run (the drivers count exactly one error entry).
- [x] `[AI] [AC-BI-07, AC-BI-17]` **RED** — add
      `apps/bnest-app/test/integration/mix/tasks/bnest_backup_reconcile_test.exs` for the Mix task over an isolated
      destination and ledger: with at least one expected run and every expected run present it exits `0`, prints the summary
      `Backup files: all N retained backups are present` and no per-date line (agent-proposed rewording of 2026-10-04,
      resolving the gate pass 6 finding; see the PRD reconciliation note); with a missing or changed run it exits non-zero and the report names the date and state; with a
      ledger holding no verified run it prints `Backup files: no verified backup to check yet`, prints no date as
      present, never says `present`, and exits non-zero (the empty case, decision D10); the printed report contains no
      path, digest, destination identifier or run ID; an unreadable ledger or destination exits non-zero with a
      path-free message; run against an isolated database nothing else has open, the source database and its
      `-wal` are byte-identical afterwards and no `-shm` file appears (the repository was opened on a scratch copy);
      two copies that disagree on the verified-run count exit non-zero with a path-free "ledger unstable" reason; and
      no Scheduler process is alive after the task returns. That last case runs the task in a `mix run --no-start`
      subprocess, as `apps/bnest-app/test/integration/bnest_app/scheduler/persistent_schedules_migration_test.exs`
      does, with `BNEST_STORAGE_CONFIG` naming an isolated source pointer, and fails when
      `Process.whereis(BnestApp.Scheduler)` or `Process.whereis(BnestApp.Scheduler.Tasks)` returns a pid (AC-BI-17); it
      cannot run in the test VM, where the application already started the Scheduler. These cases need a real
      filesystem, hence integration. **Proof:** `INTEGRATION` fails on the undefined task.
      Command: `INTEGRATION`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** 12 subprocess cases (a `--no-start` run, isolated source pointer, crash-image copy of an isolated database with a non-empty `-wal`): 7 of 8 failed behaviourally at first (no report, no non-zero exits); later cases for the read-only destination (a 0o755 directory not chmodded, a removed directory not recreated, a removed marker not recreated) failed against the first implementation.
- [x] `[AI] [AC-BI-07, AC-BI-17]` **GREEN** — add `apps/bnest-app/lib/mix/tasks/bnest.backup.reconcile.ex`, printing
      the same path-free report as the log. It resolves the production database path with `Storage.database_path/0`,
      copies the database and its `-wal` twice into a private scratch directory and accepts the pair as the
      [Scratch-copy read](tech-docs.md#reconciliation-detector) states, writes a scratch storage pointer file (`schemaVersion` `1`,
      `databaseDirectory`, `databaseFilename`, `phase` `sqlite_primary`, `migrationId`: every key
      `FileConfigStore` requires) and sets `BNEST_STORAGE_CONFIG` to it. It then follows the `bnest.storage.*` Mix task
      pattern: `Mix.Task.run("app.config")`, `Application.ensure_all_started(:ecto_sql)` and `(:exqlite)`, and
      `Storage.ensure_started!/0`, so only the repository starts, on the copy. It never calls `app.start` (which would
      start the Scheduler against the production `runtime_root`), sets `:scheduler_automatic?` to `false` before any
      start, and never opens the production file. **Proof:** `INTEGRATION` passes, including the no-Scheduler
      assertion. Command: `INTEGRATION`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** the task resolves the production database path, then `Storage.with_database_copy/2` copies the database and `-wal` twice as plain bytes into a private 0700 scratch directory, requires both copies to agree (verified-run count and latest `finished_at`; one fresh pair on disagreement, then a path-free `ledger unstable` reason), writes a scratch pointer with every key `FileConfigStore` requires, sets `BNEST_STORAGE_CONFIG`, starts only `ecto_sql`, `exqlite` and the repository on the copy, never `app.start`, sets `scheduler_automatic?` false first, restores the setting and removes the scratch directory on exit. The subprocess cases assert the source database and `-wal` byte-identical, no `-shm` created, and `Process.whereis` of `BnestApp.Scheduler` and `.Tasks` both nil. **Deviation:** the copy effects live in a Storage facade function, a `Maintenance` port callback pair and `Storage.Adapters.ScratchCopy`, because the architecture scan forbids `File` and `System.cmd` in `Mix.Tasks.Bnest.*`; the scan was not weakened. **Safety fix:** destination resolution is the new read-only `Backup.read_destination/0` (no mkdir, chmod or marker creation), after the executor found that `destination/0` would write.
- [x] `[AI] [AC-BI-07]` **REFACTOR** — make the log line, the telemetry metadata and the task call the wording function
      added above and delete any formatting of their own, so that the Phase 9 label renders from the same result.
      **Proof:** `INTEGRATION` and `BE_UNIT` still pass, and one grep for each state's wording finds one definition.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** the log, telemetry metadata and task call `report/1` and `render/1` only; a grep of `lib/` for each state's wording finds one definition in `reconciliation.ex`; `BE_UNIT` and `INTEGRATION` still pass.
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18]` Make the behavioural red from Phase 4 green. Command: `BEHAVIOUR`. **Proof:**
      it passes.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** all 19 Phase 4 scenarios pass in both layers (suite totals below). `BEHAVIOUR` exit 0 (13 features, 182 scenarios, 1087 steps, 492 bindings per layer; Vitest binding coverage passed). AC-BI-18 is not part of this green: its Rule moves to Phase 7 (deviation recorded in Phase 4).
- [x] `[AI] [AC-BI-14]` **Early live read-only reconcile (dated).** As soon as the items above pass, run
      `mix bnest.backup.reconcile` from the execution worktree against production, with the deployment environment [Releasing Bnest](../../../docs/how-to-guides/releasing-bnest.md) derives, under
      the Phase 1 approval. It must complete before the nightly slot of 2026-10-07T19:00Z (the first run on WIB date
      2026-10-08) finishes retention, when the first lost night leaves the seven latest WIB dates. Record the run's
      date and time. **Proof:** the report lists the 2026-09-30T19:00Z and 2026-10-01T19:00Z slots as missing and the
      other retained verified runs as present, the production directory is equal under the Phase 2 comparison rule (as the owner amended it on 2026-10-04: the
      storage lock directory's modification time is also excluded), and
      the task started no Scheduler and opened no production database file (no `-shm` or `-wal` created or touched by
      it; the running service's own changes are excluded). If the window has closed, record AC-BI-14 `Not applicable: aged out` with the date,
      and note the other retained runs are reported present. If the decision point of the fallback timing above passed
      first, record the disposition that paragraph selects instead (`Detector not ready: Phase 2 table stands`,
      `Detector not ready: Phase 2 only` or `Phase 2 not run by the slot`).
      **Evidence 2026-10-04T09:21Z (run ended 09:21:41Z; between the slots of 2026-10-03T19:00Z and 2026-10-04T19:00Z):**
      `mix bnest.backup.reconcile` run from the execution worktree under the Phase 1 approval (OD-1, R1), exit status 1,
      report: `Backup files: 2 of 7 retained backups need attention`, `2026-10-01: file missing`, `2026-10-02: file missing`.
      The dates are the WIB dates of the slots 2026-09-30T19:00Z and 2026-10-01T19:00Z, so the two lost nights are reported
      missing and the other five retained verified runs are reported present (counted, not listed). AC-BI-01: the pre-state
      (09:21:25Z) and post-state snapshots of the backup directory listing and extended attributes, the marker hash, the
      private configuration directory listing and file hashes, and the ledger rows are equal under the comparison rule as
      the owner amended it; the single difference is the storage lock directory's modification time (service-owned,
      excluded by the amendment). The task never ran `app.start` and started no Scheduler (proved by the subprocess
      test); it read the ledger from scratch copies, so it never opened the production file (a `-shm` file exists beside
      the production database because the running service holds it open; the task created none). The window had not
      closed: AC-BI-14 is proved here; no fallback disposition applies.
- [x] `[AI]` Commit U2 as thematic commits when authorized. **Proof:** the authorization line and the commit subjects,
      or `No commit authorized`.
      **Evidence 2026-10-04 (delegated to `swe-developer`, verified by the executor):** authorized by the owner's execution authority relayed to the executor. Commits: `docs(plans): record the backup integrity phase 4 evidence`; `test(backup): specify and bind the backup reconciliation scenarios`; `feat(scheduler): add a read-only verified runs query`; `feat(storage): read the database from scratch copies`; `feat(backup): reconcile verified runs against the backup folder`; the Phase 5 evidence commit follows.
- [x] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18]` **Blocking checkpoint — Phase 5.** `BE_UNIT`, `INTEGRATION`, `BEHAVIOUR` and
      the architecture boundary scan are green and the early live run, or its fallback disposition, is recorded.
      **Checkpoint passed 2026-10-04:** `BE_UNIT` 690 tests 0 failures (coverage 99.69%), `INTEGRATION` 457 tests 0 failures (11 `@integration-exempt` front-end scenarios excluded by the target; the architecture boundary scan `hexagonal_layering_test.exs` is part of it), `BEHAVIOUR` exit 0, `typecheck` and `lint` exit 0, `REPO` exit 0, all re-run by the executor after the last code change; the early live run is recorded above.

## Phase 6 — Verdict Confirmation, Idea Brief and Cause-Specific Fix

The first four items are unconditional and come after Phase 5 so that nothing window-bound waits on them (decision D11).
Every item after them is conditional on the confirmed verdict and carries that disposition. The branch table in
[`tech-docs.md`](tech-docs.md#branch-selection) is the single statement of which criteria apply to which verdict.

- [ ] `[HUMAN] [AC-BI-02]` The owner reviews V1 and confirms the branch selection together with the Phase 3 provisional
      dispositions and label state set. This is required before any conditional item below and before the Phase 12
      release, and not before Phases 4 and 5. The alert surface (OD-3, the admin-page label) and the idea brief (OD-4) were
      decided on 2026-10-03 and are not reopened here. Reason: external authority (a decision that is the owner's, not
      available to the executor). **Proof:** a dated decision naming what was put to the owner and what they chose.
      Predeclared fallback: if the owner changes the verdict or a disposition, the executor amends the affected Phase 4
      Rules and the Phase 5 and Phase 6 items as their own cycles; until the confirmation is recorded the Phase 6
      checkpoint cannot pass, so Phases 7 onward do not start.
- [ ] `[AI] [AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-19]` Confirm or amend the provisional dispositions and the label's state
      set against the owner's decision: update each conditional item's disposition and the
      [UI Design section](tech-docs.md#ui-design). **Proof:** every conditional item carries its final disposition, or
      the statement that the owner's decision left V1's dispositions unchanged.
- [ ] `[AI]` OD-4: create the idea brief `plans/ideas/q2-not-urgent-important/off-dropbox-backup-second-copy.md` for an
      off-Dropbox second backup copy, whatever the verdict (including `C-UNPROVEN`), as a two-page brief in the order that
      [`plans/ideas/README.md`](../../ideas/README.md) states, from the confirmed V1: the verdict's cause class, why a
      single Dropbox-synced destination is the exposure the verdict shows or cannot exclude, a sketch, what would make it
      not worth doing, and a promotion signal. It states plainly that building a second copy is not committed. Add it to
      the Ideas list and the Directory Map of `plans/ideas/q2-not-urgent-important/README.md`. Dates and counts only: no
      path, digest, destination identifier or run ID, per
      [data safety](../../../repo-governance/conventions/public-repository-data-safety.md). Commands:
      `rtk ./rhino md internal-link validate` and `rtk ./rhino governance directory-map validate`. **Proof:** the brief
      exists, both index entries list it, and both commands report no findings.
- [ ] `[AI]` Commit the idea brief as its own thematic commit when authorized (see Execution Status and Authority).
      **Proof:** the authorization line and the commit subject, or `No commit authorized`.

- [ ] `[AI] [AC-BI-08]` **Conditional: C-RET, C-TEST, or C-UNPROVEN with H3 open.** **Characterization** — extend
      `apps/bnest-app/test/integration/bnest_app/backup/backup_test.exs`: eight owned dates beside a foreign-destination
      receipt, an unreceipted artifact and a malformed receipt; retention removes exactly the owned pairs outside the
      seven latest dates and touches nothing else. Predeclare the mutation in the commit message before running: make
      `Backup.owned_receipts/1` count foreign receipts. Run first on unmodified code (a failure here is a real defect and
      the item is a normal red), then with the mutation. **Proof:** the unmodified run's result and the mutated run
      failing for the behavioural reason. Command: `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable (H3 stays open, so AC-BI-08 applies as defence in depth).
- [ ] `[AI] [AC-BI-08]` **Conditional: as above.** **GREEN** — change retention only if the unmodified run failed.
      **Proof:** `INTEGRATION` passes. Command: `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable, and the GREEN edit happens only if the unmodified run fails.
- [ ] `[AI] [AC-BI-08]` **Conditional: as above.** **REFACTOR** — remove the mutation. **Proof:** `INTEGRATION` still
      passes and the tree has no leftover mutation.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable (H3 stays open, so AC-BI-08 applies as defence in depth).
- [ ] `[AI] [AC-BI-09]` **Conditional: C-TEST, or C-UNPROVEN with H3 open; not C-RET.** **Characterization** — add a
      unit test in `apps/bnest-app/test/unit/bnest_app/backup/config_test.exs` and an integration case that the test
      environment's default destination is under the per-run test root and that resolving the checkout's `data/backup`
      fails closed, with the production listing unchanged. Predeclare the mutation: remove the `:backup_repository_root`
      setting from `config/test.exs`. Run first on unmodified code, then with the mutation. **Proof:** the unmodified
      result and the mutated run failing for the behavioural reason. Commands: `BE_UNIT`, `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable (H3 stays open, so AC-BI-09 applies as defence in depth).
- [ ] `[AI] [AC-BI-09]` **Conditional: as above.** **GREEN** — close any remaining path in `config/test.exs` or
      `test/support/test_backup_destination.ex` only if the unmodified run failed. **Proof:** both commands pass.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable, and the GREEN edit happens only if the unmodified run fails.
- [ ] `[AI] [AC-BI-09]` **Conditional: as above.** **REFACTOR** — remove the mutation; one place states the test-root
      derivation. **Proof:** both commands pass and the tree has no leftover mutation.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable (H3 stays open, so AC-BI-09 applies as defence in depth).
- [ ] `[AI] [AC-BI-10]` **Conditional: C-RET or a supersession cause (H1, H3a), or C-LEDGER (H5).** **RED** — a test
      reproducing the minimal case Phase 3 recorded in V1: for supersession, in
      `apps/bnest-app/test/integration/bnest_app/backup/backup_test.exs`, a newer same-date owned receipt removing the
      only production-keyed verified run of a date; for C-LEDGER, in
      `apps/bnest-app/test/integration/bnest_app/backup/scheduled_backup_test.exs`, the completion path recording
      `verified` without a promoted artifact. **Proof:** `INTEGRATION` fails for exactly that reason. Command:
      `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: V1 names no repository-side cause and records no minimal reproduction (H1 eliminated for production writers alone, H3a not reproduced, H5 eliminated).
- [ ] `[AI] [AC-BI-10]` **Conditional: C-RET or a supersession cause.** **GREEN** — apply the rule the owner confirmed
      in the first Phase 6 item in `retention.ex`. **Proof:** `INTEGRATION` and `BE_UNIT` pass.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: V1 names no repository-side cause and records no minimal reproduction (H1 eliminated for production writers alone, H3a not reproduced, H5 eliminated).
- [ ] `[AI] [AC-BI-10]` **Conditional: C-RET or a supersession cause.** **GREEN** — update
      `repo-governance/conventions/runtime-flat-file-data.md` and `specs/` if the rule restates "one newest pair per
      date". **Proof:** the changed lines name the rule; `REPO` passes.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: V1 names no repository-side cause and records no minimal reproduction (H1 eliminated for production writers alone, H3a not reproduced, H5 eliminated).
- [ ] `[AI] [AC-BI-10]` **Conditional: C-LEDGER.** **GREEN** — correct the completion path the reproduction names in
      `scheduled_backup_task.ex` or `sqlite_schedule_store.ex`. **Proof:** `INTEGRATION` and `BE_UNIT` pass.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: V1 names no repository-side cause and records no minimal reproduction (H1 eliminated for production writers alone, H3a not reproduced, H5 eliminated).
- [ ] `[AI] [AC-BI-10]` **Conditional: as the RED item above.** **REFACTOR** — keep `Reconciliation` and `Retention` on
      one shared definition. **Proof:** `BE_UNIT` still passes.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: V1 names no repository-side cause and records no minimal reproduction (H1 eliminated for production writers alone, H3a not reproduced, H5 eliminated).
- [ ] `[AI] [AC-BI-19]` **Conditional: C-DEST.** **RED** — extend
      `apps/bnest-app/test/unit/bnest_app/backup/reconciliation_test.exs`: a receipt for a retained date naming a
      destination identity different from the marker's is reported as a destination mismatch by date (the words themselves are pinned by the Phase 5 wording cases), the report
      names neither identifier, and it states that runs lost without a surviving receipt are not seen. **Proof:** `BE_UNIT`
      fails on the undefined mismatch state. Command: `BE_UNIT`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: C-DEST is not selected (H4 eliminated).
- [ ] `[AI] [AC-BI-19]` **Conditional: C-DEST.** **GREEN** — the facade reads the destination identity of each
      receipt in the directory (not only owned ones) and `Reconciliation` classifies a differing one as the mismatch
      state, in `reconciliation.ex` and `backup.ex`. **Proof:** `BE_UNIT` passes. Command: `BE_UNIT`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: C-DEST is not selected (H4 eliminated).
- [ ] `[AI] [AC-BI-19]` **Conditional: C-DEST.** **REFACTOR** — keep the mismatch wording in the one formatting function
      the log, telemetry and Mix task share. **Proof:** `BE_UNIT` and `INTEGRATION` still pass. Commands: `BE_UNIT`,
      `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: C-DEST is not selected (H4 eliminated).
- [ ] `[AI] [AC-BI-10]` **Conditional: C-DROPBOX or C-UNPROVEN.** Record `Not applicable: no repository-side cause`
      for the fix items, and route any owner-side action (Dropbox settings, a second device) to `learnings.md` for
      resolution. **Proof:** the disposition and the routed entry.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** applicable: V1 is `C-UNPROVEN`, so the fix items are recorded `Not applicable: no repository-side cause`.
- [ ] `[AI]` Commit U3 as thematic commits when authorized. **Proof:** the authorization line and the commit subjects,
      or `No commit authorized`.
- [ ] `[AI] [AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-19]` **Blocking checkpoint — Phase 6.** The owner's confirmation of V1 and the idea
      brief are recorded, every conditional item is ticked with evidence or dispositioned `Not applicable`, and
      `APP_QUICK` is green.

## Phase 7 — Restore Drill Tooling

- [ ] `[AI] [AC-BI-11, AC-BI-18]` **RED** — add
      `apps/bnest-app/test/integration/mix/tasks/bnest_backup_restore_drill_test.exs` (a real filesystem is needed, so
      this is an integration test, not a unit test): the task restores a synthetic artifact from an isolated
      destination into a fresh marked root, prints redacted evidence, removes that root, refuses a path outside the
      destination, refuses a non-regular file, creates no restore root on a refusal, and never opens the live
      database. Any pure target-classification rule exposed on the `Backup` facade is a unit case in
      `apps/bnest-app/test/unit/bnest_app/backup/backup_test.exs`. **Proof:** `INTEGRATION` (and `BE_UNIT` for the
      pure case) fails on the undefined task. Commands: `INTEGRATION`, `BE_UNIT`.
- [ ] `[AI] [AC-BI-11, AC-BI-18]` **GREEN** — add `apps/bnest-app/lib/mix/tasks/bnest.backup.restore_drill.ex` over
      `Backup.restore/1`. **Proof:** `INTEGRATION` and `BE_UNIT` pass. Commands: `INTEGRATION`, `BE_UNIT`.
- [ ] `[AI] [AC-BI-11, AC-BI-18]` **REFACTOR** — reuse the destination resolution and exit-code conventions of the
      neighbouring Mix tasks. **Proof:** `INTEGRATION` still passes. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-11]` Smoke the task end to end against a synthetic artifact in an isolated destination, never the
      production directory. **Proof:** exit status 0, redacted evidence printed, the restored root removed.
- [ ] `[AI] [AC-BI-11]` Write `docs/how-to-guides/restoring-a-bnest-backup.md` (a how-to, per
      [Diátaxis](../../../repo-governance/conventions/documentation-architecture.md)): choose an artifact, run the
      task, read the evidence, what a failure means, what to do on a failure. Add it to
      `docs/how-to-guides/README.md`. **Proof:** the guide exists, is linked, and a cold reader can follow it.
      acceptance: `grep -c 'restoring-a-bnest-backup' docs/how-to-guides/README.md` prints at least `1` (the guide is
      linked).
- [ ] `[AI]` Commit U4 as thematic commits when authorized. **Proof:** the authorization line and the commit subjects,
      or `No commit authorized`.
- [ ] `[AI] [AC-BI-11, AC-BI-18]` **Blocking checkpoint — Phase 7.** The task is proven on a synthetic artifact and the
      guide is linked.
      acceptance: `grep -c 'restoring-a-bnest-backup' docs/how-to-guides/README.md` prints at least `1` (the guide is
      linked).

## Phase 8 — UI Design: Copy Reconciliation and Owner Design Review

The design itself was produced at plan time under [Plan UI Design](../../../repo-governance/conventions/plan-ui-design.md)
(decision D6): the twelve SVG assets and their `README.md` in [`assets/`](assets/README.md), the comparison, the selected
alternative `row` (D7), the tokens and components, and the twelve embeds are in the
[UI Design section](tech-docs.md#ui-design). This phase starts after the Phase 7 checkpoint, changes no file under `apps/`
or `specs/`, and is unconditional because the owner selected the label (OD-3). Nothing in Phases 1 to 5 waits for it.
Affected route: `/admin/settings/schedules`. Rendered states: checking, all present, needs attention, could not be
checked, nothing to check yet, and destination mismatch on the C-DEST branch only. Viewport classes: desktop 1440 × 900,
tablet 768 × 1024 and mobile 393 × 851. The assets travel with the folder to `plans/in-progress/backup-integrity/assets/`
in Phase 1 and carry fictional content only.

- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Copy reconciliation. Replace the draft copy in the States and Real Copy table
      of the UI Design section with the exact output of the Phase 5 wording function for every state in the confirmed
      state set, and decide and record the date convention the page states (the ledger's slot date in UTC, or the WIB
      date that retention groups by). Where the function's output differs from the text drawn in the assets (the summary
      sentences, the singular and plural forms, the term and summary split, the date text), edit only that text in every
      affected asset, lo-fi and hi-fi alike, keeping the twelve file names. **Proof:** the table with each row traced to
      the function's output, the date convention stated, and the list of edited assets or `no asset text changed`.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Verify the assets and the section after any edit: `xmllint --noout assets/*.svg`
      reports no error, `rtk grep -h "<title" assets/*.svg` lists twelve distinct titles,
      `rtk grep -c "<desc" assets/*.svg` shows one description in each, Prettier passes over the plan folder
      (`rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- prettier --check plans/in-progress/backup-integrity`),
      `rtk ./rhino md internal-link validate` and `rtk ./rhino governance directory-map validate` report no findings, and
      no asset or section contains a real account, credential, private identifier or production value. **Proof:** each
      command's result and the manual scan.
- [ ] `[HUMAN] [AC-BI-21, AC-BI-22, AC-BI-23]` Owner design review. The owner reviews the UI Design section: the nine
      lo-fi and three hi-fi assets, the comparison, the selected alternative `row` (D7) and the reconciled copy, and
      records `Approved`, or `Changed to <option>`. Reason: external authority (approving a design is the owner's
      decision, not significance). **Proof:** a dated decision line naming what was put to the owner and what they chose.
      Predeclared fallback: if the owner selects another alternative, the executor draws that option's three hi-fi assets
      (`ui-<option>-hifi-desktop.svg`, `-tablet.svg` and `-mobile.svg`) to the same standard, removes the three `row` hi-fi
      assets, updates the selected and not-selected labels, the comparison rationale, the plan `README.md` preview, the
      assets `README.md` and File Impact, and asks once more for approval; if the owner cannot review, Phase 9 does not
      start, because the label is not built on an unreviewed design, and the executor reports the wait.
- [ ] `[AI]` Commit U5 (design copy) as a thematic commit when authorized. **Proof:** the authorization line and the
      commit subject, or `No commit authorized`.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` **Blocking checkpoint — Phase 8.** The copy is reconciled and agrees between
      the section and the assets, the twelve assets exist and are embedded with one alternative selected, the owner's
      design review is recorded, and no file under `apps/` or `specs/` has changed.
      acceptance: `grep -c '^Phase 8 checkpoint met:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Phase 8 checkpoint met:`).

## Phase 9 — Schedules-Page Integrity Label: Specification and Implementation

Gherkin, then bindings, then an Nx red, then code, then smoke, as the project rule requires, starting from the selected
and owner-reviewed design. This phase starts after the Phase 8 checkpoint and needs the Phase 5 reconciliation and the
Phase 6 states; its C-DEST items are conditional. It adds no migration and stores nothing
([decision D4](tech-docs.md#decisions-recorded-with-the-expansion-of-2026-10-03)). Route `/admin/settings/schedules`.

- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Add Scenarios to
      `specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature` transcribing AC-BI-21 (every retained backup present;
      each missing or changed date named; could not be checked; nothing to check yet; checked again after a save),
      AC-BI-22 (never writes; no private value; does not delay the page and is cancelled at the ceiling; a
      non-administrator causes no check) and AC-BI-23 (the viewport outline; reachable and announced without a pointer),
      plus the page scenario of AC-BI-19 on C-DEST. The scenarios that need the rendered page (AC-BI-21 present, attention
      and the re-check after a save, AC-BI-23) are covered by `bnest-app-fe-e2e`; a scenario that needs a forced failure, a
      controlled slow store, an empty ledger or a filesystem comparison carries `@e2e-exempt` with an `Exemption(e2e)`
      comment naming its `bnest-app:test:integration` alternative. No AC-BI-23 Examples row is exempted. Omit the AC-BI-19
      scenario if its disposition is `Not applicable`. **Proof:** each scenario names an outcome visible on the page; no
      placeholder, no-op or outcome table.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** AC-BI-19 page scenario `Not applicable` (C-DEST not selected).
- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Update `specs/apps/bnest/app-fe/architecture.md` as
      [`tech-docs.md`](tech-docs.md#specification-changes) states: Component View for the Schedules page integrity label,
      its off-render-path time-boxed check and its re-check after a save; Constraints for a read-only label that stores
      nothing; Behaviour Traceability for the new scenarios. Record the Container View as deliberately unchanged.
      **Proof:** those locations changed and no other.
- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Bind the new scenarios in
      `apps/bnest-app/test/behaviour/steps/scheduled_backup_steps.exs` with the drivers in
      `apps/bnest-app/test/unit/support/home_page_driver.ex` and `apps/bnest-app/test/integration/support/home_page_driver.ex`,
      and in the browser harness in `apps/bnest-app-fe-e2e/tests/steps/scheduled-backups.steps.ts` and
      `apps/bnest-app-fe-e2e/tests/support/scheduled-backups.ts` (seed through
      `apps/bnest-app/test/integration/support/seeds/schedules.ex`). The browser step sets the viewport from each AC-BI-23
      Examples row with `page.setViewportSize` (decision D9), because the projects default to 1280 × 720, 768 × 1024 and
      the Pixel 5 profile, so the 320 × 568 and 1440 × 900 rows run at their own width. Update
      `apps/bnest-app-fe-e2e/behaviour-coverage.json` as `FE_E2E_COVERAGE` requires, then capture the **RED**. Commands:
      `BEHAVIOUR`, then `FE_E2E_CASE` for the rendered scenarios. **Proof:** both fail because the label does not exist,
      not because of compilation or configuration.
- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Run the repository specification-map gate. Command: `REPO`. **Proof:** it passes and
      the record names every specification file changed.
- [ ] `[AI] [AC-BI-21, AC-BI-22]` **RED** — extend `apps/bnest-app/test/integration/bnest_app_web/admin_settings_live_test.exs`
      over an isolated destination and an isolated ledger seeded with synthetic runs: the connected page shows all
      present, a missing and a changed date by date and state, could not be checked when reconciliation raises (the page
      and both forms still render), and nothing to check yet; the disconnected render shows checking and opens neither the
      ledger nor the destination; the destination listing, file bytes and ledger rows are unchanged after a render and a
      reload; the rendered text and attributes carry no path, digest, destination identifier or run ID; a non-administrator
      gets not found and no reconciliation starts. **Proof:** `INTEGRATION` fails on the absent label. Command:
      `INTEGRATION`.
- [ ] `[AI] [AC-BI-21, AC-BI-22]` **GREEN** — in `apps/bnest-app/lib/bnest_app_web/live/admin_schedule_settings_live.ex`,
      on the connected mount only, `assign_async` the result of `Scheduler.verified_runs/1` and `Backup.reconcile/2`,
      mapping a raise, an exit or an unreadable ledger to the could-not-be-checked state; the disconnected mount assigns the
      checking state and touches neither; render the structured result through the one wording function, in the markup the
      selected design fixes. **Proof:** `INTEGRATION` passes. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-22]` **RED** — extend the same `admin_settings_live_test.exs` for the time-box: with the ceiling lowered
      through application configuration (default five seconds) and a reconciliation stand-in that blocks past it, the page
      and both forms render first, the label reads checking and then could not be checked at the ceiling, and the
      stand-in's work process is dead (a monitored `:DOWN`) shortly after the ceiling with no further read of the
      destination, so the work is cancelled and not left running. **Proof:** `INTEGRATION` fails because nothing yet
      cancels the work at the ceiling. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-22]` **GREEN** — put the ceiling inside the async function in `admin_schedule_settings_live.ex`: run
      the reconciliation in a task the function owns and monitors, wait with `Task.yield/2` for the ceiling, and on no reply
      call `Task.shutdown/2` and return the could-not-be-checked result (`assign_async/3` has no timeout of its own).
      **Proof:** `INTEGRATION` passes, including the cancellation assertion. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-21]` **RED** — extend the same `admin_settings_live_test.exs` for the re-check after a save: after a
      successful `save_schedule`, and after `save_backup` with the folder left unchanged, the label returns to checking and
      then shows the new result when an expected artifact was removed in between; a failed save starts no check; a second
      save while the first check is in flight leaves only the newer result; the focus does not move. **Proof:**
      `INTEGRATION` fails because the label keeps its first result. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-21]` **GREEN** — one function in `admin_schedule_settings_live.ex` starts the check; the connected mount
      and the successful branches of `save_schedule` and `save_backup` all call it, resetting the label to checking and
      superseding a check still in flight. **Proof:** `INTEGRATION` passes. Command: `INTEGRATION`.
- [ ] `[AI] [AC-BI-21, AC-BI-22]` **REFACTOR** — the LiveView holds no second copy of the state wording or the date
      formatting; the log, telemetry metadata, Mix task and label all render from `Reconciliation`'s one function.
      **Proof:** `INTEGRATION` and `BE_UNIT` still pass, and one grep for each state's wording finds one definition.
      Commands: `INTEGRATION`, `BE_UNIT`.
- [ ] `[AI] [AC-BI-19]` **Conditional: C-DEST. RED** — extend the same LiveView test with a surviving receipt for a retained
      date that names another destination identity: the label lists that date as a destination mismatch, names neither
      identifier, and states that runs lost without a surviving receipt cannot be seen this way. **Proof:** `INTEGRATION`
      fails on the absent state. Command: `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: C-DEST is not selected (H4 eliminated).
- [ ] `[AI] [AC-BI-19]` **Conditional: C-DEST. GREEN** — render the mismatch state from the structured result in
      `admin_schedule_settings_live.ex`. **Proof:** `INTEGRATION` passes. Command: `INTEGRATION`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable`: C-DEST is not selected (H4 eliminated).
- [ ] `[AI] [AC-BI-23]` **Styling (format and lint proof, not a RED/GREEN cycle of its own)** — add the label styles
      to `apps/bnest-app/assets/css/app.css` per the selected hi-fi: the page's tokens, problem lines that wrap and are
      never truncated, a text and marker cue for every state, a 2.75rem minimum target for any control, and any
      animation removed under `prefers-reduced-motion: reduce`. The behavioural RED for these styles is the
      `FE_E2E_CASE` red captured in the binding item above, which the item below turns green; a stylesheet has no
      unit-level test of its own. **Proof:** `APP_QUICK` is green (format and lint). The rendered result is proved by
      that red turning green and in Phase 10, and never by this item alone. Command: `APP_QUICK`.
- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Make the behavioural red from this phase green. Commands: `BEHAVIOUR`,
      `FE_E2E_COVERAGE`, and `FE_E2E_CASE` for each rendered scenario title (the three viewport projects). **Proof:** all
      pass, with no undefined, ambiguous or unused binding.
- [ ] `[AI]` Commit U5 (specification and implementation) as thematic commits when authorized. **Proof:** the
      authorization line and the commit subjects, or `No commit authorized`.
- [ ] `[AI] [AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` **Blocking checkpoint — Phase 9.** `BE_UNIT`, `INTEGRATION`, `BEHAVIOUR`,
      `FE_E2E_COVERAGE` and the affected `FE_E2E_CASE` runs are green; the label exists in every Phase 3 state; no
      migration and no stored state were added.

## Phase 10 — Rendered Verification of the Label

Required by [Plan UI Design](../../../repo-governance/conventions/plan-ui-design.md) and the
[exploratory and usability review](../../../repo-governance/workflows/quality/exploratory-usability-review.md): a rendered
check at an exact served origin that automation, code inspection, inferred layout and the design assets supplement and
never replace. The origin is isolated and non-production: a Bnest started from the execution checkout in its tmux pane per
the [development server restart workflow](../../../repo-governance/workflows/maintenance/development-server-restart.md),
with isolated runtime roots, an isolated storage pointer (`BNEST_STORAGE_CONFIG`), an isolated backup configuration
(`BNEST_BACKUP_CONFIG`) and repository root, and a synthetic `test-user-` administrator. The production origin and
production data are never used. Both passes are passive and non-destructive under
[live-service continuity](../../../repo-governance/development/live-service-continuity.md). Route
`/admin/settings/schedules`; states as in the [UI Design section](tech-docs.md#states-and-real-copy); viewport classes desktop 1440 × 900, tablet 768 × 1024 and mobile
393 × 851, with the 320 px reflow floor checked inside mobile.

- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Start the isolated origin and seed it so each state is reachable (all present, one missing, one
      changed, could not be checked, none verified, and the mismatch on C-DEST), by seeding the isolated destination and
      ledger or by lowering the ceiling. **Proof:** the exact origin (host and port) and the state list by name, no private
      value.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** the mismatch state is `Not applicable` (C-DEST not selected); the other states apply.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Audit the rendered states at each viewport class for accessibility: the accessibility tree, controls,
      keyboard and focus, non-colour cues, narrow reflow and contrast, with Lighthouse when available. A passing functional
      run waives no finding. **Proof:** a route, state, viewport class and result table in `learnings.md`.
      acceptance: `grep -c 'Accessibility audit' plans/backlog/backup-integrity/learnings.md` prints at least `1` (the
      item writes a table headed `Accessibility audit` in `learnings.md`).
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Walk the full matrix by hand at the exact origin: route, every state, every viewport class and the 320 px
      floor. Exercise the changed interaction (a reload, the change from checking to the result, a save of each form and the
      re-check that follows, the keyboard path through the page, and both existing forms still usable) and confirm layout, content, focus and responsive behaviour.
      **Proof:** a route, state, viewport class and pass or fail table in `learnings.md`, with no private values.
      acceptance: `grep -c 'Manual matrix' plans/backlog/backup-integrity/learnings.md` prints at least `1` (the item
      writes a table headed `Manual matrix` in `learnings.md`).
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` **Exploratory pass (spec-aware), first.** Drive Playwright MCP against the running origin across all
      three viewport classes with isolated `test-user-` identities, mutating no shared or production state. Compare live
      behaviour with the changed `specs/**` Gherkin and probe beyond the scripted cases: boundary conditions, route
      structure and passive security signals such as an exposed identifier or a missing authorization check. **Proof:**
      every finding under the exact heading `## Exploratory findings` in `learnings.md`, each with its route, state and
      category, and no private values. This pass is finished and recorded before the usability pass begins.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` **Usability pass (spec-blind), second.** Blindness must be structural: delegate the pass to a fresh
      agent context given only the origin, the route and the viewport classes, and withhold the specs, the source and
      the design assets. If no delegation is available, run it and record explicitly that it ran spec-aware. Judge only
      first-time-user perception against Nielsen's ten heuristics, a cognitive walkthrough, the empty, loading and error
      states, and responsive usability. **Proof:** findings under the exact heading `## Usability findings`, never merged
      into the exploratory section.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Cross-reference the two sets: where an exploratory and a usability finding describe one underlying
      defect, add a short note in both sections naming the shared root cause. **Proof:** the notes, or a statement that no
      pair shared a root cause.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Reconcile every finding that reveals correct-but-unspecced behaviour through the
      [BDD Iron Rule](../../../repo-governance/development/behaviour-driven-development.md#iron-rule) as its own cycle:
      update the Gherkin, bind failing steps, confirm RED, then implement; label a usability-sourced proposal as such and
      never merge an unreconciled proposal into `specs/**`. Commands: `BEHAVIOUR`, `FE_E2E_COVERAGE`. **Proof:** for each
      accepted proposal the scenario name with its RED and GREEN results, or a statement that none was proposed.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Fix every finding or accept it as non-blocking with its reason written in `learnings.md`, and rerun
      the affected automated commands after each fix. **Proof:** a resolution per finding and the green reruns.
      acceptance: `grep -c 'Finding resolution' plans/backlog/backup-integrity/learnings.md` prints at least `1` (the
      item writes a per-finding table headed `Finding resolution` in `learnings.md`).
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Confirm, before the checkpoint, that both passes ran, that findings are present or recorded as none
      found, that both headings are correctly labelled, that cross-references are noted, and that every accepted spec
      proposal completed the Iron Rule. **Proof:** the confirmation in `learnings.md` against each of the five conditions.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Clean up the browser work: close every page, tab and browser context the passes created, also after
      a failure; inspect the controlled tabs and close the navigation tabs; stop the isolated origin and any watcher. **Proof:**
      no controlled tab and no isolated server process remains.
- [ ] `[AI]` Commit U5 (findings and fixes) as thematic commits when authorized. **Proof:** the authorization line and the
      commit subjects, or `No commit authorized`.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` **Blocking checkpoint — Phase 10.** The matrix, the accessibility audit, the exploratory pass and the
      usability pass are recorded and separately labelled; every finding is fixed or accepted with its reason; cleanup is
      complete.
      acceptance: `grep -c '^Phase 10 checkpoint met:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Phase 10 checkpoint met:`).

## Phase 11 — Documentation, Rules and Repository Gates

- [ ] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Update `apps/bnest-app/README.md` for the two Mix tasks, the post-run reconciliation and the
      Schedules page label, per [project READMEs](../../../repo-governance/conventions/project-readmes.md), and run
      [Docs Propagation](../../../repo-governance/workflows/quality/docs-propagation.md). **Proof:** its terminal result,
      which may be `no-change`.
      acceptance: `grep -c '^Docs Propagation result:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Docs Propagation result:`).
- [ ] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Re-read
      `specs/apps/bnest/app-be/architecture.md` and `specs/apps/bnest/app-fe/architecture.md` against the as-built code and
      reconcile them: Component View, Constraints, and any verdict-specific change from Phase 6. **Proof:** a line per
      changed location, or `no-change` with the reason.
      acceptance: `grep -c '^Architecture reconcile:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Architecture reconcile:`).
- [ ] `[AI] [AC-BI-10]` **Conditional: Phase 6 changed a rule.** Apply the bounded
      [rules-propagation workflow](../../../repo-governance/workflows/quality/rules-propagation.md) to any rule changed
      in Phase 6, and record its terminal result, which may be `no-change`.
      **Provisional disposition (V1, `C-UNPROVEN`, AI-recorded 2026-10-04, pending owner confirmation):** `Not applicable` provisionally: no rule change is expected (the AC-BI-10 fix items are `Not applicable`); applies only if a Phase 6 characterization fails on unmodified code and its fix changes a rule.
- [ ] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Run the
      [Gherkin implementation review](../../../repo-governance/workflows/quality/gherkin-implementation-review.md) over
      the changed backend and frontend features, bindings and exemptions. **Proof:** a row per expanded scenario with
      `PASS` or `EXEMPT`; any `FAIL` is repaired before the checkpoint.
- [ ] `[AI] [AC-BI-21, AC-BI-22, AC-BI-23]` Confirm the [exploratory and spec-blind usability passes](../../../repo-governance/workflows/quality/exploratory-usability-review.md)
      are **applicable**, because the owner's OD-3 added a rendered surface (they are not `Not applicable`), and that
      Phase 10 recorded them under `## Exploratory findings` and `## Usability findings` in `learnings.md`, each finding
      fixed or accepted with its reason. **Proof:** a confirmation line naming both headings.
- [ ] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` Run `APP_QUICK`, `BEHAVIOUR`, `FE_E2E_COVERAGE`, `RELEASE_TEST` and `REPO`, and manually
      `curl` the unaffected GraphQL health path to confirm no behavioural change (no REST or GraphQL operation changed; the
      label is a rendered LiveView page, proved in Phase 10). **Proof:** each command's result and the exit status.
- [ ] `[AI]` Before committing, inspect the diff and the evidence in `learnings.md` for prohibited data (paths with
      identifiers, digests, destination IDs, run IDs) under
      [data safety](../../../repo-governance/conventions/public-repository-data-safety.md). Leak-review every commit
      before push. **Proof:** the review result per commit.
      acceptance: `grep -c '^Leak review result:' plans/backlog/backup-integrity/delivery.md` prints at least `1` (the
      item writes a line beginning `Leak review result:`).
- [ ] `[AI]` Commit U6 as thematic commits when authorized. **Proof:** the authorization line and the commit subjects,
      or `No commit authorized`.
- [ ] `[AI] [AC-BI-03, AC-BI-04, AC-BI-05, AC-BI-06, AC-BI-07, AC-BI-08, AC-BI-09, AC-BI-10, AC-BI-11, AC-BI-15, AC-BI-16, AC-BI-17, AC-BI-18, AC-BI-19, AC-BI-21, AC-BI-22, AC-BI-23]` **Blocking checkpoint — Phase 11.** All commands green, propagation results recorded, Gherkin
      review has no `FAIL`, and the review passes are confirmed applicable and recorded.

## Phase 12 — Production Release

**Unconditional.** The detector and the Schedules-page label add code under `apps/bnest-app/lib/` in every branch, so a
release always follows, and one release carries both.
Follow [Releasing Bnest](../../../docs/how-to-guides/releasing-bnest.md) and the
[Caddy deployment workflow](../../../repo-governance/workflows/maintenance/development-caddy-deployment.md). The
budget is zero routed failures, p95 at most 500 ms, and every sample at most 2 s. The routed journey is read-only and
anonymous (health, login page and an anonymous LiveView and WebSocket connection): no synthetic user is provisioned on
the production origin. The release target itself qualifies synthetic `test-user-` identities at an isolated exact
origin, never in production. The label's rendered states are proved at an isolated exact origin in Phase 10, and on
production by the owner in Phase 13; no administrator session is provisioned for the executor.

- [ ] `[AI] [AC-BI-12]` Release preconditions: the owner's confirmation of V1 (the first Phase 6 item) and the owner's
      design review (Phase 8) are recorded and current, and the Phase 1 plan quality gate verdict is non-blocking.
      **Proof:** the two dated lines and the verdict line; without them the release does not start (decision D11).
- [ ] `[AI] [AC-BI-12]` Integrate the change by pull request under the
      [integration path](../../../repo-governance/conventions/integration-path.md); leak-review the exact head; wait
      for the `leak-review` status, polling no more often than every three minutes. **Proof:** merged head commit.
- [ ] `[AI] [AC-BI-12]` Record the pre-release baseline: at least 12 exact-origin samples and the read-only anonymous
      routed journey. **Proof:** sample count, p95 and maximum.
- [ ] `[AI] [AC-BI-12]` Start the candidate on a separate loopback port from the release revision. The active backend
      stays up; Tailscale is not repointed; nothing under the active server's watched tree is edited. **Proof:**
      candidate port and a healthy local HTTP response.
- [ ] `[AI] [AC-BI-12, AC-BI-13]` Verify the candidate: reported revision equals the release revision, read-back and
      the anonymous journey pass, LiveView and WebSocket connect. **Proof:** each check's result.
      acceptance: `grep -c '^Candidate verification:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Candidate verification:`).
- [ ] `[AI] [AC-BI-12]` Mixed-version safety: confirm the change adds read queries and no migration or schema change (the page
      label stores nothing), so both versions can share the store. Both run the scheduler; the slot claim makes that safe (decision G12 in
      [`tech-docs.md`](tech-docs.md#decision-record-pre-write-gate)). **Proof:** the diff shows no migration, and
      `INTEGRATION` passes the existing two-coordinator claim test in
      `apps/bnest-app/test/integration/bnest_app/scheduler/scheduler_test.exs`, which is in-process evidence only (two
      workers in one VM); the cross-process evidence is the ledger-row item below. If a migration is present, stop and
      re-plan.
- [ ] `[AI] [AC-BI-12]` Start continuous sampling of the exact routed origin, then switch Caddy's upstream with a
      graceful reload. **Proof:** sampling covers preflight, switch and drain; zero failures, p95 at most 500 ms, every
      sample at most 2 s.
- [ ] `[AI] [AC-BI-12]` Verify reconnect: an already-open anonymous LiveView session reconnects to the candidate
      without a manual refresh within the bounded drain. **Proof:** the reconnect observation.
      acceptance: `grep -c '^Reconnect observed:' plans/backlog/backup-integrity/delivery.md` prints at least `1` (the
      item writes a line beginning `Reconnect observed:`).
- [ ] `[AI] [AC-BI-12, AC-BI-13]` Routed proof: query the routed origin and the loopback backend for their revision.
      **Proof:** both report the release revision.
- [ ] `[AI] [AC-BI-12]` One ledger row per slot across candidate and active backend. While the candidate and the
      previous backend both run the scheduler, read the backup schedule's ledger through `LEDGER_COPY`,
      `LEDGER_CHECK` and `LEDGER_QUERY` (read-only; read R4 of the Phase 1 scope check) after the next 19:00 UTC slot that falls in the window, including a slot that lands
      mid-handoff, and confirm that slot has exactly one row and one artifact and receipt pair, whichever backend ran
      it (the loser inserts nothing, because the primary key `(schedule_key, claim_key)` rejects the second insert). Do
      not stop the previous backend while a row for the schedule is `running`; a stopped claimant's lease expires and
      the survivor recovers the run as the next attempt. If no slot falls in the window, record `no slot in window`
      and that only the in-process claim test then stands (the cross-process proof was not obtained), and keep both
      backends up through the next slot only if the owner retains rollback capacity. **Proof:** the per-slot row count,
      which is the cross-process evidence, or the recorded `no slot in window` with the passing in-process claim test,
      labelled as such. A duplicate row stops the plan for re-planning of the handoff.
- [ ] `[AI] [AC-BI-12]` Drain and clean up: after the bounded drain stop the previous backend only if rollback capacity
      is no longer retained by decision, and stop every unneeded candidate, watcher and temporary proxy. **Proof:**
      process list shows only the active route and the explicitly retained rollback capacity.
- [ ] `[AI] [AC-BI-12, AC-BI-13]` **Blocking checkpoint — Phase 12.** Routed backend serves the release revision, the
      budget held, cleanup is complete.
      acceptance: `grep -c '^Phase 12 checkpoint met:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Phase 12 checkpoint met:`).

## Phase 13 — Owner Drill and Live Detection Proof

The `[AI]` items are delivery unit U8 and the two `[HUMAN]` items are delivery unit U9.

- [ ] `[AI] [AC-BI-14]` Under the OD-1 approval recorded in Phase 1, run `mix bnest.backup.reconcile` read-only against
      production from the released revision. The two lost slots stay reportable only while they are among the seven
      latest WIB dates, which ends when the first run on WIB 2026-10-08 completes; if that has passed, rely on the
      Phase 5 early run and record this repeat `Not applicable: aged out`. **Proof:** the report lists the
      2026-09-30T19:00Z and 2026-10-01T19:00Z slots as missing and the other retained verified runs as present, or the
      aged-out disposition with the other retained runs reported present, and the production directory listing is equal
      to the Phase 2 post-state under the comparison rule as the owner amended it on 2026-10-04 (the storage lock directory's
      modification time is also excluded).
- [ ] `[HUMAN] [AC-BI-11]` The owner runs the restore drill once on one present production artifact following the
      guide, and records the redacted evidence and pass or fail. Reason (external authority, not significance): the
      artifact holds household members' chat content, which the test-data iron rule withholds from an agent, so only the
      data's owner can authorize reading it; the executor holds neither that authority nor an approved read. **Proof:**
      the evidence and a statement that the artifact and live database were not changed.
- [ ] `[HUMAN] [AC-BI-21, AC-BI-22, AC-BI-23]` The owner opens Schedules & backups on the routed origin with their own
      administrator session and reports, for the route `/admin/settings/schedules`, which state the label showed, the
      viewport class used (desktop, tablet or mobile), pass or fail, and whether it matched the reconcile report; no
      private value. Expect only the all-present state: the two lost nights will likely have aged out of the seven latest
      dates by then, so needs attention, could not be checked, nothing to check yet and checking are proved at the isolated
      exact origin in Phase 10 and are not claimed for production; if a lost night is still retained when the owner
      looks, the label may show needs attention for it, and the report says so. Reason: a credential the executor does
      not have, and the test-data iron rule bars provisioning a synthetic user on the production origin. **Proof:** the
      owner's report. Predeclared fallback: if the owner declines or cannot, record `Not performed` with the reason; the
      Phase 10 matrix at the isolated exact origin then stands as the rendered proof, labelled as such, and AC-BI-21 to
      AC-BI-23 are not claimed for the production origin.
- [ ] `[AI] [AC-BI-11, AC-BI-14, AC-BI-21, AC-BI-22, AC-BI-23]` Record the drill, the live detection and the label look
      in `learnings.md` as sanitized entries. If the drill failed, record it as an escalation to the owner and not as a
      plan failure. **Proof:** the entries.
- [ ] `[AI] [AC-BI-11, AC-BI-14, AC-BI-21, AC-BI-22, AC-BI-23]` **Blocking checkpoint — Phase 13.** The live detector
      reported the known gap (here or in Phase 5) or its window is recorded as aged out, the drill outcome is recorded,
      and the owner's look at the label on the live origin is recorded, with the state it showed (likely only all present), or
      `Not performed` with its reason.
      acceptance: `grep -c '^Phase 13 checkpoint met:' plans/backlog/backup-integrity/delivery.md` prints at least `1`
      (the item writes a line beginning `Phase 13 checkpoint met:`).

## Recovery and Rollback

Dormant until triggered. Each carries its trigger; otherwise record a dated `Not triggered` at reconciliation.

- [ ] `[AI]` **Trigger: any routed failure, p95 above 500 ms, or a sample above 2 s during Phase 12.** Route Caddy back to
      the previous healthy backend with a graceful reload, re-prove the journey and budget, stop the candidate, record a
      learning, and resume only when the live surface is healthy. **Proof:** the routed revision and budget evidence
      after the rollback.
- [ ] `[AI]` **Trigger: Phase 2 post-state differs from the pre-state beyond the comparison rule.** Stop, do not attempt
      to repair production, report the difference to the owner. **Proof:** the report.
- [ ] `[AI]` **Trigger: the post-run reconciliation fails or slows a scheduled backup in the candidate.** Revert the
      unit's commits and release the revert by the Phase 12 procedure. **Proof:** a clean backup run on the reverted
      revision.
- [ ] `[AI]` **Trigger: the label slows, breaks or alarms the Schedules page in the candidate or after the cutover.**
      Revert the label commits of Phases 9 and 10 and release the revert by the Phase 12 procedure, keeping the detector.
      **Proof:** the page renders both forms on the reverted revision and the routed revision is recorded.

## Archival

Archival runs after every substantive phase and is separate from them.

- [ ] `[AI]` Reconcile `learnings.md`: resolve every entry to one durable owner (governance, specification, test, code
      comment, permanent documentation, idea brief) or discard it with a reason, per
      [knowledge capture](../../../repo-governance/conventions/plans/008-knowledge-capture-and-archival.md). The OD-4 idea
      brief already exists from Phase 6: keep it current with the final verdict, and route any other owner-side Dropbox
      finding to an idea brief if it describes work. **Proof:** a resolution row per entry.
- [ ] `[AI]` Update `plans/ideas/q2-not-urgent-important/bnest-post-closure-follow-ups.md`: remove item 4 and its
      entries in the Problem, Direction and Risks sections now that this plan owns them, and fix its Q2 index line if the
      summary changed. **Proof:** the brief no longer lists the missing-backups investigation.
- [ ] `[AI]` Run the plan execution check and record its terminal verdict. **Proof:** the verdict line.
- [ ] `[AI]` Remove the artifacts the work created that the repository should not keep, following
      [dev artifact clean-up](../../../repo-governance/workflows/maintenance/dev-artifact-clean-up.md): `local-tmp/`
      scratch, the pre- and post-state files, any candidate, and the planning and execution worktrees and branches after
      their merges. **Proof:** a clean `git status` and no leftover process.
- [ ] `[AI]` Move this folder, with its `assets/` directory, from `plans/in-progress/backup-integrity` (where Phase 1 placed
      it) to `plans/done/YYYY-MM-DD__backup-integrity` with the completion date, update `plans/in-progress/README.md`,
      `plans/done/README.md` and every live reference to the old path, run `REPO` from the archived state, and commit the
      move when authorized. **Proof:** `REPO` green and no remaining reference to
      `plans/in-progress/backup-integrity` or `plans/backlog/backup-integrity`.
