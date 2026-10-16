# Plan Execution

Use only after explicit direction to execute one formal plan. Keep its records truthful.

## Start

1. Select one backlog or in-progress plan. A verdict from a manually invoked
   [quality-gate](../quality/plan-quality-gate.md) run, when recorded, is advisory history. Execution starts with or
   without a verdict and never runs the gate itself; a missing verdict is recorded as
   `plan-quality-gate: not run (manual-only)`. Upstream Tool Defects remains available direction for a bug-fix plan
   when explicitly invoked. Before starting, resolve every dependency the plan declares under
   [Plan-Order Graph](../../conventions/plans/012-plan-order-graph.md): each must already be satisfied,
   or the run stops and names the unmet one. A missing declaration reads as no dependencies.
2. Enter the plan's declared `worktrees/<name>/` checkout before any file or Git mutation, initializing it if new, and
   pass the [integration path](../../conventions/integration-path.md) sync gate there. Executing from a stale branch or the
   primary checkout is forbidden, save the release invocation that convention exempts; an unclean tree stops the start
   and goes to the user. Handle rebase conflicts under
   [owned task sync](../../conventions/no-destructive-git-operations/001-authorized-task-branch-sync.md).
3. If backlogged, move it with status and stage maps to `plans/in-progress/<slug>/`; never copy it.
4. Read every plan document before the checklist. Mirror each unchecked executable delivery item into the task list
   with wording, label, references, and dependency-graph order rather than list position, per
   [Dependency Graph and Recovery](../../conventions/plans/011-dependency-graph-and-recovery.md). Keep conditional
   recovery dormant until triggered.
5. Detect affected active services. Apply [live-service continuity](../../development/live-service-continuity.md), baseline
   local and routed health and responsiveness against the plan's numeric budget, and activate continuity and rollback
   work before editing. For Bnest deployments follow the [Caddy workflow](../maintenance/development-caddy-deployment.md) end to end.
   Never treat a browser refresh or a Tailscale repoint as a normal-release recovery path.

## Execute

1. Dispatch every item whose dependencies are terminal, up to the concurrency cap, reusing the plan's one worktree
   per repository; a failure blocks only its downstream. Stay authorized, stop at pending `[HUMAN]` input, and pass
   every phase checkpoint. A more optimal order found mid-run revises `delivery.md` first, keeping acceptance criteria
   and the end result; a material change re-passes the [quality gate](../quality/plan-quality-gate.md).
2. Resolve each item atomically: tick the checkbox, record the result, and move on. Check an item only after outcome
   and proof pass; its dated note records what was produced, what changed, and what was surprising.
3. Synchronize both lists and activate triggered conditionals. Add discoveries to both only for an existing outcome;
   label and explain them.
4. Capture learnings. Search the owning repository's `plans/ideas/`; merge overlap or create one distinct mapped brief
   and link it.
5. Run required automation and manual AI journeys. For UI work, execute the planned exact-origin route, state, and
   viewport matrix after implementation and record each pass or fail; inference cannot replace it. Record
   safe evidence without secrets or sensitive runtime data.
6. Fix what fails, including what was already failing; pre-existing is an explanation, not an exemption.
7. Apply all applicable rules; plans and task lists expand no authority.
8. A degraded endpoint, exceeded routed-responsiveness budget, or incomplete cutover stops the line. Restore and verify
   the usable local and routed journey and its numeric budget, update delivery and learnings, then resume.
9. Land independent delivery units in any order, each refreshed with its gates re-run, per
   [Delivery Seams and Ownership](../../development/planning-capabilities/005-delivery-seams-and-ownership.md).

## Complete and Archive

Complete and archive per [Completion and Archival](plan-execution-completion-and-archival.md).

## Pause Safety

Execution stops at arbitrary moments. At any pause the plan carries enough state to resume: the current checkout, last
terminal gate, next unresolved item, and any partly consumed bounded budget. Resuming continues a budget; it never
resets one.

## Recovery

Leave interrupted work accurately in progress and resume it without a new gate run. If archival verification
fails, restore folder, status, and maps. Never leave split copies or archive incomplete work.
