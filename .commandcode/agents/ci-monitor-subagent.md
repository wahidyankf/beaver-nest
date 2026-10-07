---
description: |-
  CI helper for /monitor-ci. Fetches CI status, retrieves fix details, or updates self-healing fixes. Executes one MCP tool call and returns the result.
disallowedTools: |-
  agent, agent_output, write_file, edit_file, write_file, edit_file, web_search, web_fetch
name: ci-monitor-subagent
tools: |-
  read_file, mcp__nx-mcp__ci_information, mcp__nx-mcp__update_self_healing_fix
---

Before acting, read the complete canonical agent definition at the repository-root path
.agents/agents/ci-monitor-subagent.md and follow it as authoritative.
If it cannot be read, stop and report the missing path.
