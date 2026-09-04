# Plan Quality Gate

Produce exactly one terminal result—`PASS` or one `BLOCKED_*` variant—for one formal plan's semantic readiness. Run before execution, after material plan changes, and at completion. Never recurse or automatically start another run.

## Sufficiency and Ownership

A `PASS` means good enough for the authorized scope, known risks, and applicable rules—not perfect, exhaustive, or future-proof. Do not block on stylistic preference, speculative hardening, optional detail, or an improvement that can wait without making execution unsafe or ambiguous. Apply [minimal sufficiency](../principles/minimal-sufficiency.md).

This workflow evaluates meaning, consistency, safety, executability, and proof. Deterministic tooling owns machine-decidable checks, including links, directory maps, word budgets, Mermaid, harness parity, and later automated contracts. Do not manually reproduce, sample, or second-guess those checks.

Run canonical tooling only in verification and consume its findings. For a check delivered by the plan, verify that `delivery.md` has an executable implementation and proof task; do not simulate the future tool. At completion, its target must exist and pass.

## Snapshot and Ledger

Freeze the plan path and stage, Git revision plus dirty paths, scope, relevant specification and governance paths, unresolved decisions, and cycle `1`. A material external input change ends the run as `BLOCKED_INPUT_CHANGED`; it never causes an automatic restart. Recorded repairs remain inside this run and do not trigger another quality-gate run.

Audit before editing. Create a finite ledger containing `ID`, canonical rule, location, material gap, required repair, proof, and status: `OPEN`, `FIXED`, `NOT_APPLICABLE`, or `BLOCKED`. Only gaps that violate a rule or make scoped execution unsafe, ambiguous, or unprovable enter the ledger. Mandatory findings cannot be waived; `NOT_APPLICABLE` requires evidence. Preserve the snapshot, cycle, ledger, pending verification, and authorization through compaction or handoff under [governance continuity](../principles/governance-continuity.md).

## Bounded Procedure

1. Recursively inventory and read the plan, assets, relevant implementation, specifications, and governance. Do not validate machine-owned concerns.
2. Complete one semantic audit without edits. Check:
   - the formal [plan lifecycle](../conventions/plan-lifecycle.md): one stage, required documents, one technical shape, and truthful status;
   - coherent purpose, decision, scope, risks, acceptance, and a junior-readable route from BRD/PRD through design and delivery;
   - necessary, non-placeholder artifacts with distinct reader jobs;
   - synchronized architecture, Gherkin, file impact, dependencies, and applicable [software-quality routes](../development/software-quality-enforcement.md);
   - executable ownership, acceptance traceability, RED/GREEN/REFACTOR tasks, checkpoints, evidence, cleanup, recovery, and rollback;
   - applicable [migration](../conventions/plan-migrations.md), [UI](../conventions/plan-ui-design.md), [API](../development/api-testing.md), test-isolation, and live-service contracts; and
   - conflicts with current specifications, governance, implementation, or active plans.
3. Freeze the initial ledger. Repair only its findings in dependency and safety order. Each repair must close an `OPEN` row without expanding product scope. Missing decisions, authority, or irreconcilable rules become `BLOCKED`, never invented answers.
4. Verify semantically in read-only mode, reviewing only repaired meaning and cross-document effects. Then run:

   ```sh
   ./resource-guard run --class ephemeral -- npm exec -- nx run -p badakmini-cli -t test:repo
   ```

5. Return `PASS` when no row is `OPEN` or `BLOCKED`, tooling passes, no new material semantic gap appears, and the snapshot changed only through recorded repairs.
6. Otherwise allow exactly one stabilization cycle. Add only repair-caused semantic gaps and deterministic-tool findings, set cycle `2`, repair them once, and repeat step 4. A fixed finding cannot reopen without changed input; changed input yields `BLOCKED_INPUT_CHANGED`.
7. After cycle `2`, return `PASS` if step 5 holds. Otherwise return `BLOCKED_NON_CONVERGENT` with the remaining ledger and evidence. Do not repair, restart, or invoke this workflow again automatically.

Resource-guard recovery required by its canonical standard is infrastructure handling, not another quality-gate cycle.

If canonical recovery cannot obtain a deterministic verdict, return `BLOCKED_TOOLING` with the failure evidence. Never simulate the check or retry it without bound.

## Terminal Contract

`PASS` authorizes neither execution nor commit/push. Any `BLOCKED_*` result names the reason, remaining rows, and required external change. Resume only after new input or authority starts a fresh run through [plan execution](plan-execution.md).
