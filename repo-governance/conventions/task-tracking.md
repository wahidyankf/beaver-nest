# Task Tracking

Represent repository work as a granular task list or to-do list, and keep that list synchronized with the actual state of the work.

## Requirements

- Create or refresh the task list before beginning execution.
- Split work into small, concrete items with one observable outcome each. An item should be independently actionable and verifiable; split it again when it combines distinct actions or outcomes.
- For new or changed application/library behaviour and bug fixes, represent each [red–green–refactor](../workflows/quality/red-green-refactor.md) increment as separate RED, GREEN, and REFACTOR items. Preserve the test path and Nx target, the expected behavioural RED reason before production implementation, and the final GREEN and REFACTOR-green results. Pure refactors follow the green-baseline and characterization rule in [TDD](../development/test-driven-development.md).
- Include discovery, implementation, validation, documentation, and delivery items when they are part of the requested scope. Do not hide required work inside a broad item.
- Record each item as pending, in progress, completed, or blocked. Keep at most one item in progress unless work is genuinely proceeding in parallel.
- Update status promptly whenever work starts, completes, becomes blocked, or returns for revision. Add, remove, split, merge, or reorder items when understanding or scope changes.
- Mark an item completed only after its stated outcome is achieved and any item-specific verification succeeds.
- Before reporting completion, reconcile the entire list with the repository state. Complete remaining items or clearly report what remains and why.
- Preserve the current list and its accurate status across context compaction or handoff under the [governance-continuity principle](../principles/governance-continuity.md).

## Written Progress Record

Plan-mediated work records its progress in the plan's `delivery.md`, under the [delivery contract](plans/004-delivery-contract.md#single-progress-surface). Outside plan-mediated work, a progress file in `local-tmp/` is the written progress record. Open it before the task's first action, record the goal, every active rule decision, and each item with its status, and update it as items resolve, so a session that breaks off resumes from it. It stays until the whole task has ended, delivery and cleanup in every repository included, and is then removed under [dev artifact clean-up](../workflows/maintenance/dev-artifact-clean-up.md).

## Delegated-Agent Concurrency

At most 3 delegated agents run at once; the main thread is the `+1` and takes no slot. The count covers every delegated agent alive in the session, foreground or background, at any depth: an agent that a delegated agent spawns takes a slot of its own. It binds in every harness whose session can spawn delegated agents, whatever that harness calls them, including Claude Code's `Agent` tool, Codex spawned agents, and OpenCode's `task` tool. Work beyond the cap waits until a running agent returns; it is never launched over the cap. Only a plan or the user changes the cap.

Both rules are unenforced by tooling, by decision: the user declined hooks and harness settings for them, so review verifies them.

## New Direction Mid-Task

New, follow-on, or changed direction reaches the list before it reaches the work. Read it against every open item first: some are now wrong, some are superseded, some are unaffected, and the new direction is usually more than one item. Record that reconciliation, then continue.

Acting first and updating afterwards produces a list describing the task as it was requested rather than as it is being performed, which is the state the list exists to prevent. The reconciliation is also where a contradiction between old and new direction becomes visible; carrying both silently resolves it by accident.

## Concurrent Ownership

At any time, parallel tasks may create, update, move, or delete artifacts under `plans/`, change repository rules, or modify `repo-governance/`. Before relying on or editing those areas, refresh their state. Treat unfamiliar concurrent changes as expected work owned by another task; preserve and reconcile around them rather than reverting, overwriting, or treating them as an error.

Use the environment's task or plan mechanism when available; otherwise maintain a visible written checklist. A task list records intended work but does not grant authorization for commits, pushes, or other actions governed by the [commit-authorization convention](commit-authorization.md).
