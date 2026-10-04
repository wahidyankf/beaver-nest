# Backup Integrity

## Status

**In progress since 2026-10-04.** Gate pass 6 returned `PASS_WITH_FINDINGS` and execution was authorized. Phases 1
and 2 are complete (see [`delivery.md`](delivery.md) and [`learnings.md`](learnings.md) entries V0.1 to V0.12); Phases 3 to 5
(the AI-recorded cause verdict V1, the specifications and the reconciliation detector, with its early live run) are
complete; Phases 6 to 11 are executed (V1 confirmed as `C-UNPROVEN` on 2026-10-04; the label, its rendered inspection and the review passes are done); Phase 12 (release) has not started. The history paragraph below describes the plan as it stood in the backlog.

**Backlog. Drafted 2026-10-03, expanded the same day for the owner decisions OD-1 to OD-4, and repaired on 2026-10-04
after plan quality gate passes 4 and 5; not authorized for execution.** The six documents and the UI design assets are
complete. Both planning decision gates ran on the draft that preceded the expansion (their records are in
[`tech-docs.md`](tech-docs.md#decision-record-pre-write-gate)). Gate pass 4 on 2026-10-04 returned `BLOCKED` on one High
finding, F1: the UI design assets had been deferred to Phase 8. The owner resolved F1 by having them drawn in the plan
now, so the twelve assets, their [README](assets/README.md), the comparison and the selection are in this plan. A fourth
propagation also repaired F2 to F7 with agent proposals that the owner has not yet confirmed (the Phase 5 wording cases
and the empty-ledger exit, the owner's verdict confirmation moved to Phase 6, the label's re-check after a save and its
in-function time-box, the viewport set by the browser binding, and the limit of the production proof). Gate pass 5 on
2026-10-04 returned `PASS_WITH_FINDINGS` (M1 and M2 Medium, L1 to L5 Low), and a fifth propagation applied all seven
within the recorded decisions: the Shape Choice of `tech-docs.md` justified against the owner as a distinct reader, the
dated preconditions and the Phase 2 dispositions before Phase 1 (extending agent proposal D11), a note in the PRD that
D2 and D8 to D10 are pending, the wording of one BRD risk row, the backlog index summary, a Phase 4 Rule pinning the
state-to-wording mapping, and the label of the Phase 9 styling item. **No plan quality gate verdict is current for the
folder as it now stands:** the pass 5 verdict applies to the folder before the fifth propagation, and the gate re-run,
which [`delivery.md`](delivery.md) records as its first Phase 1 item, unticked, is outstanding. Execution needs its own
explicit direction; Phase 1 then moves the folder to `plans/in-progress/`. The production reads it needs are approved
(OD-1, and R1 to R4 on 2026-10-03); the items still awaiting the owner's confirmation are named under
[Owner Decisions](#owner-decisions).

## Outcome

When the Bnest ledger says a production backup is `verified`, a verified artifact and its receipt exist where the
ledger says they are, or Bnest says plainly that they do not. Today the ledger and the disk disagree and nothing
notices.

Concretely, the plan delivers, each conditional on what the investigation proves:

1. **The cause**, established by read-only evidence before any change. The Dropbox hypothesis (H2) can end only
   unproven, because the owner has no Dropbox web access.
2. **A detector** that reports a `verified` run whose artifact is absent, changed, or unreadable: a read-only `Backup`
   reconciliation surfaced through a Mix task, a log line, a telemetry event and a label on the Schedules & backups page.
3. **A regression test** that proves test receipts and artifacts can never influence production retention, if the
   cause or its neighbourhood makes that claim worth pinning.
4. **An owner-run restore drill**, so a backup is proven restorable by a person, not only by the proof the backup
   task runs on its own copy.
5. **An idea brief** for an off-Dropbox second copy, created once the verdict is known, with no commitment to build it.

## Context

The owner asked for this plan on 2026-10-03 ("Buka plan integritas backup"). It promotes item 4 of
[Bnest post-closure follow-ups](../../ideas/q2-not-urgent-important/bnest-post-closure-follow-ups.md), which the
archived `ddd-hexagonal-adoption` plan recorded as an investigation, not a finding.

Verified read-only on 2026-10-03:

- `bnest_schedule_runs` records the production backup runs for `scheduled_for` 2026-09-30T19:00Z and
  2026-10-01T19:00Z as `verified`, each with an artifact name and 684032 bytes.
- The backup directory (`data/backup`, synchronized by Dropbox) holds **no** artifact and **no** receipt for 20260930
  or 20261001. It holds twelve test-fixture artifacts named `bnest-prod-20260918T000000Z-*`, artifact and receipt pairs
  of roughly 660 to 684 KB (receipt 752 B) for 20260925, 26, 27, 28, 29 and 20261002, and the ownership marker.

So the database claims `verified` while the files are absent. **The cause is unproven.** Five hypotheses are on the
table, H1 to H5: retention, Dropbox, another writer or test pollution, a different destination, and a ledger row that
is not what it seems. H3a is a candidate mechanism inside H3. The plan starts by discriminating between them. The
Dropbox event history is not available to the owner (OD-2), so H2 can be confirmed only by a local signal and otherwise
stays unproven.

The backup task only records a run as `verified` after the artifact is promoted and its receipt is written. A missing
file therefore means something removed it, something wrote it elsewhere, or the ledger row is not what it seems.

## Scope Boundary

**Included.** Read-only investigation of the ledger, the backup directory, the repository, local Dropbox metadata and
the service logs (Dropbox's web history is unavailable, OD-2); a cause verdict; the detector (a read-only `Backup`
reconciliation, a Mix task, telemetry, and an administrator-facing label on the Schedules & backups page, designed first
under the [UI design convention](../../../repo-governance/conventions/plan-ui-design.md)); the cause-specific regression
test and fix; a restore-drill Mix task and how-to guide; one production release (the detector and the label always
change service code); the owner-run drill and the owner's own look at the label on the live origin; an idea brief for an
off-Dropbox second copy; specification, documentation and README propagation; and the exploratory and usability review
of the label.

**Excluded.** Any write to the production backup directory or to `~/.config/bnest/*` without the owner's recorded
approval; recovering the two missing artifacts (they are unrecoverable unless the investigation finds them); changing
Dropbox account settings; building an off-Dropbox second backup copy (an idea brief only, with no commitment); push or
email notification beyond the label; changing the retention policy of seven WIB dates.

## Approach

Investigate first, change second. [Phase 2](delivery.md) gathers evidence that separates the hypotheses without
touching production; [Phase 3](delivery.md) turns it into one recorded verdict that selects which later phases apply.
The detector is independent of the cause and is delivered in every branch, because no cause makes "the ledger says
verified and nobody checked" acceptable. The cause-specific fix is delivered only for the branch the evidence selects.
Code follows Gherkin, bindings and an Nx red, as the project rule requires.

**Schedule pressure.** The two lost nights stop being reportable by the live detector once the run of WIB 2026-10-08
finishes retention. Phases 1 to 5 therefore run first, and the early live reconcile in Phase 5 does not wait on the UI.
The label (OD-3) has its design assets in this plan; Phase 8 reconciles their copy and records the owner's design review,
Phase 9 specifies and builds it, and Phase 10 inspects it, all after Phase 7. As an agent proposal pending owner
confirmation (D5), it is released with the detector in one release (Phase 12). Also as an agent proposal pending owner
confirmation (D11), the owner's confirmation of the cause verdict is needed before Phase 6 and the release, not before
Phases 4 and 5, and [`delivery.md`](delivery.md#dated-preconditions) states the dated preconditions before Phase 1 and
Phase 5 the dispositions recorded for the window.

## Dependencies and Authority

- Authoritative SQLite, loopback Caddy and Tailscale HTTPS are unchanged.
- No dependency is added.
- On 2026-10-03 the owner approved the read-only production reads (OD-1) and the four reads its enumeration does not
  name (R1 to R4), recorded that Dropbox web access is not available (OD-2), selected the admin-page label (OD-3) and
  approved an idea brief for an off-Dropbox second copy (OD-4). The owner remains the authority for execution, the
  verdict confirmation, the design review, the restore drill, the owner's look at the label on the live origin, and any
  write to the production backup directory or `~/.config/bnest/*`.
- Governing standards: [plan lifecycle](../../../repo-governance/conventions/plan-lifecycle.md),
  [live-service continuity](../../../repo-governance/development/live-service-continuity.md),
  [test identities](../../../repo-governance/development/test-identities.md),
  [runtime flat-file data](../../../repo-governance/conventions/runtime-flat-file-data.md),
  [plan UI design](../../../repo-governance/conventions/plan-ui-design.md).

## Owner Decisions

The decisions the owner actually made are exactly these. OD-1 to OD-4 were decided on 2026-10-03; the records are in
[`tech-docs.md`](tech-docs.md#owner-decisions-of-2026-10-03):

- **OD-1.** Approved: the read-only production reads of Phase 2 and the two read-only reconcile runs.
- **OD-2.** Dropbox web access is not available; H2 can only be recorded as unproven.
- **OD-3.** The alert surface adds an admin-page label beside the Mix task, the log and telemetry.
- **OD-4.** Yes: record an idea brief for an off-Dropbox second copy once the cause is known.

The other owner-made decisions are **R1 to R4**, the reads that OD-1 does not name, approved with "Setujui keempatnya"
in the 2026-10-03 session ([`tech-docs.md`](tech-docs.md#confirmed-by-the-owner)); **D1**, dropping the ledger
destination comparison (2026-10-03); and the resolution of **F1** by drawing the UI design assets in the plan now
(2026-10-04), which D6 carries out.

Everything else is an agent proposal pending owner confirmation, and nothing in it is confirmed
([`tech-docs.md`](tech-docs.md#pending-owner-confirmation)): D2 and D3; the gate resolutions G1 to G12 and P1 to P6,
including the residual effect that a candidate backend may win a nightly slot, the reason the restore drill is `[HUMAN]`
and the C-LEDGER path; D4 (the source of the label's data); D5 (the label shares one release with the detector); D6
beyond the F1 resolution (Phase 8 reduced to copy reconciliation and the design review); D7 (the selected alternative
`row`, approved by the owner at the Phase 8 design review on 2026-10-04); D8 (the label re-checks after a save) and its residual (what
the re-check reports right after a destination change); D9 (the browser binding sets the viewport per Examples row); D10
(the reconcile task exits non-zero on an empty ledger); and D11 (Phases 4 and 5 start on the AI-recorded verdict, the
owner's confirmation falls before Phase 6 and the release, the fallback decision point is 2026-10-07T12:00Z, and the
dated preconditions are authorization by 2026-10-06T19:00Z and Phase 2 finished by 2026-10-07T12:00Z). The
plan also proposes that authorizing execution confirms these unless the owner changes one.

## UI Design Preview

The selected alternative `row`, hi-fi on desktop, with synthetic content: a `Backup files` item beside `Last result:
Verified` states that 2 of 7 retained backups need attention and names the two dates. The full comparison of the three
alternatives, the other eleven assets and the rationale are in the
[UI Design section](tech-docs.md#selected-alternative-comparison-and-assets) of `tech-docs.md`.

![Hi-fi mockup of the selected row alternative on desktop: the Production database backup schedule row carries a Backup files item with a coral left strip, a warning triangle, the words 2 of 7 retained backups need attention and two problem lines, beside Last result: Verified](assets/ui-row-hifi-desktop.svg)

## Plan Map

- [`brd.md`](brd.md) why this is worth doing.
- [`prd.md`](prd.md) personas, stories and acceptance criteria.
- [`tech-docs.md`](tech-docs.md) hypotheses, discriminating checks, design, UI design, decisions and file impact.
- [`delivery.md`](delivery.md) the ordered checklist.
- [`learnings.md`](learnings.md) the transient discovery log (decision records live in `tech-docs.md`).
- [`assets/`](assets/README.md) holds the twelve UI design assets and their `README.md`; the preview above is one of them.

## Directory Map

- [`README.md`](README.md) is this entrypoint.
- [`brd.md`](brd.md) is the business requirements document.
- [`prd.md`](prd.md) is the product requirements document.
- [`tech-docs.md`](tech-docs.md) is the single-file technical shape.
- [`delivery.md`](delivery.md) is the executable checklist.
- [`learnings.md`](learnings.md) is the learnings log.
- [`assets/`](assets/README.md) holds the UI design assets: nine lo-fi and three hi-fi accessible SVGs and their README.
