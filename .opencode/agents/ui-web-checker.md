---
description: |-
  Audits a running web user interface against its specification, adopted design, accessibility beyond what a scanner settles, and first-use usability, and returns criticality-rated findings with reproduction steps, without modifying anything.
mode: subagent
permission:
  bash: allow
  edit: deny
  glob: allow
  grep: allow
  read: allow
  task: deny
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/ui-web-checker.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
