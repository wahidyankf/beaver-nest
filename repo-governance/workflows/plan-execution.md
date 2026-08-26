# Plan Execution

Use only after explicit direction to execute one formal plan. Keep delivery, tasks, evidence, and lifecycle truthful.

## Start

1. Select one plan in `plans/backlogs/<slug>/` or `plans/in-progress/<slug>/`. Run and repair the [plan quality gate](plan-quality-gate.md).
2. If backlogged, move—never copy—it to `plans/in-progress/<slug>/`. Set status to In progress and move its stage index/map entries together.
3. Read `learnings.md`. Create or refresh one task-list item per unchecked required executable `delivery.md` checkbox. Preserve wording, `[AI]`/`[HUMAN]`, order, and references. Keep explicitly conditional recovery/rollback items dormant until triggered.

## Execute

1. Work in order with one item active unless genuinely parallel. Stay within authority, stop at pending `[HUMAN]` input, and pass each phase checkpoint before continuing.
2. Update the matching delivery item at start, material progress, and completion. Keep it unchecked until its outcome and proof pass; add concise dated notes.
3. Synchronize both lists. Activate conditional items when triggered. Add a discovered task to both only for an existing outcome; label and explain it.
4. Capture material and final learnings. Search `plans/ideas/`; merge an overlap or create one distinct brief, update its map, and link the destination.
5. Run specified automation and the manual AI journey. Record only safe evidence; exclude secrets and sensitive user/runtime data.
6. Apply all applicable development, specification, testing, data-safety, and authorization rules. Neither plan nor task list expands authority.

## Complete and Archive

1. Re-run the quality gate from its first step. Reconcile every item, note, acceptance criterion, learning, specification, README, governance change, and test with the delivered system.
2. Give each dormant conditional item a dated, evidenced `Not triggered` disposition; do not claim it ran. Keep the plan in progress while any required outcome, activated conditional, gate, dependency, or human action is open. The move completes the archival item.
3. Use the local date when the final checkpoint passed for README `Completed` and `plans/done/YYYY-MM-DD__<slug>/`. Stop if that destination exists; never merge, overwrite, or invent a suffix.
4. Together, set status Done; record completion, actual outcome/proof, and deviations; move the folder and its stage index/map entries; preserve delivery history and labels.
5. Complete the archival item with its dated destination. Confirm the source is absent, the destination occurs once, and active references avoid the old path.
6. Resolve every archived internal link/map directly because routine link validation excludes archive sources. Run repository verification and inspect the complete diff.
7. Keep move, metadata, indexes, maps, and archive record in one thematic commit when authorized. Commit/push requires its own authorization. Complete the environment task list only after verification.

## Recovery

Before archival, leave interrupted work in progress with accurate items, notes, and blocking learning; resume after the quality gate. If archival verification fails, restore the folder, status, indexes, and maps to in progress. Never leave split copies or archive incomplete work.
