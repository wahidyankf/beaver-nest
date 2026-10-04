# Learnings

A transient holding area. Every entry is resolved to one durable owner, or discarded with a reason, before archival.
Estimates are permitted here when labelled. Record only dates, counts and yes/no observations: no paths with
identifiers, digests, destination IDs or run IDs.

## Planning Decision Records

The pre-write gate (G1 to G12), the post-write gate (P1 to P6), the owner decisions OD-1 to OD-4 of 2026-10-03, the
expansion proposals D4 and D5, the gate pass 4 proposals D6 to D11, the confirmed reads R1 to R4 and the
pending-confirmation list are recorded once, in
[`tech-docs.md`](tech-docs.md#decision-record-pre-write-gate), each with its provenance: the owner made OD-1 to OD-4,
R1 to R4, D1 and the resolution of F1 (the UI design assets drawn in the plan now), and everything else is an agent
proposal pending owner confirmation. This file holds no decision record; it holds the discovery entries below.

## Plan Quality Gate Records

2026-10-03, first plan-checker pass: findings returned, not a passing verdict (3 HIGH, 13 MEDIUM, 7 LOW). Propagation
applied the repairs the plan's own decisions settle.

2026-10-03, second pass: further rows returned, which a second propagation addressed; the decisions it recorded are D1
(the owner's) to D3 (agent proposals D2 and D3) in
[`tech-docs.md`](tech-docs.md#decisions-and-investigations-recorded-after-the-first-pass).

2026-10-03, third pass: `PASS_WITH_FINDINGS`. M1 (mechanism that redirects the repository to the scratch copy: a scratch
storage pointer file, `BNEST_STORAGE_CONFIG`, only the repository started), M2 (ledger query file name, sidecar naming
and the equal-count command) and L1 (the claim test is single-VM evidence, the release phase (Phase 9 then, Phase 12 now) is the cross-process proof, a cited
release record) were fixed by a third propagation; L2 is this record. The owner's confirmation of D2 and D3 is pending.
That result applied to the folder as it stood before the expansion below.

2026-10-03, reset: the owner decided OD-1 to OD-4 and OD-3 added an administrator-facing label, with a UI Design
section, Phases 8 to 10, acceptance criteria AC-BI-21 to AC-BI-23, a shift in phase numbering (the former Phases 8 to 10
are now Phases 11 to 13) and file, README and delivery-unit changes. The third pass's verdict does not carry over to
this folder, so no verdict is current. The gate must be re-run on the expanded folder; its first item in
[`delivery.md`](delivery.md#phase-1--authorization-preflight-and-baseline) stays unticked until the terminal verdict
line is recorded there. The owner's confirmation of the items in
[`tech-docs.md`](tech-docs.md#pending-owner-confirmation) is also pending.

2026-10-04, fourth pass: `BLOCKED` on one High finding, F1 (the UI design assets had been deferred to Phase 8, but the
convention requires them in the plan), with six further findings, F2 to F7. A fourth propagation applied, within the
recorded decisions: F1, the twelve assets, their README, the comparison, the selection and the embeds (the owner's
resolution of F1, carried out by D6, with the comparison and the selection of `row` as agent proposals D6 and D7); F2,
the Phase 5 state-to-wording RED and GREEN and the empty-ledger output and exit of the Mix task (agent proposal D10); F3,
Phases 4 and 5 starting on the AI-recorded V1, the owner's confirmation moved to Phase 6, the idea brief moved after
Phase 5 and the fallback timing, with its 2026-10-07T12:00Z decision point, for the 2026-10-07T19:00Z window (agent
proposal D11); F4, the label's re-check after a save (agent proposal D8); F5, the time-box inside the async function with
a cancellation RED and the online-only note; F6, the viewport set per Examples row (agent proposal D9); F7, the
production-proof limit and the U8 and U9 split. The reads R1 to R4 were recorded as confirmed on 2026-10-03.
Provenance correction, 2026-10-04: an earlier version of this entry, and of the plan's decision record, README and
delivery checklist, recorded D6, D8, D9 and D11 as the owner's relayed decisions. The owner did not make them. Only the
F1 resolution behind D6 is the owner's; D6 beyond it and D7 to D11 are agent proposals pending owner confirmation. The
gate re-run is pending; its Phase 1 item stays unticked and no verdict is current.

2026-10-04, fifth pass: `PASS_WITH_FINDINGS` (M1 and M2 Medium, L1 to L5 Low). A fifth propagation re-validated each row
against the folder and applied it within the recorded decisions: M1, the Shape Choice of `tech-docs.md` rewritten to
justify the single file against the owner as a distinct reader (the Phase 6 verdict confirmation, the Phase 8 design
review of the UI Design, and the confirmation of the agent proposals in the decision tables), the file kept as one and
the one-sitting claim dropped; M2, the Dated Preconditions before Phase 1 (authorization by 2026-10-06T19:00Z, Phase 2
finished by 2026-10-07T12:00Z) and the dispositions `Detector not ready: Phase 2 only` and
`Phase 2 not run by the slot`, stated in D11 and Phase 5 as an extension of agent proposal D11; L1, a PRD note that D2
and D8 to D10 are agent proposals pending owner confirmation; L2, the BRD risk row now says the detector is built first and
is independent of the cause; L3, the backlog index summary now mentions the Schedules page label; L4, a Phase 4 Rule
pinning the state-to-wording mapping of the task report, with the Phase 5 wording items citing AC-BI-07
and AC-BI-17 only; L5, the Phase 9 styling item labelled as format and lint proof whose behavioural RED is the earlier
rendered red. The gate has not been re-run on the folder as that propagation left it; the Phase 1 item stays unticked
and records the terminal verdict line, so the pass 5 verdict is not claimed as current for this folder.

## Execution Entries

Phase 2 findings are recorded below as sanitized entries V0 onward; the Phase 3 verdict is entry V1. Phase 10 records two
separately labelled sections in this file, `## Exploratory findings` and `## Usability findings`, and the route, state,
viewport class and result tables of the rendered checks. Entries V0.1 to V0.12 record Phases 1 and 2, executed on
2026-10-04 between the 2026-10-03T19:00Z and 2026-10-04T19:00Z slots. Times are UTC; the WIB date of a slot is the next
calendar day (the slot of a given UTC date at 19:00Z is 02:00 WIB the following day).

### V0.1 Gate, authority and baseline (Phase 1), 2026-10-04

- Gate pass 6 returned `plan-quality-gate: PASS_WITH_FINDINGS`. Two findings are recorded for resolution when Phase 4
  writes the Gherkin, and neither is edited now: **Medium**, AC-BI-17 says the all-present run "prints each date as
  present", which contradicts the all-present summary wording `Backup files: all N retained backups are present` in the
  PRD AC-BI-17 and the Phase 5 RED; **Low**, the PRD has no reconciliation note.
- Authority relayed to the executor on 2026-10-04 from the owner's 2026-10-03 and 2026-10-04 session: execution
  authorized; OD-1 read-only production reads approved; R1 to R4 approved; OD-2 Dropbox web access not available.
  Agent proposals D2 to D11 are not owner-confirmed and are not treated as owner decisions.
- Execution checkout: a clean worktree on its own branch at the planning commit, equal to `origin/main` after a fetch
  (`merge-base --is-ancestor` succeeded).
- Active backend: the green slot on loopback port 4001, the Caddy proxy on loopback port 4100; the blue port 4000 is
  idle. Readiness: loopback 4001 HTTP 200, loopback 4100 HTTP 200, routed origin HTTP 200 on five consecutive samples
  (0.02 to 0.04 s each); the readiness body reports `ready`, the green slot, a scheduler ready, SQLite ready and the
  release revision `e92f1ec2c82e9ee42fa535cd5ac2a1c1a2592b3e`. This is the baseline Phase 12 compares against.
- Timing: the latest slot, 2026-10-03T19:00Z, is `verified` (finished 19:00:39Z). Pre-state started 07:28Z, the
  post-state ended 07:37Z, so no 19:00Z slot lies between them. The authorization date 2026-10-04 is before the
  2026-10-06T19:00Z precondition; no `Late authorization` is recorded.

### V0.2 OD-2 (Phase 1)

`Unavailable (OD-2, 2026-10-03)`: the owner has no Dropbox web access, so the deleted-files list, the event history and
the list of devices linked to the backup folder cannot be read. Consequence: H2 can end only `unproven` unless a local
signal confirms it.

### V0.3 Pre-state (Phase 1), 2026-10-04T07:28Z

Captured to the ignored scratch area: the backup directory listing (27 entries: 12 test-fixture artifacts, 7 receipts,
7 production artifacts, the ownership marker), extended attributes of the directory and each entry, the marker hash, the
private configuration directory listing (3 entries: the backup configuration file, the storage pointer file and a
storage lock directory) with the two configuration files' hashes, and the ledger summary from a stable scratch copy of
the database and its `-wal` sidecar (53 runs, 39 verified, latest `finished_at` 2026-10-03T19:00:39Z; 38 rows for the
backup schedule). The production database was only copied, never opened by SQLite. The copy pair was accepted as
`stable` on the first attempt.

### V0.4 Ledger against disk (Phase 2: H5 and H4 data), 2026-10-04

Per slot, ledger state against the files on disk; the backup schedule has 36 scheduled and 2 setup runs, all verified.

| Slot (UTC)          | Ledger   | Artifact on disk | Receipt on disk | Bytes and digest equal ledger |
| ------------------- | -------- | ---------------- | --------------- | ----------------------------- |
| 2026-09-18 to 09-24 | verified | no               | no              | not applicable                |
| 2026-09-25 to 09-29 | verified | yes              | yes             | yes                           |
| **2026-09-30**      | verified | **no**           | **no**          | not applicable                |
| **2026-10-01**      | verified | **no**           | **no**          | not applicable                |
| 2026-10-02, 10-03   | verified | yes              | yes             | yes                           |

The seven slots 2026-09-18 to 09-24 are older than the seven retained dates, so their absence is retention (all seven
absent as the oldest dates). The seven surviving receipts all name the same destination as the present marker (equality
only, read R2); every surviving receipt carries the production schedule key and a `scheduled` claim whose slot equals
its ledger row. The twelve fixtures are artifacts with no receipt. The ledger records no destination, so a lost run is not
attributed to a destination by this comparison. The surviving seven pairs are exactly seven WIB dates, which is
consistent with retention having seen only seven owned dates (see V0.8).

### V0.5 H5 (Phase 2), 2026-10-04

Compared the two lost rows to their intact neighbours (2026-09-25 to 09-29 and 2026-10-02, 10-03):

- slot versus `finished_at`: indistinguishable (offsets of 5 to 57 seconds; the lost rows are 40 s and 6 s);
- attempt count: indistinguishable (1 each); occurrence numbers are contiguous across the lost rows;
- name timestamp versus slot: indistinguishable (the artifact name's UTC time equals `finished_at` for all 16 rows);
- byte size: indistinguishable, and **not unique**: 684032 bytes is also the size of the intact 2026-09-29, 10-02 and
  10-03 runs (the plan's note that both lost rows are exactly 684032 bytes is true but does not set them apart);
- digests: all 16 verified rows since 2026-09-18 carry 16 distinct digests and 16 distinct basenames.

H5 observation: the rows are indistinguishable from intact neighbours in every compared field, so H5 is eliminated by
the plan's rule. The other schedule in the ledger (the push-retention schedule) has 14 failed and 1 verified runs and
is unrelated to the backup schedule.

### V0.6 H4 (Phase 2), 2026-10-04

- Host search for the two lost artifact names (read R3): not found in the user Trash, the Dropbox cache folder, the
  Dropbox folder, the home directory (whole, one filesystem), the temporary directories, mounted volumes (one) and the
  shared and library folders. A positive control (a surviving name) was found. The Dropbox cache stores obfuscated
  names, so it was also searched by content: no file of 100 KB or more in it (47 files) matches either lost digest. A
  size-and-digest search over the home and temporary directories (3 files of the lost size, all intact survivors) found
  no copy under another name.
- Saved destination override: the backup configuration file's modification time is 2026-08-30, and the marker's is
  2026-08-30, both earlier than the first lost slot. No log line about a destination change exists (see V0.9).
- Surviving receipts all match the present marker's destination, which does not eliminate H4 for the lost runs (the
  ledger has no destination column).

H4 observation: no copy found anywhere on the host, no override after 2026-08-30. H4 is eliminated by the plan's rule
("a copy search and the logs find no copy and no override across the two slots"), with the stated limit that the logs
carry no dates (V0.9).

### V0.7 H3 (Phase 2), 2026-10-04

- The twelve fixtures were all born on WIB 2026-09-18 (UTC 13:46 to 15:29) and none on the lost WIB dates (2026-10-01
  and 2026-10-02) or after. Repository writers of `bnest-prod-` names: one in `lib` (the scheduled backup artifact
  name); the others are unit and integration test helpers and tests.
- The ledger holds no non-production backup schedule key.
- Commits touching Backup, the Scheduler and the test configuration, per WIB date from 2026-09-18: 09-19: 5, 09-22: 1,
  10-01: 4, 10-02: 12, none on the other dates. Test-guard landings by author date: `c6f654ec8` 2026-10-02 07:18 WIB and
  `ca0e437e9` 2026-10-02 09:12 WIB (committer dates 07:42 and 09:25).

| WIB date   | Fixture births | Commits to the three areas | Guard landing | Lost night |
| ---------- | -------------- | -------------------------- | ------------- | ---------- |
| 2026-09-18 | 12             | 0                          | no            | no         |
| 2026-09-19 | 0              | 5                          | no            | no         |
| 2026-09-22 | 0              | 1                          | no            | no         |
| 2026-10-01 | 0              | 4                          | no            | slot 09-30 |
| 2026-10-02 | 0              | 12                         | both          | slot 10-01 |

H3 observation: the ledger has no foreign schedule key and no fixture is dated on a lost night, but a window of Backup,
Scheduler and test-configuration commits (hexagonal refactor, pre-guard) covers WIB 2026-10-01 evening to 2026-10-02
09:12, which overlaps the loss window V0.8 derives. This is temporal fit, not proof: H3 is **not eliminated**, and
nothing recovered shows a test pair.

### V0.8 H1 and H3a replay (Phase 2), 2026-10-04

The real `Retention.retained_run_ids/1` was replayed in scratch over receipt histories rebuilt from the ledger (36
scheduled verified runs, synthetic receipts only, each slot adding its receipt and then removing every pair not kept):

| Reconstruction                                                     | Lost nights removed? | Final survivors                   |
| ------------------------------------------------------------------ | -------------------- | --------------------------------- |
| (a) production runs alone                                          | no                   | 2026-09-27 to 10-03 (7 dates)     |
| (b) plus a synthetic newer same-WIB-date receipt on each lost date | yes                  | 09-27, 09-28, 09-29, 10-02, 10-03 |
| (c) plus twelve synthetic fixture receipts dated 2026-09-18        | no                   | 2026-09-27 to 10-03 (7 dates)     |

Reconstruction (a) keeps the lost nights, as expected, so production retention alone does not remove them (H1 alone is
eliminated). Reconstruction (b) removes exactly the two nights but also prunes 09-25 and 09-26, which the disk still
holds, so it does not reproduce the disk. One more probe (not in the plan, labelled): removing both production pairs
outside retention at a chosen instant reproduces the disk exactly (09-25 to 09-29, 10-02, 10-03) only when the removal
falls **after the retention of the 2026-10-01T19:00Z slot and before the retention of the 2026-10-02T19:00Z slot**,
that is between WIB 2026-10-02 02:00 and 2026-10-03 02:00. Removal after the lost slot's own retention, or after the
2026-10-02 retention, does not.

### V0.9 Service and slot logs (Phase 2), 2026-10-04

The blue and green service logs carry a time of day without a date, and the release logs and metrics concern releases.
They contain no line naming a backup, retention, a destination or a verified run, so for both lost slots: `No log
retained` (event sequence unavailable). The logs also record scheduler SQLite connection timeouts on the green service
(5 occurrences, undated, at times of day 08:55 to 12:33); no relation to a lost slot can be shown and none is claimed.
Destination override seen: no (nothing logged; the configuration file is unchanged since 2026-08-30).

### V0.10 H2 local signals (Phase 2), 2026-10-04

Extended attributes: every entry in the backup directory (the directory, the fixtures, the surviving pairs and the
marker) carries the same two attributes, `com.dropbox.attrs` and `com.apple.provenance`, uniformly: no entry differs.
Conflicted-copy files: none in the backup directory or anywhere in the repository's Dropbox folder (the machine does
hold 176 conflicted copies in one unrelated top-level Dropbox folder, which shows conflicts occur on this machine but is
no signal for this folder). Placeholder, partial or temporary files in the backup directory: not found. Local Dropbox cache: no copy of
either lost artifact (V0.6). No local H2 signal.

### V0.11 H2 disposition (OD-2), 2026-10-04

H2 is `unproven`: no local signal confirmed it, and it cannot be eliminated without the Dropbox event history. The
observation that would settle it: the Dropbox event history of the backup folder between 2026-10-02 02:00 WIB and
2026-10-03 02:00 WIB (the loss window of V0.8), or the deleted-files list for the two lost artifacts. Unavailable under
OD-2.

### V0.12 AC-BI-01 comparison (Phase 2), 2026-10-04

Pre-state 07:28Z and post-state 07:37Z, with no scheduled slot between. Equal: the backup directory listing (names,
sizes, modification and birth times), extended attributes, the marker hash, the configuration directory listing and the
two configuration files' hashes, the ledger summary and the 38 backup-schedule rows. **One difference, not covered by
the comparison rule's exclusions:** the modification time of the storage lock directory in the private configuration
directory advances about every 30 seconds while the service runs (observed advancing between two reads 20 seconds
apart with only `stat` running; it differed again between the pre-state and the post-state). It is the running
service's own heartbeat on its lock, not a write by this execution. The comparison rule says to exclude only
slot-created or slot-removed entries, so this is recorded as a deviation and as a defect of the rule: no entry other
than that lock directory, whose mtime is service-owned, changed. Recommended rule amendment: exclude the storage lock
directory's mtime.

### V0.13 AC-BI-01 comparison rule amended (owner decision), 2026-10-04

The owner decided on 2026-10-04 to amend AC-BI-01's comparison rule so that it also excludes the modification time of the
`storage.json.lock` directory under the private configuration directory, which the running service rewrites about every
30 seconds (V0.12). The amendment is recorded in the PRD under AC-BI-01 and applies to the Phase 5 early live reconcile
and the Phase 13 re-run as well as to Phase 2. The deviation recorded in V0.12 is therefore covered by the amended rule;
nothing else was excluded on this ground.

### Phase 2 observation table (H1 to H5), dates and counts only

| Hypothesis | Disposition                             | Observation                                                                                                                                              |
| ---------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H1         | eliminated for production writers alone | Replay (a) keeps both nights; retention alone cannot remove them. Interacts with H3 (b).                                                                 |
| H2         | unproven                                | No local signal (V0.10); settling observation unavailable under OD-2 (V0.11).                                                                            |
| H3         | not eliminated                          | Loss window 2026-10-02 02:00 to 2026-10-03 02:00 WIB overlaps pre-guard refactor commits; no fixture on a lost night; no direct evidence of a test pair. |
| H4         | eliminated                              | No copy on the host or in the Dropbox cache; no destination override after 2026-08-30; surviving receipts match the marker.                              |
| H5         | eliminated                              | The lost rows are indistinguishable from intact neighbours in every compared field.                                                                      |

## V1 Cause verdict (Phase 3), 2026-10-04

**AI-recorded; owner-confirmed 2026-10-04** (the owner confirmed V1 as `C-UNPROVEN` at the start of Phase 6: cause not
proven, `C-DROPBOX` and `C-TEST` stay open and honestly recorded). The observations and dispositions below are the AI's;
the confirmation is the owner's and covers V1 only, not D2 to D11.

**Verdict: `C-UNPROVEN`, with two candidates open and none confirmed.** The open candidates are `C-DROPBOX` (H2) and
`C-TEST` (H3). The verdict is not a union, because no cause is confirmed. It is not `C-RET` (H1 is eliminated for
production writers alone), not `C-DEST` (H4 eliminated) and not `C-LEDGER` (H5 eliminated).

| Hypothesis | Disposition                   | Observation that confirmed or eliminated it, or that would settle it                                                                                                                                                                                                                                                                        |
| ---------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H1         | eliminated (production alone) | V0.8 replay (a): the real retention function keeps both nights over receipt histories rebuilt from the ledger. Only a newer same-WIB-date receipt that production did not write (reconstruction (b)) removes them, and that reconstruction also prunes two dates the disk still holds, so it does not reproduce the disk.                   |
| H2         | unproven                      | No local signal (V0.10). Would be settled by the Dropbox event history, or the deleted-files list, of the backup folder between 2026-10-02 02:00 WIB and 2026-10-03 02:00 WIB. Unavailable under OD-2.                                                                                                                                      |
| H3         | not eliminated                | Temporal overlap only (V0.7, V0.8): no fixture is dated on a lost night, the ledger holds no foreign schedule key, and no direct trace of a test pair exists. Would be settled by a retained record of a pre-guard test run in the loss window that resolved the real backup destination; none is retained (V0.9: the logs carry no dates). |
| H3a        | not reproduced                | V0.8 (b): supersession by a synthetic newer same-date receipt removes the two nights but also two dates that survive, so the mechanism as formulated does not explain the disk.                                                                                                                                                             |
| H4         | eliminated                    | V0.6: no copy of either name or digest anywhere on the host, no destination override after 2026-08-30.                                                                                                                                                                                                                                      |
| H5         | eliminated                    | V0.5: the lost rows are indistinguishable from intact neighbours in every compared field.                                                                                                                                                                                                                                                   |

**What the Phase 2 narrowing does and does not show.** Under a single-instant removal assumption, the only removal time
that reproduces the disk lies between the retention of the 2026-10-01T19:00Z slot and that of the 2026-10-02T19:00Z
slot, that is WIB 2026-10-02 02:00 to 2026-10-03 02:00, a window of 24 hours (V0.8). The two test-guard commits landed at
07:18 and 09:12 WIB on 2026-10-02 by author date (V0.7), so the pre-guard part of that window is its first 7 hours 12
minutes and the post-guard part is the remaining 16 hours 48 minutes. Commits show when code changed, not when a test
ran, and no test-run record is retained. The overlap with pre-guard refactor activity therefore keeps H3 open and does
not make it likely: a Dropbox deletion, move or conflict at any time in the same 24 hours fits the disk equally well,
and nothing observed separates the two. The replay also does not support the supersession form of H3 (H3a): a test that
removed exactly the two production pairs would need a path other than supersession, and Phase 2 did not identify a code
path that does that. The window assumes both pairs left the disk at one instant; removals at two instants would widen
it.

**Minimal reproduction for Phase 6.** None is recorded, because H1, H3a and H5 are not confirmed as the cause (AC-BI-10
has no verdict-named reproduction to test). AC-BI-08 and AC-BI-09 apply as defence in depth only, because H3 stays open
(branch table, `C-UNPROVEN` row; decision G7).

**What would change this verdict.** The Dropbox event history for the loss window (settles H2), or a retained record of a
test run in that window that resolved the real destination (settles H3). If a repository-side defect is later proved,
the verdict becomes the union with that cause and the matching Phase 6 items are triggered by their own RED.

## V2 Early live reconcile (Phase 5), 2026-10-04T09:21Z

`mix bnest.backup.reconcile`, run read-only from the execution worktree against production (scratch copies of the
database and its `-wal`; no application start, no Scheduler), exited 1 and reported `2 of 7 retained backups need
attention` with `2026-10-01: file missing` and `2026-10-02: file missing`: the WIB dates of the 2026-09-30T19:00Z and
2026-10-01T19:00Z slots. The other 5 retained verified runs were present. Pre-state (09:21:25Z) and post-state: equal
under the amended comparison rule (V0.13); the one difference was the storage lock directory's modification time. A
`-shm` file sits beside the production database because the running service holds it open; the task created none.

## V3 Phase 6 results and routed owner-side actions, 2026-10-04

- The AC-BI-08 and AC-BI-09 characterization pins pass on unmodified code and fail under their predeclared mutations
  (evidence in the Phase 6 items of `delivery.md`). Neither found a repository-side defect, which agrees with V1.
- **Owner-side actions routed here (resolution is the owner's):** the Dropbox event history or deleted-files list of the
  backup folder for WIB 2026-10-02 02:00 to 2026-10-03 02:00 (settles H2); whether any other device or client was
  syncing that folder in the window; and the OD-4 idea brief, which exists and commits to nothing.
- **Finding on the AC-BI-09 wording (no scope widened).** The pins prove that the test environment's _default_
  destination is inside the per-run test root and that resolving it fails closed. They do not prove that an
  _explicit override_ naming the checkout's `data/backup` is refused: placement is judged against the configured
  repository root (`Location.repository_placement/2`), which in the test environment is the isolated root, so such an
  override is not refused by that check. A test that saves that path would be doing so deliberately, and the production
  protection for the default path rests on the per-run `BNEST_BACKUP_CONFIG` and the isolated root the pins now hold.
  No code was changed; if the owner wants explicit overrides naming the checkout refused in tests, that is a new item.
- The mutated AC-BI-09 `INTEGRATION` run created a synthetic test backup under the worktree's ignored `data/backup`
  (never the production directory); it was deleted afterwards.

## Phase 3 to 5 deviations and agent proposals

- AC-BI-11 and AC-BI-18 Rules and bindings move to Phase 7 (their task is built there; Phase 5 needs a green suite). The
  Phase 5 item that lists AC-BI-18 cannot be satisfied in Phase 5 for that reason.
- The copy effects of the reconcile task sit in a Storage facade function and adapter (architecture scan), and
  destination resolution is a new read-only `Backup.read_destination/0` because `Backup.destination/0` creates, marks
  and chmods the directory.
- One multi-line log entry per run, and `classify/2` instead of `classify/3`.
- Singular wording forms (`the retained backup is present`, `1 of N retained backups needs attention`) are agent
  proposals for the Phase 8 copy review.
- The README of `apps/bnest-app` (tasks line, Backup context, Storage description) is a Phase 11 item.

## V4 Phase 8 and 9 results and deviations, 2026-10-04

- Owner design review (Phase 8): the owner approved the alternative `row` and the draft copy including the singular forms in
  the executing session on 2026-10-04 and requested no change. Only D7 and that copy are settled; D2 to D6 and D8 to D11
  stay agent proposals. The wording function's output equals the draft strings, so no asset text changed.
- Date convention: the label shows the WIB date of a run's `finished_at` and adds no suffix; the page already labels its own
  times in WIB. This is an agent decision for the owner to confirm or turn into an explicit suffix (a change of the
  wording function and of every surface).
- The PRD text of AC-BI-23 had a scenario outline without a `When` step and the execution gates reject that; the outline
  now opens the page at each viewport as its `When`. An exemption comment may not use the word `slow`.
- `BEHAVIOUR` is a static binding check (it passes once every step is bound and never runs a scenario), so the red of a
  new UI scenario comes from `BE_UNIT`, `INTEGRATION` and `FE_E2E_CASE`.
- A pre-existing defect was found by the new browser scenario and fixed: every successful save on the Schedules page
  dropped keyboard focus to the document body, because the unkeyed status paragraph made LiveView recreate both forms.
  The feedback paragraphs now sit in one stable container.
- Observation for the owner: the page's existing `refresh/0` calls `Backup.destination/0` on every render, and that call
  creates, marks and sets the mode of the destination folder (the label's own check uses the read-only
  `Backup.read_destination/0`). The AC-BI-22 never-writes scenarios pass because the folder is already prepared by then,
  so a first render over a never-prepared destination is the one place a render can still write. Not changed here.
- The LiveView, the Mix task and the post-run reconciliation each hold the same short verified-runs-then-reconcile
  composition (candidate follow-up, not extracted).
- The fixture schedule used by the shared test seeds has the same handler as the production backup, so an isolated page
  shows two `Backup files` items; production has one such row.
- The state words of a problem line (`file missing`, `file changed`) are not bold as the hi-fi draws them, and the marker sits
  about 10px further from the strip than the hi-fi draws it; both follow from using the one wording string and the
  stated padding. Owner call.

## Phase 10 rendered verification, 2026-10-04

Isolated origin `http://localhost:4660` (host `localhost`, port 4660), started from the execution checkout in its own tmux
window with an isolated runtime root, storage pointer, backup configuration and SQLite database, and two synthetic
`test-user-` accounts (an administrator and a non-administrator). The production service, its ports and its data were not
touched (ports before and after compared; production listeners unchanged). States were seeded through the shared test
seeds: all present (7 dates), one missing, two problems (a missing and a changed date), exactly one retained date present,
exactly one retained date missing, none verified, could not be checked (the newest artifact made unreadable), and checking
(the server's disconnected first render).

### Accessibility audit

| Route                     | State                                      | Viewport class                  | Result                                                                                                                                                                                                                           |
| ------------------------- | ------------------------------------------ | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| /admin/settings/schedules | needs attention (two problems)             | desktop, mobile (Lighthouse)    | pass: accessibility 100, best practices 100, 31 audits passed, 0 failed                                                                                                                                                          |
| /admin/settings/schedules | all states                                 | desktop, tablet, mobile, 320 px | pass: the item is a `dt` and `dd` pair in the existing list; the `dd` is the only live region, polite, named by its term; no `role=alert` for the label; no focusable control or tab stop inside it; the marker is `aria-hidden` |
| /admin/settings/schedules | all states                                 | all                             | pass: every state has words and a marker shape as well as a strip colour (non-colour cue)                                                                                                                                        |
| /admin/settings/schedules | all states                                 | all                             | pass: contrast measured in the rendered page: text on paper 10.99:1; strip 3.24:1 (coral), 3.26:1 (green), 7.28:1 (neutral), each at least the 3:1 a non-text cue needs                                                          |
| /admin/settings/schedules | needs attention                            | 320 px, 393 px                  | pass: no horizontal scroll at 320 and 393; problem lines wrap and are never truncated (a date line wraps onto two lines at 320)                                                                                                  |
| /admin/settings/schedules | needs attention                            | mobile at 200 percent text      | label passes (nothing cut off); the page overflows horizontally because of the Backup folder form's path field, which pre-exists and is not the label                                                                            |
| /admin/settings/schedules | dark theme, forced colours, reduced motion | mobile                          | pass: the cards keep the cream surface in the dark theme so the contrast above holds; the strip stays a 6px solid border in forced colours; nothing animates                                                                     |

### Hand-walk matrix (route, state, viewport class, pass or fail)

| Route                     | State                          | Desktop 1440 | Tablet 768 | Mobile 393 | 320 px floor |
| ------------------------- | ------------------------------ | ------------ | ---------- | ---------- | ------------ |
| /admin/settings/schedules | checking (disconnected render) | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | all present                    | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | needs attention, two problems  | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | needs attention, singular      | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | all present, singular          | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | could not be checked           | pass         | pass       | pass       | pass         |
| /admin/settings/schedules | nothing to check yet           | pass         | pass       | pass       | pass         |

Placement: beside `Last result` in the second column at 1440 (828px wide, three columns) and at 768 (second column); stacked
under `Last result` at 393 and 320. Changed interaction, at all four widths: a reload shows checking and then the result;
saving the daily schedule and saving the unchanged backup folder each turn the label to checking and back to the result
with focus returning to the pressed button; a failed save (a relative folder) shows the existing alert, leaves the label
unchanged and starts no check; two quick saves leave one final result; the keyboard path (theme buttons, breadcrumb,
the row title link, the enabled box, the time field, Save schedule, the folder field, Save and create first backup) has no
extra stop for the label and both forms stay usable. The destination-mismatch state is Not applicable (C-DEST not
selected) and was not rendered on the page.

## Exploratory findings

Spec-aware pass, Playwright against the isolated origin, three viewport classes and 320 px, synthetic identities only,
nothing shared or production touched. Compared with the Gherkin of `scheduled_backups.feature` and probed beyond it.

| ID  | Route and state                                                      | Category                 | Finding                                                                                                                                                                                                                                                                     | Disposition                                                                                                                 |
| --- | -------------------------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| E1  | /admin/settings/schedules, all states                                | Spec conformance         | The label states, order, singular forms, polite region, no control, no private value and the re-check after both saves all behave as the scenarios say; the label text carries no path, digest, destination identifier or run ID (scan of its markup and attributes: none). | None needed                                                                                                                 |
| E2  | /admin/settings/schedules, needs attention                           | Visual fidelity          | The state words of a problem line are not bold and the marker is about 10px further from the strip than the hi-fi draws it.                                                                                                                                                 | Accepted, non-blocking: bolding needs a split of the one wording string; reason recorded in V4; owner call                  |
| E3  | /admin/settings/schedules, any state, mobile at 200 percent text     | Responsive               | The page scrolls horizontally because the Backup folder form's field overflows; the label does not.                                                                                                                                                                         | Accepted, non-blocking: pre-existing form outside this plan's scope (changes to the page beyond the label are out of scope) |
| E4  | any state                                                            | Console                  | One console warning on every load: the deprecated `apple-mobile-web-app-capable` meta tag. No error.                                                                                                                                                                        | Accepted, non-blocking: pre-existing, not the label                                                                         |
| E5  | route variants                                                       | Route structure          | `/admin/settings/schedules/` and `?x=1` render the page; a path traversal and `/integrity` return not found; an unauthenticated visitor and the non-administrator get not found.                                                                                            | None needed                                                                                                                 |
| E6  | /admin/settings/schedules                                            | Passive security         | The Backup folder field shows the full path of the resolved backup folder to the administrator (pre-existing by design, administrator only); the label never shows a path.                                                                                                  | Accepted, non-blocking: outside the label's contract                                                                        |
| E7  | /admin/settings/schedules, first render over a never-prepared folder | Write on render          | The page's existing refresh calls the folder-preparing `Backup.destination/0`, so a render can create or re-mark the folder before the label's read-only check runs; the integration scenarios pass because the folder is already prepared.                                 | Accepted, non-blocking here, reported to the owner as an observation (see V4)                                               |
| E8  | /admin/settings/schedules, two backup rows                           | Test artifact            | The fixture schedule used by the test seeds has the production handler, so an isolated page shows two `Backup files` items; production has one.                                                                                                                             | Accepted: test seed, not a product defect                                                                                   |
| E9  | /admin/settings/schedules, focus after a save                        | Regression found earlier | Focus was lost on every successful save before the stable feedback container (fixed in Phase 9); verified fixed here at all four widths.                                                                                                                                    | Fixed                                                                                                                       |

## Usability findings

Spec-blind pass, run after the exploratory pass was recorded. Structural blindness: a fresh `swe-usability-tester`
context was given only the isolated origin, the route, the viewport classes, synthetic administrator credentials, six
neutrally lettered situations and seven frozen tasks; the specs, the source, the design assets and the plan were withheld
and it reported reading none (it read its own agent definition, its usability skill and a public probes document). It
visited all six situations at 1440, 768, 393 and 320 px, saved the schedule and the folder, walked the page by keyboard,
checked dark theme and a simulated offline save. Findings about the new line are NEW, findings about the rest of the page
are PRE.

| ID           | Situation                                          | Heuristic  | Severity          | Finding                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Disposition                                                                                                                                                                                                 |
| ------------ | -------------------------------------------------- | ---------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N-01         | could not be checked                               | H2, H9     | Major             | The remedy `Run mix bnest.backup.reconcile on the host.` means nothing to a household administrator and gives no reason or word on whether the backups are safe.                                                                                                                                                                                                                                                                                                    | Accepted, non-blocking, owner decision: the copy is the owner-approved wording of 2026-10-04 and the one wording function serves four surfaces; changing it is a copy change for the owner (see the report) |
| N-02         | needs attention                                    | H9         | Major             | `file changed` is not explained, and the only action, `Save and create first backup`, is far below.                                                                                                                                                                                                                                                                                                                                                                 | Accepted, owner decision: same wording constraint; the lines are the approved `date: file missing or changed` form                                                                                          |
| N-03         | nothing to check yet                               | H1, H6     | Major             | The neutral calm style and `no verified backup to check yet` can reassure or confuse.                                                                                                                                                                                                                                                                                                                                                                               | Accepted, owner decision: the nothing-to-check state is a designed neutral state by decision D10 and the PRD (AC-BI-17, AC-BI-21); the owner may ask for an attention style                                 |
| N-04         | needs attention, could not be checked, all present | H1, H4     | Major             | The line can disagree with `Last result` on the same card (`Verified` beside `2 of 7 ... need attention`).                                                                                                                                                                                                                                                                                                                                                          | Accepted: they answer different questions (last run result versus files on disk now); that is the purpose of the label                                                                                      |
| N-05         | after Save and create first backup                 | H1         | Major             | There is no checked-at time and the line does not refresh when the queued first verification finishes; it stayed at its first result until a reload.                                                                                                                                                                                                                                                                                                                | Accepted, owner decision: this is the recorded D8 residual (whether to hold the label at checking until the verification finishes); no live refresh was specified                                           |
| N-06         | all present                                        | H2         | Minor             | `present` does not say intact.                                                                                                                                                                                                                                                                                                                                                                                                                                      | Accepted: a changed file is reported separately as `file changed`, so `present` means present and unchanged by the check                                                                                    |
| N-07         | all                                                | H8         | Minor             | The line appears under two cards.                                                                                                                                                                                                                                                                                                                                                                                                                                   | Not a product defect: the isolated page has a fixture schedule with the production handler (see E8); production has one such row. Root cause shared with P-03                                               |
| N-08         | needs attention                                    | H2         | Minor             | The dates carry no time zone.                                                                                                                                                                                                                                                                                                                                                                                                                                       | Accepted: the dates are WIB dates per the Phase 8 date convention, an agent decision awaiting the owner; the fixture dates in 2030 are synthetic                                                            |
| N-09         | singular                                           | H4         | Cosmetic          | Lower-case sentence fragments and a singular beside the seven-day policy.                                                                                                                                                                                                                                                                                                                                                                                           | Accepted: the approved copy                                                                                                                                                                                 |
| N-10, N-11   | all, narrow                                        | WCAG 1.4.1 | Pass              | Every state has an icon and words; the long command token wraps.                                                                                                                                                                                                                                                                                                                                                                                                    | None                                                                                                                                                                                                        |
| P-01 to P-12 | rest of the page                                   | various    | Major to Cosmetic | Pre-existing page issues: the save confirmation at the top far from the button, raw ISO next-run times, two cards with the same title (a fixture artifact in the isolated page), jargon in the folder panel, a cut-off folder path on mobile, a first-backup button label, flat headings, title links to the page itself, the theme toggle overlapping the breadcrumb at 320 px, a dark theme that keeps cream cards, no offline feedback and inconsistent wording. | Accepted, non-blocking: the plan's scope is the label (changes to the page beyond it are out of scope); listed here for the owner                                                                           |

Tasks: 1 pass with caveats, 2 partial (the next step is missing), 3 fail on the developer command, 4 fail on the neutral
wording, 5 fail on the distant save confirmation (pre-existing), 6 pass with caveats, 7 pass (the theme toggle overlaps at
320 px). Not covered: more than two problem days, slow networks, locales and browsers other than Chromium.

### Cross-references

- E3 (exploratory: the page overflows at 200 percent text) and P-05 (usability: the folder path is cut off on mobile) are
  one root cause, the Backup folder form's long path field, which pre-exists and is outside the label.
- E8 (exploratory: two `Backup files` items) and N-07 and P-03 (usability: two cards with one title) are one root cause, the
  test fixture schedule that shares the production handler; the production page has one row.
- N-08 (usability: dates without a zone) and the Phase 8 date-convention decision are one open owner decision.
- N-05 (usability: no refresh after the queued first verification) is the recorded D8 residual.
- E7 (exploratory: the page's folder-preparing call on render) has no usability counterpart.

### Phase 10 confirmation (the five conditions)

1. Both passes ran: the exploratory pass first and recorded above, then the usability pass. 2. Findings are present in both
   sections. 3. The headings `## Exploratory findings` and `## Usability findings` are separate and labelled. 4. Cross-references
   are noted above. 5. No spec proposal was accepted, so no unreconciled proposal entered `specs/**`: the usability-sourced
   suggestions all change owner-approved copy or the layout of the pre-existing page and wait for the owner.

## Phase 11 Gherkin implementation review, 2026-10-04

A `swe-reviewer` context reviewed the backup-integrity scope (27 backend scenarios and 15 expanded frontend scenarios, by
the Unit, Integration and E2E adapters: 126 rows). First pass: 80 PASS, 30 EXEMPT, 16 FAIL. The FAILs were repaired
(`swe-developer`, each fix proved able to fail by a mutation that was reverted):

- The step `it starts no scheduler` compared Scheduler pids inside one VM and could not fail; it now runs the task under
  the BEAM call trace and passes only when the task read the ledger, called no start or claim entry point and left the
  ledger rows equal (`SchedulerWatch`, with its own unit test). Mutations: a claim call and an application start inside
  the task turned both target scenarios red in Unit and Integration.
- The Unit driver re-composed the reconcile task; it now calls the real `Mix.Tasks.Bnest.Backup.Reconcile.execute/1`.
  Mutations: an always-zero exit status and a narrowed rescue turned Unit red.
- Two E2E exemptions had invalid reasons (the browser harness already empties and reseeds the routed ledger and reads
  server state): `The page says plainly when there is nothing to check` and `Rendering the label never writes` were
  unexempted and bound in the browser, in three projects. Mutations: a wrong copy for an empty ledger and a file written
  into the destination during the check turned both red, which also exposed that the shared routed destination kept a
  mutation's file between projects, so the browser seed now empties the destination first (it refuses any directory that
  is not the run's isolated default).
- Advisory fixed: an arithmetic clause that held by construction was removed from the label oracle.

Left for the owner (not a FAIL): 18 backend exemptions (the reconcile task's wording and exit scenarios and the restore
drill scenarios) say they are `below every public application boundary`, but the operator command line is a public
process boundary and the backend E2E app already runs Mix tasks as subprocesses. Their integration alternatives are
strong, so the reviewer kept them EXEMPT; either bind them through a command-line E2E step or rewrite each reason to a real
boundary mismatch. Other advisories left: the Unit layer cannot prove the restore root is gone (the in-memory double
creates none; Integration does), the viewport examples are markup proxies below E2E, the backend E2E coverage file is
stale and read by no gate, and the Mix task bindings call `execute/1` while the start-up glue of `run/1` is proved only by
the subprocess test.
