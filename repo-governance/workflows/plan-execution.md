# Plan Execution

Use only after explicit direction to execute one formal plan. It turns the delivery checklist into the task list, keeps progress truthful, and archives only reconciled delivery.

## Start

1. Identify one plan in `plans/backlogs/<slug>/` or `plans/in-progress/<slug>/`. Run the [plan quality gate](plan-quality-gate.md) and repair findings before implementation.
2. If it is in `backlogs/`, move—never copy—it to `plans/in-progress/<slug>/`. Set README status to In progress, move its stage-index entry, and update both maps in the same change.
3. Read its learning-capture approach. Create or refresh the task list with one item for every unchecked executable `delivery.md` checkbox. Preserve wording, `[AI]`/`[HUMAN]`, order, and reference; do not merge or omit.

## Execute

1. Work in task-list order, with one item in progress unless genuinely parallel. Perform `[AI]` only within authority; stop at `[HUMAN]` pending its stated input. Do not start a later phase before the current checkpoint completes.
2. At start, material progress, and completion, update the matching `delivery.md` item. Keep it unchecked until outcome and verification pass; record concise dated notes beneath it.
3. Synchronize task-list and delivery status. Add a discovered task to both only when needed for an existing outcome; label, order, and explain it in `delivery.md`.
4. At each material learning and final reconciliation, update `learnings.md`. Search `plans/ideas/`; merge an overlap or create a distinct brief in the proper quadrant. Update its map and link the destination; do not duplicate ideas.
5. Run specified automated checks and manual AI journey, recording safe evidence only. Never put secrets or sensitive user/runtime data in plan documents, task lists, or test evidence.
6. Apply all applicable development, specification, testing, data-safety, and commit-authorization rules. A plan or task list never expands external authority.

## Complete and Archive

1. Reconcile from the beginning: re-run the [plan quality gate](plan-quality-gate.md), inspect every delivery item and progress note, verify all acceptance criteria, dispose of learnings, and confirm affected C4, Gherkin, READMEs, governance, and tests reflect the delivered system.
2. Do not complete while any task, verification gate, unresolved dependency, or required human action remains open. Report the actual blocker and retain the plan in progress.
3. When complete, set the plan README status to Done and move the folder to `plans/done/YYYY-MM-DD__<slug>/`, using the local completion date. Move, never copy.
4. Remove the plan from the in-progress README, add the dated plan to the done README, and update both directory maps. Preserve its `delivery.md` task history and executor labels as the archive record.
5. Reconcile the environment task list to completed only after the move and repository verification pass.

## Recovery

If execution stops, leave the plan in `in-progress/`, keep every unchecked item and progress note accurate, record the blocking state in `learnings.md`, and resume from the matching task after re-running the quality gate. Never archive an incomplete plan to make the board look clean.
