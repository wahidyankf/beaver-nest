---
description: CI helper for /monitor-ci. Fetches CI status, retrieves fix details, or updates self-healing fixes. Executes one MCP tool call and returns the result.
mode: subagent
permission:
  read: allow
  glob: deny
  grep: deny
  list: deny
  edit: deny
  bash: deny
  task: deny
  external_directory: deny
  webfetch: deny
  websearch: deny
  skill: deny
  nx-mcp_*: allow
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/ci-monitor-subagent.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
