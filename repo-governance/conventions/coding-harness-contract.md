# Coding-Harness Contract

Codex, Claude Code, and OpenCode must receive the same repository-owned rules, skill workflows, custom-agent intent, safety constraints, deterministic Nx task routes, and required MCP capabilities. Vendor system prompts, built-in tools, models, credentials, local memory, plugins, and approval interfaces are outside this equality claim.

Matching file names, paths, or counts is not sufficient. Parity means that each harness reaches the same effective canonical content and that every native adapter preserves the canonical semantics without adding instructions or weakening restrictions.

## Required Parity

| Concern               | Requirement                                                                                                    | Deterministic proof                                                                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rules                 | Every harness reaches the normalized root `AGENTS.md` body and no additional always-on repository instruction. | Exact Claude import, canonical-content digest, and rejection of competing instruction sources.                                                                      |
| Skills                | Every canonical skill, including its complete supporting-resource bundle, is available in all three harnesses. | One-to-one adapter coverage where required, exact description and route, and a digest of `SKILL.md` plus every supporting file.                                     |
| Agents                | Every canonical agent is available in all three harnesses with the same prompt intent and safety boundary.     | One-to-one native adapter coverage, exact canonical route, prompt digest, and equivalent identity, mode, capabilities, denies, constraints, and native permissions. |
| Required capabilities | Every harness declares the same credential-free repository capability.                                         | Semantic comparison of the executable vector and working-directory behavior rather than raw vendor syntax.                                                          |

An adapter fails parity when it is missing, stale, extra, malformed, routes to the wrong canonical source, copies or extends canonical instructions, changes effective content, or weakens a required capability or deny. Adding, renaming, changing, or removing a canonical skill or agent therefore requires all affected harness adapters and deterministic fixtures in the same change.

Follow the [coding-harness contract change workflow](../workflows/coding-harness-contract-change.md) for the canonical edit, adapter reconciliation, enforcement impact, verification, and recovery procedure.

## Canonical Sources

- `AGENTS.md` is the only project-rule body. Root `CLAUDE.md` must contain only `@AGENTS.md` apart from a UTF-8 BOM, line-ending differences, or surrounding blank lines.
- `.agents/skills/<name>/SKILL.md` and every regular supporting file below that skill directory form one canonical skill bundle.
- `.agents/agents/<name>.md` is the only full custom-agent prompt and semantic capability source.
- The required committed MCP capability is the credential-free `npx nx mcp` executable vector rooted at the workspace.

Adapters must route to these sources without copying, extending, or weakening them. Claude command wrappers mirror each canonical skill description and contain only the fixed canonical route. Each canonical custom agent has exactly one native adapter in `.codex/agents/`, `.claude/agents/`, and `.opencode/agents/`.

## Instruction Boundary

The initial contract permits only root `AGENTS.md` and its exact Claude import. Nested `AGENTS.md`, `AGENTS.override.md`, additional `CLAUDE.md`, `.claude/rules/**/*.md`, and nonempty OpenCode `instructions` arrays are prohibited until the contract explicitly defines equivalent routing.

`CLAUDE.local.md`, user-global configuration, vendor caches, generated trees, worktrees, links, credentials, and runtime data are local concerns and do not enter parity inspection.

## Deterministic Enforcement

Run `apps/resource-guard/resource-guard run --class ephemeral -- npm exec -- nx run -p badakmini-cli -t test:repo --skipNxCache` to reconcile effective content. The harness-contract validator is read-only, network-free, process-free, path-contained, and deterministic. It normalizes only a UTF-8 BOM and CRLF/LF, sorts records ordinally, hashes canonical content with SHA-256, and fails on missing, extra, stale, malformed, content-divergent, or semantically weaker adapters.

Runtime discovery smoke checks remain separate because a deterministic repository validator cannot prove vendor model compliance or locally available tools.

Use the [coding-harness parity verification workflow](../workflows/coding-harness-parity-verification.md) to record an evidence-backed audit without changing the contract.
