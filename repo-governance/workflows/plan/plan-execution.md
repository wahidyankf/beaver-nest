# Plan Execution

Use only after explicit direction to execute one formal plan. Keep its records truthful.

## Start

1. Select one backlog or in-progress plan. A manually invoked
   [quality-gate](../quality/plan-quality-gate.md) verdict is advisory history when recorded; execution never runs
   the gate; a missing verdict records as `plan-quality-gate: not run (manual-only)`. Upstream Tool Defects stays
   available on explicit bug-fix invocation. Resolve declared dependencies per
   [Plan-Order Graph](../../conventions/plans/012-plan-order-graph.md): each satisfied, or stop, naming the unmet one;
   a mid-run graph change in a reviewed merged PR is authoritative — adapt.
2. Enter the plan's declared `worktrees/<name>/` checkout before any file or Git mutation, initializing if new,
   passing the [integration path](../../conventions/integration-path.md) sync gate there — never a stale branch or the
   primary checkout, save the exempted release invocation; an unclean tree stops it.
   Handle rebase conflicts under
   [owned task sync](../../conventions/no-destructive-git-operations/001-authorized-task-branch-sync.md). Sync from
   latest `origin/main`, then prove access from the plan's scope — least privilege, infra secrets only
   for infra scope, portable versus machine-bound per need; missing access stops it.
3. Promote a backlogged plan by its own pull request moving only it to `plans/in-progress/<slug>/` with status,
   stage maps, graph node, before Phase 0. Worktree from that trunk; the promotion branch dies at merge.
4. Read the plan documents. Mirror each unchecked executable item into the task list — wording, label,
   references, graph order — per
   [Dependency Graph and Recovery](../../conventions/plans/011-dependency-graph-and-recovery.md); conditional recovery
   stays dormant until triggered. Mirror the ledger from ignored `local-tmp/` into one per-run Issue as the claim;
   prove sole ownership via lease, branches, open PRs; stale leases yield only to explicit caller override.
   Inputs: `plan`; caps `max-worktrees-per-plan-repo`, `max-active-worktrees` (`1`, caller-raised only).
5. Detect affected services. Apply [live-service continuity](../../development/live-service-continuity.md):
   baseline local and routed health/responsiveness against the plan's numeric budget; continuity and
   rollback activate before editing. For Bnest deployments, follow the
   [Caddy workflow](../maintenance/development-caddy-deployment.md) throughout — never a browser refresh or Tailscale
   repoint as the recovery path.

## Execute

1. Dispatch dependency-terminal items under the worktree lock: one `in_progress` per worktree, every compute node
   through one guard per [Resource-Aware Development](../../development/resource-aware-development.md) — a deferred
   guard queues: retry, never bypass or abandon. Failures block only downstream. Stay authorized, stop at
   pending `[HUMAN]` input, pass every phase checkpoint. Reorder only by revising `delivery.md`; material
   changes re-pass the quality gate.
2. Resolve each item atomically — tick, record, move on with outcome, proof, never batched ticks. Dated notes
   record product, change, surprise. Ship code in batched cycles — one RED plus one GREEN per batch, selection
   frozen — per [Batched Cycles](../../development/test-driven-development/001-batched-cycles-in-planned-delivery.md).
3. Synchronize both lists, activating conditionals; discoveries join both labelled, only for an existing outcome.
4. Capture learnings: search the owning repository's `plans/ideas/`; merge overlap or link one distinct brief.
5. Run required automation and manual AI journeys. For UI work, execute the exact-origin route, state, and
   viewport matrix after implementation, recording each pass or fail — inference never replaces it. Record only
   safe evidence.
6. Fix every failure, pre-existing included; it explains, never exempts.
7. Apply all applicable rules; plans and task lists expand no authority.
8. A degraded endpoint, exceeded routed-responsiveness budget, or incomplete cutover stops the line. Restore and
   verify the usable local and routed journey and numeric budget, update delivery and learnings, then resume.
9. Land independent delivery units in any order, refreshed with gates re-run, per
   [Delivery Seams and Ownership](../../development/planning-capabilities/005-delivery-seams-and-ownership.md).

## Status Cadence

Heartbeat every **20 minutes**, five lines — progress, steps left, blockers, decisions, next `[HUMAN]` timing
(`delivery.md` weights, else `1`) — plus phase boundaries and terminal states. A queued node is reported, never
a stop. Each heartbeat clears owned subagents and processes of stuck work — `in_progress` with no progress since the
last heartbeat, no guard or error reason: nudge once, escalate on repeat.

## Goal and Termination

`pass` is the only success: terminal items, permitted archival, landed delivery, `done`, worktree/branches
gone, learnings routed. `handed-off`: `[AI]` ready, only `[HUMAN]` remains; resume to `pass`. `partial`: open
findings or unexecuted work stays with blockers and unblockers. `fail`: technical error blocks; both stay.

## Complete and Archive

Complete and archive per [Completion and Archival](plan-execution-completion-and-archival.md).

## Pause Safety

At any pause the plan carries resume state: checkout, last terminal gate, next item, consumed budget.
Resuming continues a budget; it never resets one.

## Recovery

Leave interrupted work in progress; resume without a new gate run. If archival verification fails,
restore folder, status, maps; never split copies or archive incomplete work.
