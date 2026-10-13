# Complete and Archive

1. Run the [execution check](plan-execution-check.md) once every substantive item is terminal and require its verdict to
   permit archival. Never re-run the quality gate here. Reconcile all items, criteria, learnings, specifications, documentation, rules, and tests
   with delivery.
2. After any required drain, stop every unneeded non-production server, watcher, candidate, and temporary proxy; retain
   only the active route and intentional rollback capacity. Record proof or stay in progress.
3. Tear down what the plan created here under the [integration path](../../conventions/integration-path.md): remove its
   worktree, delete its local branch, and delete that branch on `origin`. Wait until every delivery unit that used the
   worktree has landed; a `partial` or failed run retains them and records why. Record proof of each removal.
4. Give dormant conditionals a dated, evidenced `Not triggered`; never claim execution. Stay in progress while any
   required outcome, activated conditional, gate, dependency, or human action remains.
5. Run the archival transaction the
   [plans convention](../../conventions/plans/008-knowledge-capture-and-archival.md) fixes, dated from the final-checkpoint
   local date. Set README `Completed` and Done, record outcomes, proof, and deviations, and move the folder with its
   stage maps in one step, then verify links and maps with the repository gate.
6. When authorized, commit the move, metadata, maps, and archive record together. Commit and push need separate
   authorization. Complete the environment list only after verification.
