# Plan Quality Gate

Use this workflow before executing a formal plan, after a material plan change, and during final completion reconciliation. Its outcome is an executable or repaired plan; do not start while a material gap remains.

Do not rerun or manually duplicate deterministic pre-commit/pre-push validation. Hooks own link, directory-map, word-budget, Mermaid-accessibility, and applicable automated checks. This workflow assesses plan content and execution readiness instead.

## Inputs

- one formal plan below `plans/backlogs/` or `plans/in-progress/`;
- current repository evidence, specifications, and relevant governance; and
- the intended execution scope and any unresolved human decisions.

## Procedure

1. Confirm the plan is in exactly one non-archived lifecycle stage and contains `README.md`, `brd.md`, `prd.md`, `tech-docs.md`, `delivery.md`, and `learnings.md`.
2. Check the README's status, scope, dependencies, and navigation are useful.
3. Check that BRD, PRD, and technical documentation agree on the goal, roles, scope, risks, dependencies, data safety, testing, rollback, and what remains proposed rather than as-built. Reject a plan containing secrets, credentials, personal data, private identifiers, or sensitive runtime values.
4. Check `tech-docs.md` provides junior-readable context, definitions, decisions/trade-offs, flow, impact, and verification. For schemas, require old/new shapes, versioning, compatibility, migration, rollback, and tests. Use Mermaid when it clarifies a non-trivial flow or relationship. Replace jargon lists with plain execution guidance.
5. Confirm named C4, Gherkin, and automated-test changes; relevant test levels/targets; and a safe manual AI verification journey. It names a tool (for example `curl` or Playwright MCP), setup, steps, expected result, and safe evidence—never a secret.
6. Confirm `learnings.md` defines what to learn, capture timing, retained evidence, and likely permanent destination. Require searching `plans/ideas/` before adding an idea, then merging overlap or creating only a distinct one.
7. Compare proposed behavior and architecture with current C4, Gherkin, implementation, and other active plans. Resolve a conflict, duplicate responsibility, stale assumption, or missing affected surface in the plan before execution.
8. Check `delivery.md` for small, ordered, observable tasks; a labeled, checkable checkpoint at the end of every phase; and one `[AI]` or `[HUMAN]` label on every executable checklist item. Default eligible work to `[AI]`; split mixed work instead of hiding a human dependency inside it. Require each task to name enough context, action, outcome, and verification for a junior engineer to perform it safely.
9. Confirm every `[HUMAN]` item states the exact needed decision, credential, physical action, or external authority. Confirm every `[AI]` item remains within current authorization and safety boundaries.
10. Repair every finding in its canonical plan document, refresh the stage index when needed, then repeat this workflow from step 1.

## Exit Criteria

The plan passes only when its documents agree, dependencies are explicit, learning capture and testing are executable, every delivery item has a clear executor and verification, and no material ambiguity would force an executor to invent product, security, or operational decisions.

Passing this gate does not authorize plan execution, commits, pushes, or external actions. Follow the [plan-execution workflow](plan-execution.md) only after explicit user direction.
