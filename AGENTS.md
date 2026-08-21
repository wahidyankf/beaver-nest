<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- For navigating/exploring the workspace, invoke the `nx-workspace` skill first - it has patterns for querying projects, targets, and dependencies
- When running tasks (for example build, lint, test, e2e, etc.), always prefer running the task through `nx` (i.e. `nx run`, `nx run-many`, `nx affected`) instead of using the underlying tooling directly
- Prefix nx commands with the workspace's package manager (e.g., `pnpm nx build`, `npm exec nx test`) - avoids using globally installed CLI
- You have access to the Nx MCP server and its tools, use them to help the user
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

- Use direct local-`main` pushes by default; follow [integration paths](repo-governance/conventions/integration-path.md) for PRs.
- Make every commit [thematic](repo-governance/conventions/thematic-commits.md).
- Never commit secrets, tailnet names, or machine-local data. See [data safety](repo-governance/conventions/public-repository-data-safety.md).
- [Commit or push](repo-governance/conventions/commit-authorization.md) only with explicit user authorization or an approved plan.
- Fix hook failures at root; never use `--no-verify` without explicit authorization. Follow [push-hook verification](repo-governance/conventions/push-hook-verification.md).
- Space repeated GitHub status polls at least two minutes apart. Follow the [GitHub polling convention](repo-governance/conventions/github-polling.md).

## Repository Governance

- Automatically follow [rules propagation](repo-governance/workflows/rules-propagation.md) for every repository rule change, even when not explicitly requested.
- Use [Diátaxis for non-rule documentation](repo-governance/conventions/documentation-architecture.md).
- Preserve rule-governed repository behavior across context compaction. Follow the [governance-continuity principle](repo-governance/principles/governance-continuity.md).
- Split work into granular task-list items and keep their status synchronized with reality. Follow the [task-tracking convention](repo-governance/conventions/task-tracking.md).
- Ask the user only as a last resort after exhausting safe, in-scope ways to proceed. Follow the [last-resort questions convention](repo-governance/conventions/last-resort-questions.md).
- Make the smallest change that fully satisfies the need, and stop when required verification passes. Follow the [minimal-sufficiency principle](repo-governance/principles/minimal-sufficiency.md).

## Development

- Keep every applicable [quality gate](repo-governance/development/quality-gates.md) green.
- Keep `test:e2e` out of `test:quick`; run only affected end-to-end cases during development. Follow the [end-to-end testing standard](repo-governance/development/end-to-end-testing.md).
- Develop app and library behavior with [TDD](repo-governance/development/test-driven-development.md).
- Maintain every app and library [project README](repo-governance/conventions/project-readmes.md), updating it when affected.
- Prefer accessible Mermaid for useful Markdown visuals under the [visualization convention](repo-governance/conventions/markdown-visualizations.md).
