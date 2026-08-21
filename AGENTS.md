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

- Make every commit thematic. Follow the [thematic-commit convention](repo-governance/conventions/thematic-commits.md).
- Commit or push only when explicitly authorized by the user or included in a user-approved plan. Follow the [commit-authorization convention](repo-governance/conventions/commit-authorization.md).
- Fix push-hook failures at their root cause and push normally. Use `--no-verify` only with explicit user authorization for that push. Follow the [push-hook verification convention](repo-governance/conventions/push-hook-verification.md).

## Repository Governance

- Automatically follow [rules propagation](repo-governance/workflows/rules-propagation.md) whenever creating, adding, updating, moving, deleting, or otherwise changing repository rules, even when the user does not mention the workflow.
- Preserve rule-governed repository behavior across context compaction. Follow the [governance-continuity principle](repo-governance/principles/governance-continuity.md).
- Split work into granular task-list items and keep their status synchronized with reality. Follow the [task-tracking convention](repo-governance/conventions/task-tracking.md).
- Ask the user only as a last resort after exhausting safe, in-scope ways to proceed. Follow the [last-resort questions convention](repo-governance/conventions/last-resort-questions.md).
- Make the smallest change that fully satisfies the need, and stop when required verification passes. Follow the [minimal-sufficiency principle](repo-governance/principles/minimal-sufficiency.md).

## Development

- Develop application and library behavior with test-driven development. Follow the [TDD standard](repo-governance/development/test-driven-development.md).
