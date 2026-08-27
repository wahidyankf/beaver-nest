# Plan Quality Gate

Use before execution, after changes, and at completion. Repair gaps before advancing.

Do not duplicate hooks; they own links, maps, word budgets, Mermaid accessibility, and automation. This workflow evaluates meaning and readiness.

## Inputs

One active/backlog plan, current repository/specifications/governance, scope, and unresolved decisions.

## Procedure

1. Confirm one non-archived stage, [required files](../conventions/plan-lifecycle.md#formal-plans), and one technical shape. Run `wc -l <plan>/tech-docs.md`; split at 401. A split's `wc -l <plan>/tech-docs/*.md` total must remain at least 401 or collapse it. Never script this check.
2. Inventory recursively. Read every document; inspect each asset's purpose, safety, owner. Follow every map and internal link.
3. Resolve unlinked, empty, stale, duplicate, or unrelated material. Repair links, remove orphans, assign asset reader/purpose/owner, and reject both technical shapes or threshold evasion.
4. Apply [minimal sufficiency](../principles/minimal-sufficiency.md). Keep only artifacts required for scope, safety, correctness, or execution. Split mixed reader jobs when navigation improves; merge needless fragments.
5. Check README status, context, scope, dependencies, technical route, map. Align BRD/PRD goals, roles, stories, Gherkin, scope, non-goals, risks, decisions.
6. Read the technical set as one design. Require junior-readable context, decisions, architecture, components, flow, verification. A split also needs reading order and distinct companion ownership.
7. Schemas need exact old/new shapes, validation, defaults, compatibility, migration, rollback, and tests. Migrations name every source/reader/writer/owner/destination, expand→migrate→verify→contract, recovery, and no-loss proof; apply [migration](../conventions/plan-migrations.md).
8. Keep Specification Changes and File Impact as `tech-docs.md` sections until a required split. Require exact C4/Gherkin deltas, scenarios, bindings/adapters, proof, and every expected `[E]`, `[N]`, `[M]`, or `[D]` path; apply [specification changes](../conventions/plan-specification-changes.md).
9. UI work needs selected design, alternatives, states, responsive/accessibility behavior, displayed safe assets, implementation paths, and device proof. Keep assets under the plan-level `assets/` directory; apply [UI design](../conventions/plan-ui-design.md).
10. `delivery.md` needs ordered `[AC-...]` tasks with input, action, outcome, proof, checkpoints. Prefer `[AI]`; `[HUMAN]` needs unavailable authority. Split mixed work.
11. Active-service plans link [continuity](../development/live-service-continuity.md) and name baseline health, independent candidate, Caddy promotion, revision readiness, LiveView/WebSocket proof, drain/cleanup, and rollback. Reject sole-backend stops, normal-release Tailscale repoints, or required refresh.
12. Testing names unit/integration/behavior/E2E targets, changes, safe AI steps, setup, results, cleanup, evidence. Authentication follows [test identities](../development/test-identities.md).
13. `learnings.md` defines timing, safe evidence, and destination. Search `plans/ideas/`; merge overlap or create only a distinct brief.
14. Compare claims with C4, Gherkin, implementation, governance, active plans. Resolve staleness, duplication, secrets, gaps, contradictions canonically.
15. Repeat until the recursive inventory is reachable, necessary, consistent, junior-executable, and orphan-free.

## Exit Criteria

Pass only when documentation reconciles, artifacts are necessary/discoverable, decisions/dependencies explicit, delivery safe, and no implementer must invent product, security, migration, UI, test, or rollback behavior.

Passing authorizes neither execution nor commit/push. Use [plan execution](plan-execution.md) only after explicit direction.
