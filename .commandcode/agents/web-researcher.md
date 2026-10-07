---
description: Research current or uncertain facts and return cited findings.
disallowedTools: |-
  agent, agent_output, write_file, edit_file, write_file, edit_file
name: web-researcher
tools: |-
  read_file, read_directory, grep, glob, web_search, web_fetch
---

Before acting, read the complete canonical agent definition at the repository-root path
.agents/agents/web-researcher.md and follow it as authoritative.
If it cannot be read, stop and report the missing path.
