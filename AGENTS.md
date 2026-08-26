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

- Use local-`main` for default pushes; use [integration paths](repo-governance/conventions/integration-path.md) for PRs.
- Make [thematic commits](repo-governance/conventions/thematic-commits.md).
- Never commit secrets, tailnet identifiers, or machine-local data; see [data safety](repo-governance/conventions/public-repository-data-safety.md).
- Keep runtime flat files within `data/{general,users,system}`; follow [runtime-data](repo-governance/conventions/runtime-flat-file-data.md).
- [Commit or push](repo-governance/conventions/commit-authorization.md) only with explicit user authorization or an approved plan.
- Fix hooks at root; never use `--no-verify` without explicit authorization. Follow [push-hook verification](repo-governance/conventions/push-hook-verification.md).
- Space GitHub polls two minutes apart; follow [GitHub polling](repo-governance/conventions/github-polling.md).

## Governance

- Follow [rules propagation](repo-governance/workflows/rules-propagation.md) for rule changes.
- Use [Diátaxis](repo-governance/conventions/documentation-architecture.md) for non-rule docs.
- Preserve rules across [compaction](repo-governance/principles/governance-continuity.md).
- Keep [tasks](repo-governance/conventions/task-tracking.md) current.
- Create plans only on request; [plan lifecycle](repo-governance/conventions/plan-lifecycle.md) keeps `specs/` authoritative.
- Maintain [directory maps](repo-governance/conventions/directory-maps.md) for governed trees.
- Keep [internal Markdown links](repo-governance/conventions/markdown-links.md) valid outside archives.
- Ask as a [last resort](repo-governance/conventions/last-resort-questions.md).
- Make the [smallest sufficient change](repo-governance/principles/minimal-sufficiency.md); stop when verified.

## Development

- Use [English](repo-governance/conventions/language.md) for artifacts.
- Separate server/proxy lifecycles; follow [restart](repo-governance/workflows/development-server-restart.md) and [proxy](repo-governance/workflows/development-tailnet-proxy.md).
- Keep applicable [quality gates](repo-governance/development/quality-gates.md) green.
- Keep `test:e2e` out of `test:quick`; run only affected end-to-end cases during development. Follow the [end-to-end testing standard](repo-governance/development/end-to-end-testing.md).
- **Application rule** (except `libs/ex-bdd`): assess/update all relevant [specifications](repo-governance/development/specification-maintenance.md); Gherkin → failing bindings → Nx red → implementation → manual smoke. Implement every step; exempt incapable adapters.
- Update affected project [READMEs](repo-governance/conventions/project-readmes.md).
- Prefer useful, accessible [Mermaid visuals](repo-governance/conventions/markdown-visualizations.md).
