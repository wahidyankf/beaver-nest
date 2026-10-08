---
description: Indexes the repository-owned OpenCode policy adapter
when_to_use: Use when locating OpenCode native policy hooks for this checkout
---

# OpenCode Policy Plugin

[`agent-policy.ts`](agent-policy.ts) handles native tool preflight for this physical checkout. It uses the
[shared client](../../scripts/agent-policy-client.ts) and [repository endpoint](../../scripts/agent-policy-hook.sh).
Protected-path data lives in [repository agent policy](../../.agents/agent-policy.json).

Serena registration is deferred in OpenCode. The global adapter routes ordinary operations to other repositories.
