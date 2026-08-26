# Plan Quality Gate

Use this workflow before executing a formal plan, after a material plan change, and during final completion reconciliation. Its outcome is an executable or repaired plan; do not start while a material gap remains.

Do not rerun or manually duplicate deterministic pre-commit/pre-push validation. Hooks own link, directory-map, word-budget, Mermaid-accessibility, and applicable automated checks. This workflow assesses plan content and execution readiness instead.

## Inputs

- one formal plan below `plans/backlogs/` or `plans/in-progress/`;
- current repository evidence, specifications, and relevant governance; and
- the intended execution scope and any unresolved human decisions.

## Procedure

1. Confirm one non-archived stage and all six required files: `README.md`, `brd.md`, `prd.md`, `tech-docs.md`, `delivery.md`, and `learnings.md`.
2. Check useful README status, scope, dependencies, and navigation.
3. Check BRD, PRD, and technical docs agree on goal, roles, scope, risks, dependencies, data safety, testing, rollback, and proposed/as-built state. Reject secrets and sensitive identifiers or runtime values.
4. Check `tech-docs.md` has junior-readable context, decisions, flow, exact annotated File Impact, and verification. Label every path `[E]`, `[N]`, `[M]`, or `[D]`. Schemas need old/new shapes, compatibility, migration, rollback, and tests. Apply [migration](../conventions/plan-migrations.md) and [UI-design](../conventions/plan-ui-design.md) conventions when relevant.
5. Confirm selected C4/Gherkin/test targets and safe manual AI verification: tool, setup, steps, result, safe evidence—never a secret. Auth tests follow [test identities](../development/test-identities.md). Plan-only PRD criteria need a reason and named delivery proof, not a `specs/` copy. Behavior changes follow [plan specification changes](../conventions/plan-specification-changes.md).
6. Confirm `learnings.md` defines what to learn, capture timing, retained evidence, and likely permanent destination. Require searching `plans/ideas/` before adding an idea, then merging overlap or creating only a distinct one.
7. Compare proposed behavior and architecture with current C4, Gherkin, implementation, and other active plans. Resolve a conflict, duplicate responsibility, stale assumption, or missing affected surface in the plan before execution.
8. Check `prd.md` identifies user stories and expresses acceptance criteria in Gherkin. Check `delivery.md` for small, ordered, observable tasks; a labeled checkpoint at every phase end; `[AI]`/`[HUMAN]` and relevant PRD `[AC-...]` labels on every executable item; and enough context, action, outcome, and verification for a junior engineer. Default eligible work to `[AI]`; split mixed work.
9. Confirm every `[HUMAN]` item states the exact needed decision, credential, physical action, or external authority. Confirm every `[AI]` item remains within current authorization and safety boundaries.
10. Repair every finding in its canonical plan document, refresh the stage index when needed, then repeat this workflow from step 1.

## Exit Criteria

The plan passes only when its documents agree, dependencies are explicit, learning capture and testing are executable, every delivery item has a clear executor and verification, and no material ambiguity would force an executor to invent product, security, or operational decisions.

Passing this gate does not authorize plan execution, commits, pushes, or external actions. Follow the [plan-execution workflow](plan-execution.md) only after explicit user direction.
