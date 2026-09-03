<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- Invoke `nx-workspace` before exploring projects, targets, or dependencies.
- Run tasks through package-manager-prefixed Nx, not underlying tools.
- Use Nx MCP; consult an available plugin `PLUGIN.md` for plugin guidance.
- Never guess flags; check `nx_docs` or `--help` when unsure.

## Scaffolding & Generators

- Invoke `nx-generate` first for any scaffolding.

## When to use nx_docs

- Use for advanced configuration, unfamiliar flags, migrations, plugins, and edge cases.
- Skip for standard commands and generator discovery handled by `nx-generate`.

<!-- nx configuration end-->

## Version Control

- Push `main` directly under [integration](repo-governance/conventions/integration-path.md).
- Only `main` persists; delete non-`main` branches/worktrees immediately after integration or abandonment.
- Make [thematic commits](repo-governance/conventions/thematic-commits.md). Before committing, inspect and remove prohibited data under [data safety](repo-governance/conventions/public-repository-data-safety.md).
- Follow [runtime-data](repo-governance/conventions/runtime-flat-file-data.md).
- [Commit/push](repo-governance/conventions/commit-authorization.md) only when authorized or plan-approved.
- Fix root [push hooks](repo-governance/conventions/push-hook-verification.md); never use unauthorized `--no-verify`.
- Space [GitHub polls](repo-governance/conventions/github-polling.md) two minutes.

## Governance

- Keep all coding harnesses aligned under [the contract](repo-governance/conventions/coding-harness-contract.md).
- [Propagate rules](repo-governance/workflows/rules-propagation.md).
- Use [Diátaxis](repo-governance/conventions/documentation-architecture.md) for non-rule docs.
- Preserve rules through [compaction](repo-governance/principles/governance-continuity.md); [track tasks](repo-governance/conventions/task-tracking.md); preserve unfamiliar parallel changes under `plans/` and `repo-governance/`.
- `plans/` require user request, not Plan mode; clarify why, options, decision, execution, proof, and reader-serving shape. Number split tech-doc companions `01-`. [Lifecycle](repo-governance/conventions/plan-lifecycle.md), [execution](repo-governance/workflows/plan-execution.md), [minimalism](repo-governance/principles/minimal-sufficiency.md).
- Under the [migration convention](repo-governance/conventions/plan-migrations.md): schema-changing plans need a data-model diagram and field-by-field guide beside the exact contract; authority cutovers must prove fresh-process product journeys with the prior source unavailable, never counts or parity alone.
- Bnest active-service plans require Caddy candidate/promotion/rollback, continuous routed-responsiveness proof from preflight through drain, compatible LiveView reconnect, authoritative socket-state recovery, and routed WebSocket/revision proof; never assume refresh.
- Maintain [maps](repo-governance/conventions/directory-maps.md) and [links](repo-governance/conventions/markdown-links.md).
- Label delivery tasks `[AI]`/`[HUMAN]`; prefer AI; checkpoint phases; code-shipping items need RED/GREEN/REFACTOR checkboxes.
- [Ask last](repo-governance/conventions/last-resort-questions.md); stop after the minimal verified change.

## Development

- Prefix shell commands with `rtk` under [the shared RTK instructions](RTK.md), preserving repository-mandated command forms and safety rules.
- Use [English](repo-governance/conventions/language.md).
- Prefer the standard library and existing repository mechanisms; add an external dependency only under the [dependency-selection standard](repo-governance/development/dependency-selection.md).
- New tables need [audit columns](repo-governance/conventions/database-audit-columns.md); event logs and projections are exempt.
- Bnest is 24/7; obey [continuity](repo-governance/development/live-service-continuity.md); failed health stops work.
- A commit or push is not a deployment. Before reporting an active-service change complete, verify the routed backend serves the intended revision or behavior; otherwise perform a no-downtime candidate cutover.
- Before completion, stop unneeded non-production servers, watchers, candidates, and temporary proxies; retain only the active route and bounded drain.
- Separate server/proxy lifecycles; follow [start/restart](repo-governance/workflows/development-server-restart.md) and [proxy](repo-governance/workflows/development-tailnet-proxy.md).
- Keep [quality gates](repo-governance/development/quality-gates.md) green.
- Guard compute-bearing Nx work under `apps/`, `libs/`, and repository-owned tools with [resource-aware development](repo-governance/development/resource-aware-development.md). Exit `75` is transient capacity or a held heavy-work lease, not task/test failure: read the deferral message, confirm any named holder exited, then retry serially; never abandon the objective. Exit `73` requires storage cleanup first; never blind-retry it. Exit `78` means a strict profile or local config requires replanning; ordinary work falls back through `minimal`. Never bypass, parallel-retry, weaken gates, or change class; recovery/status controls remain direct.
- Keep `test:e2e` outside `test:quick`; run only affected/UI-accessibility states at the exact origin, wait for connected LiveView, isolate user records, and close task-created tabs/contexts except explicit handoffs. Follow [end-to-end testing](repo-governance/development/end-to-end-testing.md).
- Manually inspect [UI changes](repo-governance/conventions/plan-ui-design.md) at the exact origin and supported viewports before completion; tests/inference never substitute. Add exploratory and spec-blind usability [passes](repo-governance/workflows/exploratory-and-usability-testing.md).
- Never test real users; use isolated `test-user-` [identities](repo-governance/development/test-identities.md); inspect production schemas read-only.
- **Project rule** (except `libs/ex-bdd`): assess/update relevant [specifications](repo-governance/development/specification-maintenance.md); Gherkin → failing bindings → Nx red → implementation → manual smoke. Implement every step; exempt incapable adapters.
- Update affected project [READMEs](repo-governance/conventions/project-readmes.md).
- Use accessible [Mermaid](repo-governance/conventions/markdown-visualizations.md); visible node/state segments are at most 32 graphemes and edge/transition segments at most 24. Scope Badakmini to changed files.
