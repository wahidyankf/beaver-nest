# Governance Continuity

Context compaction, summarization, or handoff must preserve the repository's rule-governed behavior. Reducing conversational context must not weaken, omit, reinterpret, or change the scope or precedence of an applicable repository rule.

## Requirements

- Treat applicable repository rules as durable operating state, not expendable conversational detail.
- In a compacted summary or handoff, retain the authoritative rule locations, the mandatory behavior needed to continue faithfully, and any unresolved rule-governed obligations.
- After compaction or when resuming from a handoff, reload the applicable instruction and governance sources before taking further repository action. Reconcile the summary with those sources; the authoritative files prevail.
- Preserve the task state needed to honor the rules, including relevant user authorization, pending verification, and uncommitted or unpushed changes.
- Never treat missing detail in a compacted context as permission to ignore or relax a rule. Recover the detail from its canonical source.

This principle preserves the repository's original governed behavior while allowing context to become smaller. It is subordinate to the repository [vision](../vision/README.md), and every convention, development standard, and workflow must conform to it.
