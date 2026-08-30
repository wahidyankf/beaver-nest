# Task Tracking

Represent repository work as a granular task list or to-do list, and keep that list synchronized with the actual state of the work.

## Requirements

- Create or refresh the task list before beginning execution.
- Split work into small, concrete items with one observable outcome each. An item should be independently actionable and verifiable; split it again when it combines distinct actions or outcomes.
- Include discovery, implementation, validation, documentation, and delivery items when they are part of the requested scope. Do not hide required work inside a broad item.
- Record each item as pending, in progress, completed, or blocked. Keep at most one item in progress unless work is genuinely proceeding in parallel.
- Update status promptly whenever work starts, completes, becomes blocked, or returns for revision. Add, remove, split, merge, or reorder items when understanding or scope changes.
- Mark an item completed only after its stated outcome is achieved and any item-specific verification succeeds.
- Before reporting completion, reconcile the entire list with the repository state. Complete remaining items or clearly report what remains and why.
- Preserve the current list and its accurate status across context compaction or handoff under the [governance-continuity principle](../principles/governance-continuity.md).

## Concurrent Ownership

At any time, parallel tasks may create, update, move, or delete artifacts under `plans/`, change repository rules, or modify `repo-governance/`. Before relying on or editing those areas, refresh their state. Treat unfamiliar concurrent changes as expected work owned by another task; preserve and reconcile around them rather than reverting, overwriting, or treating them as an error.

Use the environment's task or plan mechanism when available; otherwise maintain a visible written checklist. A task list records intended work but does not grant authorization for commits, pushes, or other actions governed by the [commit-authorization convention](commit-authorization.md).
