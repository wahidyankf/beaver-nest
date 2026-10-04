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

**AI-recorded; pending owner confirmation** (the owner confirms V1 at the start of Phase 6, decision D11, an agent
proposal). Nothing below is an owner decision.

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
