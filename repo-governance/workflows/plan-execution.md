# Plan Execution

Use only after explicit direction to execute one formal plan. Keep its records truthful.

## Start

1. Select one backlog or in-progress plan. Require a current `PASS` from an explicitly user-directed [quality-gate](plan-quality-gate.md) run; execution authority does not authorize that gate. If absent or blocked, stop without starting or rerunning it.
2. Enter the plan's declared `worktrees/<name>/` checkout before any file or Git mutation, initializing it first if it is new. Pass the [integration path](../conventions/integration-path.md) sync gate there: bring the branch up to date with `origin/main`, and review the incoming diff against the plan when the sync adds commits. Executing from a stale branch, or from the primary checkout, is forbidden, the release invocation that convention exempts being the sole exception; an unclean tree or a rebase conflict stops the start and goes to the user.
3. If backlogged, move it with status and stage maps to `plans/in-progress/<slug>/`; never copy it.
4. Read `learnings.md`. Mirror each unchecked executable delivery item into the task list with wording, label, order, and references. Keep conditional recovery dormant until triggered.
5. Detect affected active services. Apply [live-service continuity](../development/live-service-continuity.md), baseline local/routed health and responsiveness against the plan's numeric budget, and activate continuity/rollback work before editing. For Bnest deployments, use the [Caddy workflow](development-caddy-deployment.md): preserve the stable route, continuously monitor the exact routed origin, prepare an independent revision-verified candidate, promote through Caddy, prove routed LiveView/WebSocket reconnect, then retire only after the bounded drain and responsiveness proof. Do not treat a browser refresh or Tailscale repoint as a normal-release recovery path.

## Execute

1. Work in order with one active item unless genuinely parallel. Stay authorized, stop at pending `[HUMAN]` input, and pass every phase checkpoint.
2. Update delivery at start, material progress, and completion. Check an item only after outcome and proof pass; add dated notes.
3. Synchronize both lists and activate triggered conditionals. Add discoveries to both only for an existing outcome; label and explain them.
4. Capture learnings. Search `plans/ideas/`; merge overlap or create one distinct mapped brief and link it.
5. Run required automation and manual AI journeys. For UI work, execute the planned exact-origin route/state/viewport matrix after implementation and record each pass/fail; inference and automation cannot replace it. Record safe evidence without secrets or sensitive runtime data.
6. Apply all applicable rules; plans and task lists expand no authority.
7. A degraded endpoint, exceeded routed-responsiveness budget, or incomplete cutover stops the line. Restore and verify the usable local/routed journey and its numeric budget, update delivery/learnings, then resume.

## Complete and Archive

1. Require explicit user direction for a fresh completion quality-gate run. Continue only on `PASS`; do not start it from this workflow. Reconcile all items, criteria, learnings, specifications, documentation, rules, and tests with delivery.
2. After any required drain, stop every unneeded non-production server, watcher, candidate, and temporary proxy; retain only the active route and intentional rollback capacity. Record proof or stay in progress.
3. Tear down what the plan created in this repository under the [integration path](../conventions/integration-path.md): remove its worktree, delete its local branch, and delete that branch on `origin`. Wait until every delivery unit that used the worktree has landed; a `partial` or failed run retains them and records why. Record proof of each removal.
4. Give dormant conditionals a dated, evidenced `Not triggered`; never claim execution. Stay in progress while any required outcome, activated conditional, gate, dependency, or human action remains.
5. Use the final-checkpoint local date for README `Completed` and `plans/done/YYYY-MM-DD__<slug>/`. Refuse an existing destination; never merge, overwrite, or add a suffix.
6. Together set Done, record outcomes/proof/deviations, and move the folder with stage maps while preserving delivery history. This completes the archival item.
7. Confirm one destination, no source, and no semantically active old-path references; use the repository gate for link/map verification.
8. When authorized, commit move, metadata, maps, and archive record together. Commit/push needs separate authorization. Complete the environment list only after verification.

## Recovery

Leave interrupted work accurately in progress and resume only after an explicitly directed fresh quality-gate `PASS`. If archival verification fails, restore folder, status, and maps. Never leave split copies or archive incomplete work.
