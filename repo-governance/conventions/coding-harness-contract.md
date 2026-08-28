# Coding-Harness Contract

Codex, Claude Code, and OpenCode must receive the same repository-owned rules, skill workflows, custom-agent intent, safety constraints, deterministic Nx task routes, and required MCP capabilities. Vendor system prompts, built-in tools, models, credentials, local memory, plugins, and approval interfaces are outside this equality claim.

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

Run `npm exec -- nx run badakmini-cli:test:repo --skipNxCache` to reconcile effective content. The harness-contract validator is read-only, network-free, process-free, path-contained, and deterministic. It normalizes only a UTF-8 BOM and CRLF/LF, sorts records ordinally, hashes canonical content with SHA-256, and fails on missing, extra, stale, malformed, or semantically weaker adapters.

Runtime discovery smoke checks remain separate because a deterministic repository validator cannot prove vendor model compliance or locally available tools.
