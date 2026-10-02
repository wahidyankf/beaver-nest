---
description: |-
  Audits a running HTTP interface against its contract and behaviour specifications by sending real requests, and returns criticality-rated findings with the request that reproduces each, without modifying anything.
mode: subagent
permission:
  bash: allow
  edit: deny
  glob: allow
  grep: allow
  read: allow
  task: deny
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/api-http-checker.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
