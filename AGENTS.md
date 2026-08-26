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
- Non-`main` worktrees are temporary deployment infrastructure; remove them immediately after use under [integration](repo-governance/conventions/integration-path.md).
- Make [thematic commits](repo-governance/conventions/thematic-commits.md). Before committing, inspect and remove prohibited data under [data safety](repo-governance/conventions/public-repository-data-safety.md).
- Follow [runtime-data](repo-governance/conventions/runtime-flat-file-data.md).
- [Commit/push](repo-governance/conventions/commit-authorization.md) only when authorized or plan-approved.
- Fix root [push hooks](repo-governance/conventions/push-hook-verification.md); never use `--no-verify` without authorization.
- Space [GitHub polls](repo-governance/conventions/github-polling.md) two minutes.

## Governance

- [Propagate rules](repo-governance/workflows/rules-propagation.md).
- Use [Diátaxis](repo-governance/conventions/documentation-architecture.md) for non-rule docs.
- Preserve rules through [compaction](repo-governance/principles/governance-continuity.md); track [tasks](repo-governance/conventions/task-tracking.md).
- `plans/`: explicit request only; Plan mode does not authorize repository docs. Use `tech-docs/`, [lifecycle](repo-governance/conventions/plan-lifecycle.md), [execution](repo-governance/workflows/plan-execution.md), and [minimalism](repo-governance/principles/minimal-sufficiency.md).
- Bnest active-service plans require Caddy candidate/promotion/rollback, compatible LiveView reconnect, and routed WebSocket/revision proof; never assume refresh.
- Maintain [maps](repo-governance/conventions/directory-maps.md) and [links](repo-governance/conventions/markdown-links.md).
- Label delivery tasks `[AI]`/`[HUMAN]`; prefer AI; checkpoint phases.
- [Ask last](repo-governance/conventions/last-resort-questions.md); stop after the minimal verified change.

## Development

- Use [English](repo-governance/conventions/language.md).
- Bnest is 24/7; obey [continuity](repo-governance/development/live-service-continuity.md); failed health stops work.
- A commit or push is not a deployment. Before reporting an active-service change complete, verify the routed backend serves the intended revision or behavior; otherwise perform a no-downtime candidate cutover.
- Before completion, stop unneeded non-production servers, watchers, candidates, and temporary proxies; retain only the active route and bounded drain.
- Separate server/proxy lifecycles; follow [restart](repo-governance/workflows/development-server-restart.md) and [proxy](repo-governance/workflows/development-tailnet-proxy.md).
- Keep [quality gates](repo-governance/development/quality-gates.md) green.
- Keep `test:e2e` outside `test:quick`; run affected cases and UI-accessibility states only. Wait for connected LiveView before interaction, and isolate user-owned records across parallel workers. Follow [end-to-end testing](repo-governance/development/end-to-end-testing.md).
- Match each E2E browser origin exactly to its served application origin so LiveView/WebSocket checks are real.
- Never test real users; use isolated `test-user-` [identities](repo-governance/development/test-identities.md); inspect production schemas read-only.
- **Application rule** (except `libs/ex-bdd`): assess/update all relevant [specifications](repo-governance/development/specification-maintenance.md); Gherkin → failing bindings → Nx red → implementation → manual smoke. Implement every step; exempt incapable adapters.
- Update affected project [READMEs](repo-governance/conventions/project-readmes.md).
- Use accessible [Mermaid](repo-governance/conventions/markdown-visualizations.md); scope Badakmini to changed files.
