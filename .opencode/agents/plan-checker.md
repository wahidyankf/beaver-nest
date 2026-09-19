---
description: "Audits a complete plan draft against the plan specification and returns findings with a terminal verdict, without modifying anything."
mode: subagent
permission:
  bash: allow
  edit: deny
  glob: allow
  grep: allow
  read: allow
  task: deny
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/plan-checker.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
