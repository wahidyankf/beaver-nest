# Multi-Harness Repository Support

**Status:** Completed

**Created:** 2026-08-28

**Started:** 2026-08-28

**Execution started:** 2026-08-28

**Completed:** 2026-08-28

**Scope:** Repository development through Codex, Claude Code, and OpenCode

## Context

The repository currently exposes its instructions, seven Nx-oriented skills, the Nx MCP server, and one CI-monitor subagent primarily through Codex conventions. The requested outcome is that contributors can perform the same governed repository work from Codex, Claude Code, or OpenCode without maintaining independent rule sets or silently losing required skills, agents, and capabilities.

The repository needs deterministic proof of its committed harness contract. Badakmini will inspect files and report drift; it will not generate adapters, modify configuration, invoke a model, authenticate a provider, or claim that user-global settings are identical.

## Recommendation

Keep `AGENTS.md`, `.agents/skills/`, and `.agents/agents/` as canonical repository-owned sources. Start the canonical agent set with the existing CI monitor and an OSE Public-inspired, read-only `web-researcher`. Add thin Claude and OpenCode/Codex adapters only where native discovery differs. Extend Badakmini with a read-only `governance harness-contract validate` command that resolves and normalizes effective instruction, skill, and agent content; rejects adapter overlays or semantic permission drift; and proves required Nx MCP declarations for all three harnesses.

Harness UI, model choice, credentials, local memory, approval prompts, and user-global extensions remain intentionally outside the equality contract. See the [technical design](tech-docs.md).

## Scope

- Define the repository-owned contract shared by Codex, Claude Code, and OpenCode.
- Preserve one canonical instruction source and one canonical copy of each skill and custom-agent workflow.
- Add minimal harness adapters for instruction loading, skill discovery, the CI monitor, the source-grounded web researcher, and Nx MCP.
- Make Badakmini deterministically reject missing, extra, stale, malformed, or content-divergent committed adapters, including changed descriptions, extra adapter instructions, wrong canonical routes, modified capability mappings, and altered supporting-resource bundles.
- Route the new validator through `test:repo`, Nx cache inputs, and pre-push selection.
- Document installation and read-only verification for each harness and RTK integration.

## Non-goals

- Add Claude or OpenCode as providers to the Bnest chat runtime.
- Force the same model, provider, authentication, local memory, UI, or permission prompt implementation.
- Inspect or commit credentials, user-global configuration, ignored local overrides, or machine identifiers.
- Generate or rewrite harness files from Badakmini; validation is read-only.
- Introduce empty MCP, plugin, command, or custom-agent abstractions without a current repository dependency.
- Guarantee that a model obeys instructions; the deterministic guarantee covers the committed repository contract and native discovery topology.

## Dependencies

- Codex and OpenCode must continue to load root `AGENTS.md`; Claude Code must load a root `CLAUDE.md` import adapter.
- Claude Code needs a native adapter for canonical `.agents/skills/`, which it does not currently discover directly.
- The Nx skills and `monitor-ci` workflow depend on the `nx-mcp` server; `monitor-ci` also depends on the `ci-monitor-subagent` definition.
- The `web-researcher` depends on repository-read, web-search, and web-fetch capabilities and must deny repository writes, shell execution, and nested delegation wherever the harness can enforce those restrictions.
- Harness-specific credentials and one-time trust/approval remain machine-local prerequisites.
- Implementation must follow Badakmini's canonical BDD corpus and unit, local-only integration, and process E2E adapters.

## Navigation

- [Business requirements](brd.md) defines value, roles, outcomes, and risks.
- [Product requirements](prd.md) defines personas, stories, and Gherkin acceptance.
- [Technical design](tech-docs.md) defines canonical sources, adapters, validation, specifications, and file impact.
- [Delivery](delivery.md) records completed implementation and the remaining final verification/archive proof.
- [Learnings](learnings.md) records safe evidence and planning decisions.

## Directory Map

- [Business requirements](brd.md) states the repository-development need and constraints.
- [Delivery](delivery.md) owns the ordered implementation and verification checklist.
- [Learnings](learnings.md) records safe observations and their disposition.
- [Product requirements](prd.md) defines plan-level acceptance behavior.
- [Technical design](tech-docs.md) owns the architecture, deterministic validator, specification changes, and exact file impact.
