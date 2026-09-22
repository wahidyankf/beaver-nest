---
description: |-
  CI helper for /monitor-ci. Fetches CI status, retrieves fix details, or updates self-healing fixes. Executes one MCP tool call and returns the result.
mode: subagent
permission:
  bash: deny
  edit: deny
  read: allow
  task: deny
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/ci-monitor-subagent.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
