# Plan Execution

Use only after explicit direction to execute one formal plan. Keep its records truthful.

## Start

1. Select one backlog or in-progress plan. Require a current `PASS` from an explicitly user-directed
   [quality-gate](plan-quality-gate.md) run; execution authority does not authorize that gate. If absent or blocked,
   stop without starting or rerunning it.
2. Enter the plan's declared `worktrees/<name>/` checkout before any file or Git mutation, initializing it if new, and
   pass the [integration path](../conventions/integration-path.md) sync gate there. Executing from a stale branch or the
   primary checkout is forbidden, save the release invocation that convention exempts; an unclean tree or a rebase
   conflict stops the start and goes to the user.
3. If backlogged, move it with status and stage maps to `plans/in-progress/<slug>/`; never copy it.
4. Read all six plan documents before the checklist. Mirror each unchecked executable delivery item into the task list
   with wording, label, order, and references. Keep conditional recovery dormant until triggered.
5. Detect affected active services. Apply [live-service continuity](../development/live-service-continuity.md), baseline
   local and routed health and responsiveness against the plan's numeric budget, and activate continuity and rollback
   work before editing. For Bnest deployments follow the [Caddy workflow](development-caddy-deployment.md) end to end.
   Never treat a browser refresh or a Tailscale repoint as a normal-release recovery path.

## Execute

1. Work in order with one active item unless genuinely parallel. Stay authorized, stop at pending `[HUMAN]` input, and
   pass every phase checkpoint.
2. Resolve each item atomically: tick the checkbox, record the result, and move on, as one step. Check an item only
   after outcome and proof pass; its dated note records what was produced, what changed, and what was surprising.
3. Synchronize both lists and activate triggered conditionals. Add discoveries to both only for an existing outcome;
   label and explain them.
4. Capture learnings. Search `plans/ideas/`; merge overlap or create one distinct mapped brief and link it.
5. Run required automation and manual AI journeys. For UI work, execute the planned exact-origin route, state, and
   viewport matrix after implementation and record each pass or fail; inference cannot replace it. Record
   safe evidence without secrets or sensitive runtime data.
6. Fix what fails, including what was already failing; pre-existing is an explanation, not an exemption.
7. Apply all applicable rules; plans and task lists expand no authority.
8. A degraded endpoint, exceeded routed-responsiveness budget, or incomplete cutover stops the line. Restore and verify
   the usable local and routed journey and its numeric budget, update delivery and learnings, then resume.

## Complete and Archive

1. Run the [execution check](plan-execution-check.md) once every substantive item is terminal and require its verdict to
   permit archival. Require explicit user direction for a fresh completion quality-gate run and continue only on `PASS`;
   never start it from here. Reconcile all items, criteria, learnings, specifications, documentation, rules, and tests
   with delivery.
2. After any required drain, stop every unneeded non-production server, watcher, candidate, and temporary proxy; retain
   only the active route and intentional rollback capacity. Record proof or stay in progress.
3. Tear down what the plan created here under the [integration path](../conventions/integration-path.md): remove its
   worktree, delete its local branch, and delete that branch on `origin`. Wait until every delivery unit that used the
   worktree has landed; a `partial` or failed run retains them and records why. Record proof of each removal.
4. Give dormant conditionals a dated, evidenced `Not triggered`; never claim execution. Stay in progress while any
   required outcome, activated conditional, gate, dependency, or human action remains.
5. Run the archival transaction the
   [plans convention](../conventions/plans/008-knowledge-capture-and-archival.md) fixes, dated from the final-checkpoint
   local date. Set README `Completed` and Done, record outcomes, proof, and deviations, and move the folder with its
   stage maps in one step, then verify links and maps with the repository gate.
6. When authorized, commit the move, metadata, maps, and archive record together. Commit and push need separate
   authorization. Complete the environment list only after verification.

## Pause Safety

Execution stops at arbitrary moments. At any pause the plan carries enough state to resume: the current checkout, the
last terminal gate, the next unresolved item, and any bounded budget already partly consumed. A resumed session
continues a budget; it does not reset one.

## Recovery

Leave interrupted work accurately in progress and resume only after an explicitly directed fresh quality-gate `PASS`. If
archival verification fails, restore folder, status, and maps. Never leave split copies or archive incomplete work.
