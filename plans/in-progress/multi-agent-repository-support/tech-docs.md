# Technical Design

## Decision Summary

The repository will support Codex, Claude Code, and OpenCode through one canonical repository contract plus the smallest required adapters. Badakmini will validate the committed topology and content relationships without generating files or launching any harness.

“Same” means the same repository-owned instructions, skill workflows, custom-agent intent, safety rules, deterministic Nx routes, and required MCP capability. It does not mean identical vendor system prompts, built-in tools, models, credentials, local memory, plugins, or approval interfaces.

## Current Condition

- Root `AGENTS.md` contains the repository rules consumed by Codex and OpenCode.
- `RTK.md` is worded specifically for Codex even though RTK supports all three harnesses through different integrations.
- Seven canonical skills and their resources live under `.agents/skills/`; Codex and OpenCode discover that location, while Claude Code currently discovers project skills under `.claude/skills/` or legacy commands under `.claude/commands/`.
- `.codex/config.toml` declares `nx-mcp` and the `ci-monitor-subagent`; its agent prompt lives in `.codex/agents/ci-monitor-subagent.toml`. No web-research agent exists in this repository.
- No committed Claude or OpenCode MCP/custom-agent adapter exists.
- Badakmini validates governance Markdown, links, maps, and Mermaid, but not harness-contract parity.
- Local inspection found Codex CLI 0.150.1, Claude Code 2.1.221, and OpenCode 1.18.7 installed; versions are evidence only and will not be pinned by this plan.

## Primary-Source Basis

- OpenAI documents Codex loading repository `AGENTS.md` files from the project root toward the working directory: [Codex agent loop](https://openai.com/index/unrolling-the-codex-agent-loop/).
- Anthropic documents that Claude Code reads `CLAUDE.md`, not `AGENTS.md`, and recommends a root `CLAUDE.md` containing `@AGENTS.md`: [Claude project memory](https://code.claude.com/docs/en/memory).
- OpenCode documents root `AGENTS.md` as its project rule file and gives it precedence over the Claude fallback: [OpenCode rules](https://opencode.ai/docs/rules).
- OpenCode and Codex discover `.agents/skills/`, while current Claude Code documents `.claude/skills/` and compatible `.claude/commands/`: [OpenCode skills](https://opencode.ai/docs/skills) and [Claude skills](https://code.claude.com/docs/en/slash-commands).
- Claude and OpenCode both support committed local MCP declarations, but use different JSON shapes: [Claude MCP](https://code.claude.com/docs/en/mcp) and [OpenCode MCP](https://opencode.ai/docs/mcp-servers/).
- RTK documents distinct Claude, Codex, and OpenCode integrations: [RTK supported agents](https://github.com/rtk-ai/rtk/blob/develop/docs/guide/getting-started/supported-agents.md).
- Codex, Claude Code, and OpenCode each support project custom agents with harness-native configuration and permission fields: [Codex subagents](https://developers.openai.com/codex/subagents), [Claude custom subagents](https://code.claude.com/docs/en/sub-agents), and [OpenCode agents](https://opencode.ai/docs/agents/).
- OSE Public's `web-researcher` provides the requested quality baseline across [Claude](https://github.com/wahidyankf/ose-public/blob/main/.claude/agents/web/web-researcher.md), [Codex](https://github.com/wahidyankf/ose-public/blob/main/.codex/agents/web-researcher.toml), and [OpenCode](https://github.com/wahidyankf/ose-public/blob/main/.opencode/agents/web-researcher.md): repository-first lookup, primary-source preference, citations, explicit gaps, and read-only execution.

## Canonical Contract and Adapters

| Concern              | Canonical source         | Codex route              | Claude Code route                 | OpenCode route              |
| -------------------- | ------------------------ | ------------------------ | --------------------------------- | --------------------------- |
| Project rules        | `AGENTS.md`              | Native                   | `CLAUDE.md` import                | Native                      |
| Skills               | `.agents/skills/`        | Native                   | Thin `.claude/commands/` wrappers | Native                      |
| Custom agents        | `.agents/agents/`        | `.codex/agents/` wrapper | `.claude/agents/` wrapper         | `.opencode/agents/` wrapper |
| Nx tools             | `npx nx mcp` declaration | `.codex/config.toml`     | `.mcp.json`                       | `opencode.json`             |
| Safety and authority | `AGENTS.md` links        | Shared rules             | Imported rules                    | Shared rules                |
| Nx task behavior     | Resolved Nx targets      | Shared CLI               | Shared CLI                        | Shared CLI                  |
| Repository gates     | Nx plus Husky            | Shared hook              | Shared hook                       | Shared hook                 |
| RTK behavior         | `RTK.md` plus onboarding | Codex integration        | Claude hook                       | OpenCode plugin             |

### Instructions

`CLAUDE.md` must be a regular UTF-8 file whose meaningful content is exactly `@AGENTS.md`. Badakmini may normalize a UTF-8 BOM, CRLF/LF line endings, and surrounding blank lines, but it must reject any additional project instruction. Codex and OpenCode need no instruction copy.

Root `AGENTS.md` will route every harness to the canonical multi-harness convention and contain the short mandatory RTK rule. `RTK.md` will become harness-neutral supporting detail. `CLAUDE.local.md` remains ignored and outside the committed parity guarantee.

The initial contract permits only the root `AGENTS.md`. Nested `AGENTS.md`, `AGENTS.override.md`, additional `CLAUDE.md`, and `.claude/rules/**/*.md` are rejected because Claude would not receive an equivalent route. A later need for scoped rules must first extend the convention and validator.

OpenCode config may contain MCP and other non-instruction settings, but any repository `opencode.json` or `opencode.jsonc` with a non-empty `instructions` array is rejected. V1 would append those instructions while V2 currently retains but does not resolve them, creating version-dependent behavior.

### Skills

`.agents/skills/<name>/SKILL.md` remains the only full workflow body. Badakmini will validate the common Agent Skills subset already used by the repository: required `name` and `description`, kebab-case directory/name equality, unique names, nonempty body, and repository-contained supporting links or relative paths selected by the skill.

Claude adapters will use `.claude/commands/<name>.md` because current Claude treats commands as the same reusable-prompt mechanism, while OpenCode does not discover that directory as an additional skill source. Each wrapper has only `description` frontmatter followed by: `Read .agents/skills/<name>/SKILL.md completely, resolve every relative resource from that skill directory, and follow it as authoritative before acting.` Badakmini normalizes line endings and surrounding blank lines, requires the wrapper description to equal the canonical description, requires a one-to-one skill/wrapper set, and rejects copied workflow bodies, missing wrappers, stale wrappers, and extras.

### Custom Agents

`.agents/agents/*.md` becomes the only full custom-agent prompt source. Each file has a small validated frontmatter contract: `name`, `description`, `mode: subagent`, required semantic capabilities, denied semantic capabilities, and a nonempty prompt body. Codex, Claude, and OpenCode agent files contain only native discovery/permission metadata plus a fixed instruction to read the canonical file completely before acting.

The canonical schema is deliberately smaller than any vendor schema:

```yaml
---
name: web-researcher
description: Research current or uncertain facts and return cited findings.
mode: subagent
requires:
  - repository-read
  - web-search
  - web-fetch
denies:
  - repository-write
  - shell
  - nested-agent
constraints:
  - inline-result-only
---
```

Badakmini accepts only known kebab-case capability and constraint values, rejects duplicates and unknown keys, requires the file stem to equal `name`, and treats list order as insignificant after ordinal sorting. The prompt body follows the frontmatter and is authoritative; adapters may not copy or extend it.

The initial set contains exactly two agents:

- `ci-monitor-subagent` moves its existing prompt into the canonical directory. It requires `nx-mcp`, permits exactly one CI MCP operation per invocation, and returns the result without unrelated work.
- `web-researcher` adapts the OSE Public pattern to Beaver Nest without importing OSE-only skills or governance links. Its canonical body requires repository-first lookup; broad-to-focused search; official or primary sources before secondary sources; dates or versions for fast-moving claims; citations adjacent to claims; explicit conflicts, gaps, and uncertainty; a concise structured result; no report file; and no edits.

The web researcher declares `repository-read`, `web-search`, and `web-fetch` as required capabilities and denies `repository-write`, `shell`, and `nested-agent`. Claude receives a `tools` allowlist, OpenCode receives explicit permission allow/deny entries, and Codex receives `sandbox_mode = "read-only"` plus the canonical constraints. Harness-selected model/provider fields are omitted or inherited: quality parity is grounded in the workflow and evidence contract, not an assertion that different models are identical.

Every adapter body normalizes to exactly this route, substituting only the name: `Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/<name>.md and follow it as authoritative. If it cannot be read, stop and report the missing path.` No adapter may append workflow instructions. The owned native mappings are:

| Semantic constraint  | Codex                               | Claude Code           | OpenCode                 |
| -------------------- | ----------------------------------- | --------------------- | ------------------------ |
| Project subagent     | registered project TOML             | `mode`/project agent  | `mode: subagent`         |
| Repository read      | inherited read tools                | `Read, Glob, Grep`    | read/glob/grep allow     |
| Web research         | inherited web tools; smoke required | `WebSearch, WebFetch` | websearch/webfetch allow |
| No repository writes | `sandbox_mode = "read-only"`        | no Write/Edit tools   | edit deny                |
| No shell             | canonical prompt; smoke required    | no Bash tool          | bash deny                |
| No nested agent      | canonical prompt; smoke required    | no Agent tool         | task deny                |

The canonical prompt says to stop with a capability gap instead of answering from memory when web search or fetch is unavailable. Badakmini validates every static field above and the exact route; the Phase 4 smoke owns runtime-only inherited capability checks. This is the narrowest honest equality claim available across the three current schemas.

Badakmini scans `.agents/agents/*.md`, requires unique names, and checks a one-to-one adapter in all three harness directories. It validates identity, description, canonical path, subagent mode, semantic capability mapping, and agent-specific invariants. For `web-researcher`, the invariant is the required/denied capability set and exact canonical route; for `ci-monitor-subagent`, it is `nx-mcp` plus the single-MCP-call constraint. It ignores vendor-only model, effort, and cosmetic fields, but fails if an adapter weakens a native permission that the plan requires. Model fields must be absent or use the harness's documented inherit value; hard-coded provider/model identifiers fail because they create a fourth, non-portable parity dimension.

### Required Capability

The current required MCP set contains only `nx-mcp`, expressed canonically as executable vector `npx nx mcp` with the repository root as working directory and no environment values. Badakmini checks the equivalent committed subset in:

- `.codex/config.toml`: `[mcp_servers.nx-mcp]`, `command = "npx"`, `args = ["nx", "mcp"]`;
- `.mcp.json`: `mcpServers.nx-mcp.command` and `args`; and
- `opencode.json`: `mcp.nx-mcp.type = "local"` and `command = ["npx", "nx", "mcp"]`.

Parsing stays narrow: built-in JSON/JSONC parsing plus a minimal section/key reader for the owned Codex TOML subset. No general TOML or vendor-schema library is added. Unknown unrelated settings pass; malformed inspected sections fail closed because parity cannot be proven.

RTK is an installation prerequisite rather than a committed MCP capability. The how-to guide will use the official per-harness `rtk init` commands and `rtk init --show`; Badakmini validates the repository rule and docs, not user-global hook/plugin state.

## Badakmini Validator

Add this public leaf:

```text
badakmini-cli governance harness-contract validate [--root <path>]
```

The inspection is read-only, network-free, process-free, and deterministic. It uses the injected filesystem boundary, skips generated/vendor/cache/worktree directories and filesystem links, sorts all paths and findings ordinally, and never reads outside the requested root.

The JSON success shape has `schemaVersion`, `command`, `harnessCount`, `skillCount`, `agentCount`, `capabilityCount`, and `violations`. The repository fixture expects `harnessCount = 3`, `skillCount = 7`, `agentCount = 2`, and `capabilityCount = 1`; generic test fixtures derive their counts from their canonical trees. Findings identify `kind`, `path`, optional `relatedPath`, optional `harness`, optional `name`, and `message`. Text output uses the atomic `[harness-contract]` prefix.

Minimum finding kinds are missing canonical source, invalid instruction adapter, unexpected instruction source, invalid skill, missing/stale/unexpected skill adapter, invalid agent, missing/stale/unexpected agent adapter, missing/divergent capability, and unreadable harness config. Exit codes retain Badakmini's `0`/`1`/`2` contract.

`test:repo` will run the leaf beside existing validators. Its Nx inputs and `.husky/pre-push` path selection must include `.agents/**`, `.codex/**`, `.claude/**`, `.opencode/**`, `.mcp.json`, `CLAUDE.md`, `opencode.json`, and `opencode.jsonc` so cache or hook selection cannot hide drift.

## Verification Strategy

1. Add canonical Gherkin and thin shared bindings first; implement every new driver member in unit, integration, and E2E adapters.
2. Prove Nx red for the new scenarios before production implementation.
3. Unit-test normalized content, sorted findings, exclusions, JSONC, minimal TOML sections, and exact adapter reconciliation using the in-memory filesystem.
4. Integration-test real temporary files without network or child processes.
5. E2E-test the built CLI's text/JSON shape, exit codes, and read-only filesystem behavior.
6. Run `test:coverage:behaviour`, unit/integration coverage, `test:quick`, focused E2E, and `test:repo` through Nx.
7. Manually start each already-authenticated harness only for a read-only discovery smoke: inspect instructions, skills, both custom agents, Nx MCP, and the effective web-researcher restrictions. Record pass/fail without prompts, credentials, paths, session content, or model output. If authentication or a required web capability is unavailable, the implementation remains unaccepted rather than weakening deterministic checks.

## Specification Changes

PRD outcomes AC-01–AC-06 become durable Badakmini contracts. AC-07 remains plan-only documentation acceptance, proved by Delivery Phase 4.

### [N] `specs/apps/badakmini/cli/behaviours/harness-contract.feature`

```diff
+ Feature: Repository coding-harness contract
+ Scenario: Canonical instructions, skills, agents, and Nx capability pass
+ Scenario: Claude imports only the canonical AGENTS file
+ Scenario: Additional or nested instruction sources fail
+ Scenario: Every canonical skill has exactly one thin Claude adapter
+ Scenario: Malformed or duplicated canonical skills fail
+ Scenario: Every canonical custom agent has three equivalent adapters
+ Scenario: Missing, stale, or extra custom-agent adapters fail
+ Scenario: Web researcher adapters preserve source and read-only constraints
+ Scenario: Equivalent Nx MCP declarations pass in all harness configs
+ Scenario: Divergent or unreadable harness capability config fails closed
+ Scenario: Inspection excludes generated trees, local overrides, and links
+ Scenario: Findings are stable, sorted, and inspection is read-only
```

- `= Preserve` every existing Badakmini scenario and validator.
- `→ Bindings` update `apps/badakmini-cli/tests/contract/BehaviourContract.fs`, `BehaviourSteps.fs`, and `BehaviourSupport.fs`; update `tests/unit/UnitDriver.fs`, `tests/integration/IntegrationDriver.fs`, and `apps/badakmini-cli-e2e/E2eDriver.fs`.
- `✓ Proof` run `npm exec -- nx run -p badakmini-cli -t test:coverage:behaviour` and `npm exec -- nx run -p badakmini-cli-e2e -t test:e2e`.

### [E] `specs/apps/badakmini/cli/behaviours/cli-contract.feature`

```diff
- The command matrix and isolated validator checks omit harness-contract.
+ The command matrix, help, recursive options, prefixes, JSON, failures, and isolation include harness-contract.
```

- `= Preserve` existing command names, output formats, and exit meanings.
- `→ Bindings` reuse the shared CLI invocation steps and extend driver validator routing.
- `✓ Proof` run Badakmini unit, integration, and process E2E scenarios.

### [E] `specs/apps/badakmini/cli/architecture.md`

```diff
- Governance inspection covers Markdown structure, links, budgets, and Mermaid.
+ Governance inspection also reconciles repository-owned harness contracts through the same read-only filesystem boundary.
```

- `= Preserve` one local CLI container, no network, no repository writes, and existing component boundaries.
- `✓ Proof` review all C4 views and update only component responsibility and architectural constraints; no new container is introduced.

## File Impact

### Repository contract and guidance

- `[E] AGENTS.md` — route all supported harnesses to the canonical convention and shared RTK requirement.
- `[N] CLAUDE.md` — import only `AGENTS.md`.
- `[E] RTK.md` — make instructions harness-neutral and list supported integration modes.
- `[E] .gitignore` — ignore `CLAUDE.local.md` while retaining existing local Claude ignores.
- `[E] README.md` — document supported coding harnesses and link the how-to guide.
- `[N] docs/how-to-guides/coding-harnesses.md` — install, trust, RTK, discovery, and safe smoke steps.
- `[E] docs/how-to-guides/README.md` — map the new guide.
- `[N] repo-governance/conventions/coding-harness-contract.md` — own parity scope, canonical sources, adapters, and exclusions.
- `[E] repo-governance/conventions/README.md` — map the new convention.

### Canonical agent and harness adapters

- `[N] .agents/agents/ci-monitor-subagent.md` — canonical custom-agent intent.
- `[N] .agents/agents/web-researcher.md` — canonical repository-first, source-grounded, read-only research workflow.
- `[E] .codex/agents/ci-monitor-subagent.toml` — reduce to a Codex adapter.
- `[N] .codex/agents/web-researcher.toml` — Codex read-only web-research adapter.
- `[E] .codex/config.toml` — preserve Codex Nx MCP and register both canonical agents.
- `[N] .mcp.json` — declare Claude's equivalent Nx MCP server.
- `[N] .claude/agents/ci-monitor-subagent.md` — Claude custom-agent adapter.
- `[N] .claude/agents/web-researcher.md` — Claude read-only web-research adapter.
- `[N] .claude/commands/link-workspace-packages.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/monitor-ci.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/nx-generate.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/nx-import.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/nx-plugins.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/nx-run-tasks.md` — Claude wrapper for the canonical skill.
- `[N] .claude/commands/nx-workspace.md` — Claude wrapper for the canonical skill.
- `[N] opencode.json` — declare only OpenCode Nx MCP configuration; no extra instructions.
- `[N] .opencode/agents/ci-monitor-subagent.md` — OpenCode custom-agent adapter.
- `[N] .opencode/agents/web-researcher.md` — OpenCode read-only web-research adapter.

### Badakmini implementation and tests

- `[E] apps/badakmini-cli/Governance.fs` — add contract models, parsers, reconciliation, findings, and formatting.
- `[E] apps/badakmini-cli/Cli.fs` — expose text/JSON command behavior.
- `[E] apps/badakmini-cli/project.json` — add `test:repo` invocation and complete cache inputs.
- `[E] apps/badakmini-cli/README.md` — document scope, command, output, and tests.
- `[E] apps/badakmini-cli/tests/contract/BehaviourContract.fs` — add driver operations and scenario state.
- `[E] apps/badakmini-cli/tests/contract/BehaviourSteps.fs` — bind the new feature.
- `[E] apps/badakmini-cli/tests/contract/BehaviourSupport.fs` — own shared fixtures and assertions.
- `[E] apps/badakmini-cli/tests/contract/CliContractTests.fs` — cover JSON shapes and operational failures.
- `[E] apps/badakmini-cli/tests/unit/UnitDriver.fs` — implement fake-only inspection.
- `[E] apps/badakmini-cli/tests/integration/IntegrationDriver.fs` — implement real-local inspection.
- `[E] apps/badakmini-cli/tests/integration/IntegrationPolicyTests.fs` — retain and expand no-network/no-process source policy if new parser sources require it.
- `[E] apps/badakmini-cli-e2e/E2eDriver.fs` — translate public JSON findings for process scenarios.
- `[E] specs/apps/badakmini/cli/architecture.md` — update inspection responsibility.
- `[N] specs/apps/badakmini/cli/behaviours/harness-contract.feature` — specify parity behavior.
- `[E] specs/apps/badakmini/cli/behaviours/cli-contract.feature` — extend the public command matrix.
- `[E] specs/apps/badakmini/cli/behaviours/README.md` — map the new feature.
- `[E] .husky/pre-push` — select every harness-contract path for repository validation.

### Planning records created by this request

- `[E] plans/in-progress/README.md` — map the active plan.
- `[N] plans/in-progress/multi-agent-repository-support/README.md` — plan entry point.
- `[N] plans/in-progress/multi-agent-repository-support/brd.md` — business requirements.
- `[N] plans/in-progress/multi-agent-repository-support/prd.md` — product requirements.
- `[N] plans/in-progress/multi-agent-repository-support/tech-docs.md` — technical design.
- `[N] plans/in-progress/multi-agent-repository-support/delivery.md` — implementation checklist.
- `[N] plans/in-progress/multi-agent-repository-support/learnings.md` — evidence log.

No Bnest source, Bnest specification, dependency lockfile, provider credential, runtime data, or deployment file is expected to change.
