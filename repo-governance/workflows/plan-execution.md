# Plan Execution

Use only after explicit direction to execute one formal plan. Keep its records truthful.

## Start

1. Select one backlog or in-progress plan and repair it through the [quality gate](plan-quality-gate.md).
2. If backlogged, move it with status and stage maps to `plans/in-progress/<slug>/`; never copy it.
3. Read `learnings.md`. Mirror each unchecked executable delivery item into the task list with wording, label, order, and references. Keep conditional recovery dormant until triggered.
4. Detect affected active services. Apply [live-service continuity](../development/live-service-continuity.md), baseline local/routed health and responsiveness against the plan's numeric budget, and activate continuity/rollback work before editing. For Bnest deployments, use the [Caddy workflow](development-caddy-deployment.md): preserve the stable route, continuously monitor the exact routed origin, prepare an independent revision-verified candidate, promote through Caddy, prove routed LiveView/WebSocket reconnect, then retire only after the bounded drain and responsiveness proof. Do not treat a browser refresh or Tailscale repoint as a normal-release recovery path.

## Execute

1. Work in order with one active item unless genuinely parallel. Stay authorized, stop at pending `[HUMAN]` input, and pass every phase checkpoint.
2. Update delivery at start, material progress, and completion. Check an item only after outcome and proof pass; add dated notes.
3. Synchronize both lists and activate triggered conditionals. Add discoveries to both only for an existing outcome; label and explain them.
4. Capture learnings. Search `plans/ideas/`; merge overlap or create one distinct mapped brief and link it.
5. Run required automation and manual AI journeys. For UI work, execute the planned exact-origin route/state/viewport matrix after implementation and record each pass/fail; inference and automation cannot replace it. Record safe evidence without secrets or sensitive runtime data.
6. Apply all applicable rules; plans and task lists expand no authority.
7. A degraded endpoint, exceeded routed-responsiveness budget, or incomplete cutover stops the line. Restore and verify the usable local/routed journey and its numeric budget, update delivery/learnings, then resume.

## Complete and Archive

1. Re-run the quality gate from step one. Reconcile all items, criteria, learnings, specifications, documentation, rules, and tests with delivery.
2. After any required drain, stop every unneeded non-production server, watcher, candidate, and temporary proxy; retain only the active route and intentional rollback capacity. Record proof or stay in progress.
3. Give dormant conditionals a dated, evidenced `Not triggered`; never claim execution. Stay in progress while any required outcome, activated conditional, gate, dependency, or human action remains.
4. Use the final-checkpoint local date for README `Completed` and `plans/done/YYYY-MM-DD__<slug>/`. Refuse an existing destination; never merge, overwrite, or add a suffix.
5. Together set Done, record outcomes/proof/deviations, and move the folder with stage maps while preserving delivery history. This completes the archival item.
6. Confirm one destination, no source, and no active old-path references. Resolve archived links/maps directly, then verify the repository and diff.
7. When authorized, commit move, metadata, maps, and archive record together. Commit/push needs separate authorization. Complete the environment list only after verification.

## Recovery

Leave interrupted work accurately in progress and resume after the quality gate. If archival verification fails, restore folder, status, and maps. Never leave split copies or archive incomplete work.
