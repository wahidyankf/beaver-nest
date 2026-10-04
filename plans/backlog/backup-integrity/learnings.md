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

None yet. Phase 2 findings are recorded here as sanitized entries V0 onward; the Phase 3 verdict is entry V1. Phase 10
records two separately labelled sections in this file, `## Exploratory findings` and `## Usability findings`, and the
route, state, viewport class and result tables of the rendered checks.
