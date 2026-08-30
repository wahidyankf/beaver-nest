# Plan Quality Gate

Use before execution, after changes, and at completion. Repair gaps before advancing.

Do not duplicate hooks; they own links, maps, word budgets, Mermaid accessibility, and automation. This workflow evaluates meaning and readiness.

## Inputs

One active/backlog plan, current repository/specifications/governance, scope, and unresolved decisions.

## Procedure

1. Confirm one non-archived stage, [required files](../conventions/plan-lifecycle.md#formal-plans), and exactly one technical shape. Inspect file lengths as a review signal, then judge the shape by reader needs, cohesion, navigation, and companion ownership; never require or prohibit a split from line count alone.
2. Inventory recursively. Read every document; inspect each asset's purpose, safety, owner. Follow every map and internal link.
3. Resolve unlinked, empty, stale, duplicate, or unrelated material. Repair links, remove orphans, assign asset reader/purpose/owner, and reject both technical shapes or a shape chosen to satisfy a numeric threshold instead of reader needs.
4. Apply [minimal sufficiency](../principles/minimal-sufficiency.md). First require a reader to understand why the plan exists, its options and selected decision, and how it will be executed and proved. Keep only artifacts required for that clarity, scope, safety, correctness, or execution. Treat split/unsplit shape only as a mechanism: split mixed reader jobs when navigation improves; merge needless fragments.
5. Check README status, context, scope, dependencies, technical route, map. Align BRD/PRD goals, roles, stories, Gherkin, scope, non-goals, risks, decisions.
6. Read the technical set as one design. Require junior-readable context, decisions, architecture, components, flow, verification. A split also needs reading order and distinct companion ownership.
7. Schemas need exact old/new shapes, validation, defaults, compatibility, migration, rollback, and tests. Require an ERD for every relational database schema change, or a storage-appropriate data-model diagram for a non-relational persistent model; it must show affected entities/records, keys, relationships or references, cardinality where applicable, and ownership context without replacing the exact contract. Require a field-by-field guide for every column, property, or key in the affected resulting model; it explains purpose and any non-obvious shape, unit/timezone, owner/producer, null/default behavior, lifecycle, key/reference role, or sensitivity. Migrations name every source/reader/writer/owner/destination, expand→migrate→verify→contract, recovery, and no-loss proof; apply [migration](../conventions/plan-migrations.md).
8. Keep Specification Changes and File Impact in `tech-docs.md` or mapped companions with distinct reader jobs. Require exact C4/Gherkin deltas, scenarios, bindings/adapters, proof, and every expected `[E]`, `[N]`, `[M]`, or `[D]` path; apply [specification changes](../conventions/plan-specification-changes.md).
9. UI work needs selected design, alternatives, states, responsive/accessibility behavior, displayed safe assets, implementation paths, and device proof. Require PRD acceptance criteria and delivery tasks for a post-implementation manual browser check of every affected route/state and supported viewport class at the exact served origin. At completion, reject code-, test-, inference-, or asset-only proof. Keep assets under the plan-level `assets/` directory; apply [UI design](../conventions/plan-ui-design.md).
10. `delivery.md` needs ordered `[AC-...]` tasks with input, action, outcome, proof, checkpoints. Prefer `[AI]`; `[HUMAN]` needs unavailable authority. Split mixed work. Require an explicit rules-propagation task when rule changes are possible and an exact canonical C4 update task in the relevant implementation phase when documented architecture changes.
11. Active-service plans link [continuity](../development/live-service-continuity.md) and name baseline health and responsiveness, independent candidate, Caddy promotion, revision readiness, LiveView/WebSocket proof, drain/cleanup, and rollback. Require acceptance criteria and delivery proof for continuous exact-origin responsiveness from preflight through compute gates, candidate qualification, promotion, and drain: a numeric p95 budget, numeric per-sample maximum, zero routed failures, representative user journey, and an explicit rollback trigger. A 2xx-only health check is insufficient. Reject sole-backend stops, normal-release Tailscale repoints, or required refresh.
12. Testing names unit/integration/behavior/E2E targets, changes, safe AI steps, setup, results, cleanup, evidence. Authentication follows [test identities](../development/test-identities.md).
13. `learnings.md` defines timing, safe evidence, and destination. Search `plans/ideas/`; merge overlap or create only a distinct brief.
14. Compare claims with C4, Gherkin, implementation, governance, active plans. Resolve staleness, duplication, secrets, gaps, contradictions canonically.
15. Repeat until the recursive inventory is reachable, necessary, consistent, junior-executable, and orphan-free.

## Exit Criteria

Pass only when documentation reconciles, artifacts are necessary/discoverable, decisions/dependencies explicit, delivery safe, and no implementer must invent product, security, migration, UI, test, or rollback behavior.

Passing authorizes neither execution nor commit/push. Use [plan execution](plan-execution.md) only after explicit direction.
