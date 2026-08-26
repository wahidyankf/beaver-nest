# Plan Lifecycle

Keep each temporary plan artifact in one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

`plans/` artifacts require an explicit user request. Harness Plan mode permits only in-memory or temporary working plans, never repository plan docs. Do not infer formal plans from another change.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md`. Select `q1-urgent-important`, `q2-not-urgent-important`, `q3-urgent-not-important`, or `q4-not-urgent-not-important` from `Why now` evidence and impact.

Each brief needs a summary, dated provenance, problem/evidence, why now, prior art, direction, scope/non-goals, risks/questions, success, and promotion signal. Exclude implementation detail, Gherkin, and delivery checklists. Search and consolidate first.

## Formal Plans

Use `plans/backlogs/<slug>/` for queued, `plans/in-progress/<slug>/` for active, and `plans/done/YYYY-MM-DD__<slug>/` for complete work. Use kebab-case.

Formal plans contain:

- `README.md`: status, context, scope, approach, dependencies, and navigation;
- `brd.md`: business goal, roles, outcomes, non-goals, and risks;
- `prd.md`: personas, user stories, Gherkin acceptance criteria, scope, and risks;
- `tech-docs.md`: architecture, schemas, decisions, mechanics, impact, testing, rollback, and risks;
- `delivery.md`: granular ordered checklist, phases, and gates; and
- `learnings.md`: the detailed capture approach and transient observations awaiting disposition.

Add `evidence/` only for committed execution evidence. Give other files distinct ownership and README links.

Every `plans/` directory follows the recursive [README and directory-map convention](directory-maps.md). Plans have no word limit; split for readability. Never include secrets or sensitive user/runtime data.

Write junior-readable docs; define terms and avoid jargon. `tech-docs.md` File Impact is an annotated tree of every changed path: `[E]` update, `[N]` new, `[M]` moved, or `[D]` deleted. Use a directory only for an unknown filename and explain why. Follow applicable [migration](plan-migrations.md) and [UI-design](plan-ui-design.md) conventions.

PRD Gherkin expresses plan outcomes; it neither modifies nor maps one-to-one to `specs/`. `tech-docs.md` selects durable canonical contracts. Keep operational, migration, rollout, and other plan-only criteria in the PRD and prove them with named `delivery.md` tasks and tests.

## Delivery Ownership

Every executable non-archived `delivery.md` item carries an executor and relevant PRD acceptance-criterion label after its checkbox:

- `[AI]` for agent work within existing authority, tools, and safety boundaries;
- `[HUMAN]` only for a maintainer decision, credentials, physical action, or unavailable authority.

Default to `[AI]`; split mixed tasks. Cross-cutting tasks list relevant criteria. Label gates, not narrative safety notes. Preserve archive labels; do not retrofit them.

End each phase with a labeled checkpoint; do not begin the next until it passes.

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at completion. After explicit direction, [execute](../workflows/plan-execution.md), synchronize delivery, and archive.

## Transitions and Specifications

Move, never copy; update stage indexes and status. Promotion replaces the idea brief while retaining evidence and decisions. Archive only after acceptance and verification; first route useful learnings to permanent documentation, specifications, governance, or an idea.

Plans may propose architecture and behavior, but C4 and Gherkin under `specs/` remain the as-built truth. Execution must update every affected specification in the same change under the [specification-maintenance standard](../development/specification-maintenance.md).
