---
description: |-
  Repairs an HTTP service from the rows of a frozen API HTTP ledger, re-validating each row by replaying its request, writing the failing test first, and recording every row's status with evidence.
name: api-http-fixer
tools: |-
  Read, Glob, Grep, Write, Edit, Bash
---

Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/api-http-fixer.md and follow it as authoritative. If it cannot be read, stop and report the missing path.
