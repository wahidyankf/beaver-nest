# Coding-Harness Contract Change

Use this workflow whenever repository-owned rules, skills, custom agents, required harness capabilities, or their adapters are added, changed, renamed, or removed. The goal is one canonical edit with complete Codex, Claude Code, and OpenCode parity—not three independently maintained workflows.

## Prerequisites

- Read the [coding-harness contract](../conventions/coding-harness-contract.md).
- Keep credentials, user-global configuration, local memory, and generated vendor state out of the repository.
- For a rule change, run [rules propagation](rules-propagation.md) first.
- Check current official vendor documentation before changing a native adapter schema; do not infer fields from another harness.

## Procedure

### 1. Classify the canonical change

Choose every affected concern, then edit its canonical source before any adapter:

- **Rules:** edit root `AGENTS.md`. Keep root `CLAUDE.md` as the exact `@AGENTS.md` import. Do not add nested or harness-specific instruction files unless the convention and validator first define equivalent routing.
- **Skills:** edit the complete `.agents/skills/<name>/` bundle, including `SKILL.md` and supporting resources. The directory and frontmatter `name` must match.
- **Agents:** edit `.agents/agents/<name>.md`, including its prompt and semantic `requires`, `denies`, and `constraints`.
- **Required capabilities:** define the credential-free executable behaviour in the convention and validator before changing harness-native declarations.

### 2. Reconcile the adapters

For a skill, Codex and OpenCode use `.agents/skills/` natively. Create or update exactly one Claude wrapper at `.claude/commands/<name>.md`:

```markdown
---
description: <exact canonical description>
---

Read .agents/skills/<name>/SKILL.md completely, resolve every relative resource from that skill directory, and follow it as authoritative before acting.
```

Do not copy the skill body into the wrapper. A description change updates the wrapper; a rename or removal renames or removes the matching wrapper and leaves no stale adapter.

For an agent, keep exactly one adapter in each of `.codex/agents/`, `.claude/agents/`, and `.opencode/agents/`. Each adapter contains only native identity, mode, tool/permission metadata, and this route:

```text
Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/<name>.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
```

Use an existing adapter from the same harness as the schema example. Translate canonical capabilities and denies into that harness's strongest native controls; do not copy the canonical prompt, pin a provider model, append instructions, or omit a restriction. If a new semantic capability has no validated mapping, extend the convention, Badakmini schema, Gherkin, and fixtures before claiming parity.

For a required MCP capability, update every owned declaration together:

- Codex: `.codex/config.toml`;
- Claude Code: `.mcp.json`; and
- OpenCode: `opencode.json`.

Compare executable vectors and workspace behaviour, not vendor syntax. Never commit credentials or populated environment values. Adding or removing a required capability also requires validator, specification, and fixture changes.

### 3. Update enforcement when the contract shape changes

A content-only change that retains names, descriptions, routes, semantics, and native schemas needs no validator code change. Badakmini reads and hashes the canonical content dynamically.

When topology, accepted frontmatter, semantic capability mappings, native schema, finding behaviour, or capability declarations change:

1. update the affected Gherkin scenarios and shared bindings;
2. implement every unit, integration, and E2E driver member;
3. prove the new scenario red through Nx;
4. change Badakmini at the narrowest responsible layer; and
5. update the Badakmini C4 specification and project README when responsibility or public behaviour changes.

### 4. Verify

Always run the deterministic repository gate uncached:

```sh
./hippo run --class ephemeral -- npm exec -- nx run -p badakmini-cli -t test:repo --skipNxCache
```

If Badakmini source, specifications, bindings, drivers, project configuration, or the push hook changed, also run the affected `test:quick`, coverage, and E2E targets required by the repository quality gates. Review findings by field and path; matching counts alone are not proof.

## Recovery

Never weaken the validator or adapter restrictions merely to make the gate pass. Restore the missing canonical route or adapter, correct the native semantic mapping, and rerun verification. If a harness cannot express or provide a required capability, stop and document the capability gap; do not claim three-harness parity until the contract or supported-harness set is explicitly changed.

## Outcome

The change is complete only when one canonical source remains, all required adapters are current, no stale or extra source exists, deterministic content and semantic checks pass, relevant runtime discovery is still honest, and the diff contains no local or sensitive data.
