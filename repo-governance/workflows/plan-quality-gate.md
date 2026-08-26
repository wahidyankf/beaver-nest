# Plan Quality Gate

Use before execution, after plan changes, and at completion. Repair gaps before advancing.

Do not duplicate deterministic pre-commit/pre-push checks. Hooks own links, maps, word budgets, Mermaid accessibility, and automated gates. This workflow evaluates meaning and readiness.

## Inputs

One active/backlog plan, current repository/specifications/governance, scope, and unresolved external decisions.

## Procedure

1. Confirm one non-archived stage and `README.md`, `brd.md`, `prd.md`, `delivery.md`, `learnings.md`, and `tech-docs/README.md`.
2. Inventory every file/directory recursively. Read every plan document completely; inspect each asset's purpose, safety, and owner. Follow every map and internal plan link.
3. Find unlinked/empty/stale files, unexplained evidence, duplicate ownership, and unrelated material. Integrate required content, update links, remove redundant orphans, and give each asset a reader, purpose, and owner.
4. Apply [minimal sufficiency](../principles/minimal-sufficiency.md). Keep only artifacts required for scope, safety, correctness, or execution. Split mixed reader jobs when navigation improves; merge needless fragments.
5. Check README status, context, scope, dependencies, technical route, and complete map. Align BRD/PRD goals, roles, stories, Gherkin criteria, scope, non-goals, risks, and decisions.
6. Read the technical set as one design. Require junior-readable context, selected decisions, architecture, components, flow, verification, reading order, and distinct companion ownership.
7. Schemas need exact old/new shapes, validation, defaults, compatibility, migration, rollback, and tests. Migrations name every source/reader/writer/owner/destination, expand→migrate→verify→contract, recovery, and no-loss proof; apply [migration](../conventions/plan-migrations.md).
8. `tech-docs/specification-changes.md` selects durable PRD outcomes with exact C4/Gherkin deltas, scenarios, bindings/adapters, and proof. `file-impact.md` lists every expected `[E]`, `[N]`, `[M]`, or `[D]` path; apply [specification changes](../conventions/plan-specification-changes.md).
9. UI work needs selected design, alternatives, states, responsive/accessibility behavior, displayed safe assets, implementation paths, and device proof under `tech-docs/`. Apply [UI design](../conventions/plan-ui-design.md).
10. `delivery.md` needs small ordered `[AC-...]` tasks with input, action, outcome, proof, and phase checkpoints. Prefer `[AI]`; `[HUMAN]` needs unavailable authority. Split mixed work.
11. Active-service plans link [continuity](../development/live-service-continuity.md) and name baseline health, independent candidate, Caddy promotion, revision readiness, LiveView/WebSocket proof, drain/cleanup, and rollback. Reject sole-backend stops, normal-release Tailscale repoints, or required refresh.
12. Testing names unit/integration/behavior/E2E targets, spec/test changes, safe manual AI steps, setup, expected results, cleanup, and evidence. Authentication follows [test identities](../development/test-identities.md).
13. `learnings.md` defines timing, safe evidence, and destination. Search `plans/ideas/`; merge overlap or create only a distinct brief.
14. Compare claims with current C4, Gherkin, implementation, governance, and active plans. Resolve staleness, duplication, secrets, missing surfaces, and contradictions canonically.
15. Repeat until the recursive inventory is reachable, necessary, consistent, junior-executable, and orphan-free.

## Exit Criteria

Pass only when documentation is reconciled, artifacts are necessary and discoverable, decisions/dependencies are explicit, delivery is safe, and no implementer must invent product, security, migration, UI, test, or rollback behavior.

Passing authorizes neither execution nor commit/push. Use [plan execution](plan-execution.md) only after explicit direction.
