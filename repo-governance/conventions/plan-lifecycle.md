# Plan Lifecycle

Plans are temporary. Store each artifact in one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

Create `plans/` documents only on explicit user request. Never infer one from a requested code, specification, or documentation change.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md`. Select `q1-urgent-important`, `q2-not-urgent-important`, `q3-urgent-not-important`, or `q4-not-urgent-not-important` from `Why now` evidence and impact.

Each brief needs a summary and dated provenance, problem/evidence, why now, prior art, direction, scope/non-goals, risks/questions, and success plus a promotion signal. Exclude implementation detail, Gherkin, and delivery checklists. Search and consolidate first.

## Formal Plans

Use `plans/backlogs/<slug>/` for queued work, `plans/in-progress/<slug>/` for active work, and `plans/done/YYYY-MM-DD__<slug>/` for complete work. Use lowercase kebab-case and the completion date prefix.

Every formal plan must contain:

- `README.md`: status, context, scope, approach, dependencies, and navigation;
- `brd.md`: business goal, roles, outcomes, non-goals, and risks;
- `prd.md`: personas, stories, requirements, acceptance criteria, scope, and risks;
- `tech-docs.md`: architecture, schemas, decisions, mechanics, impact, testing, rollback, and risks;
- `delivery.md`: granular ordered checklist, phases, and gates; and
- `learnings.md`: the detailed capture approach and transient observations awaiting disposition.

Add `evidence/` only when execution produces committed evidence. Additional files are permitted when their responsibility is distinct and linked from the README.

Every `plans/` directory follows the recursive [README and directory-map convention](directory-maps.md). Planning Markdown has no word-count limit; split only for clear ownership and readability. Plans are public: never include secrets or sensitive user/runtime data.

Write for junior engineers: define terms, state assumptions and boundaries, and make delivery actionable without expert inference. Make `tech-docs.md` explain context through verification, not list jargon. The [plan quality gate](../workflows/plan-quality-gate.md) defines learning-capture and verification detail.

## Delivery Ownership

Every executable checklist item in a non-archived formal `delivery.md` must carry one label after its checkbox:

- `[AI]` for work an agent can complete within existing authority, tools, and safety boundaries;
- `[HUMAN]` only for a maintainer decision, credentials, physical action, or unavailable external authority.

Default to `[AI]`. Split mixed tasks rather than assign both labels. Apply it to gates; narrative safety notes need no label. Preserve archive labels; do not retrofit archives.

End each phase with a labeled checkpoint verifying its outcomes. Do not begin the next phase until it passes.

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at completion. After explicit direction, run [plan execution](../workflows/plan-execution.md) to transition stages, synchronize delivery, and archive completed work.

## Transitions and Specifications

Move, never copy, one artifact through stages; update indexes and status together. Promotion replaces the idea brief while preserving evidence and decisions. Archive only after acceptance and verification pass; first route useful learnings to permanent documentation, specifications, governance, or a new idea.

Plans may propose architecture and behavior, but C4 and Gherkin under `specs/` remain the as-built truth. Execution must update every affected specification in the same change under the [specification-maintenance standard](../development/specification-maintenance.md).
