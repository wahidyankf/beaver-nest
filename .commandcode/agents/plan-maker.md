---
description: |-
  Authors a complete formal plan from a request or groomed brief, runs both decision gates, and submits the draft to the plan quality gate, whose findings a separate fixer repairs.
disallowedTools: |-
  agent, agent_output
name: plan-maker
tools: |-
  read_file, read_directory, grep, glob, write_file, edit_file, shell_command, run_command, kill_shell
---

Before acting, read the complete canonical agent definition at the repository-root path
.agents/agents/plan-maker.md and follow it as authoritative.
If it cannot be read, stop and report the missing path.
