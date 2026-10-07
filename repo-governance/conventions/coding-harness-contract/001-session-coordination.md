---
description: Command Code projection and coordination boundaries under the coding-harness contract
when_to_use: Use when changing the Command Code profile, its native agent selection, or its local-state boundary.
---

# Session Coordination

The [coding-harness contract](../coding-harness-contract.md) remains authoritative for parity.

Command Code reads root `AGENTS.md`, `.agents/skills/`, and the shared `.mcp.json` natively. The existing `nx-mcp`
entry supplies the credential-free `npx nx mcp` capability; create no duplicate instruction, skill, or MCP bridge.

Select every canonical leaf for `.commandcode/agents/`, excluding exactly roles declaring `subagent` or nonempty
`dispatches`. The main-session role here is `swe-orchestrator`: read its complete canonical definition there and follow
its named dispatch allowlist. This is the exception to native one-adapter-per-role coverage, because native leaves
cannot dispatch another agent. Do not grant `agent` or `agent_output` to leaves.

Omit Command Code tier mappings and model, featureModels, effort, and reasoningEffort pins from profiles, adapters,
settings, shared global sources, and smoke commands. The active session supplies the model; omitted reasoning fields
use the harness default. Preserve every documented native grant and denial. For `ci-monitor-subagent`, the
`single-mcp-operation` constraint grants only `mcp__nx-mcp__ci_information` and
`mcp__nx-mcp__update_self_healing_fix` as MCP tools, with web browsing denied; do not grant a wildcard.

Keep `.commandcode/settings.local.json` and the complete `.commandcode/taste/` tree ignored and local, preserving
contents and active learning. Generation owns only `.commandcode/agents/`, never local state or project settings.

When canonical agents change, update the explicit selection in the same change and audit its equality to canonical
leaves after regeneration. Declared-profile parity verifies native metadata and routes; live discovery, Nx MCP, and
main-session-to-leaf probes verify availability. Semantic main-session compliance remains unenforced by decision:
adapter validation cannot judge model conduct.
