<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- For navigating/exploring the workspace, invoke the `nx-workspace` skill first - it has patterns for querying projects, targets, and dependencies
- When running tasks (for example build, lint, test, e2e, etc.), always prefer running the task through `nx` (i.e. `nx run`, `nx run-many`, `nx affected`) instead of using the underlying tooling directly
- Prefix nx commands with the workspace's package manager (e.g., `pnpm nx build`, `npm exec nx test`) - avoids using globally installed CLI
- Use Nx MCP tools to help.
- For Nx plugin best practices, check `node_modules/@nx/<plugin>/PLUGIN.md`. Not all plugins have this file - proceed without it if unavailable.
- NEVER guess CLI flags - always check nx_docs or `--help` first when unsure

## Scaffolding & Generators

- For scaffolding tasks (creating apps, libs, project structure, setup), ALWAYS invoke the `nx-generate` skill FIRST before exploring or calling MCP tools

## When to use nx_docs

- USE for: advanced config options, unfamiliar flags, migration guides, plugin configuration, edge cases
- DON'T USE for: basic generator syntax (`nx g @nx/react:app`), standard commands, things you already know
- The `nx-generate` skill handles generator discovery internally - don't call nx_docs just to look up generator syntax

<!-- nx configuration end-->

## Version Control

- Push local `main` directly to `origin/main`; no PRs. Follow [integration path](repo-governance/conventions/integration-path.md).
- Make [thematic commits](repo-governance/conventions/thematic-commits.md).
- Never commit secrets, tailnet IDs, or local data; follow [data safety](repo-governance/conventions/public-repository-data-safety.md).
- Keep runtime flat files per [runtime-data](repo-governance/conventions/runtime-flat-file-data.md).
- [Commit or push](repo-governance/conventions/commit-authorization.md) only when explicitly authorized or plan-approved.
- Fix hooks at root; use no `--no-verify` without explicit authorization. Follow [push-hook verification](repo-governance/conventions/push-hook-verification.md).
- Poll GitHub two minutes apart; follow [GitHub polling](repo-governance/conventions/github-polling.md).

## Governance

- [Propagate rules](repo-governance/workflows/rules-propagation.md).
- Use [Diátaxis](repo-governance/conventions/documentation-architecture.md) for non-rule docs.
- Preserve rules through [compaction](repo-governance/principles/governance-continuity.md).
- Track [tasks](repo-governance/conventions/task-tracking.md).
- `plans/`: explicit request only; harness Plan mode gives no authorization. Follow [lifecycle](repo-governance/conventions/plan-lifecycle.md).
- Maintain [maps](repo-governance/conventions/directory-maps.md).
- Keep [links](repo-governance/conventions/markdown-links.md) valid.
- Label delivery tasks `[AI]`/`[HUMAN]`; prefer AI; checkpoint phases.
- Ask as a [last resort](repo-governance/conventions/last-resort-questions.md).
- Be [minimal](repo-governance/principles/minimal-sufficiency.md); stop.

## Development

- Use [English](repo-governance/conventions/language.md).
- Separate server/proxy lifecycles; follow [restart](repo-governance/workflows/development-server-restart.md) and [proxy](repo-governance/workflows/development-tailnet-proxy.md).
- Keep [quality gates](repo-governance/development/quality-gates.md) green.
- Keep `test:e2e` outside `test:quick`; run affected cases only. Follow the [end-to-end standard](repo-governance/development/end-to-end-testing.md).
- Never test with real users; use isolated `test-user-` [identities](repo-governance/development/test-identities.md). Production schema inspection is read-only and structural.
- **Application rule** (except `libs/ex-bdd`): assess/update all relevant [specifications](repo-governance/development/specification-maintenance.md); Gherkin → failing bindings → Nx red → implementation → manual smoke. Implement every step; exempt incapable adapters.
- Update affected project [READMEs](repo-governance/conventions/project-readmes.md).
- Use accessible [Mermaid](repo-governance/conventions/markdown-visualizations.md); scope Badakmini to changed files.
