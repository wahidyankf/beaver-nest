# Plan Lifecycle

Keep each temporary plan artifact in one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

Create `plans/` artifacts only after an explicit user request. Harness Plan mode permits in-memory or temporary working plans, never repository plan docs.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md`; select the q1–q4 urgency/importance directory from dated evidence.

Include summary, provenance, problem/evidence, why now, prior art, direction, scope/non-goals, risks/questions, success, and promotion signal. Exclude implementation detail, Gherkin, and delivery checklists. Search and consolidate first.

## Formal Plans

Use `plans/backlogs/<slug>/` for queued, `plans/in-progress/<slug>/` for active, and `plans/done/YYYY-MM-DD__<slug>/` for complete work. Use kebab-case.

Each non-archived plan contains:

- `README.md`: status, context, scope, approach, dependencies, and complete navigation;
- `brd.md`: business goal, roles, outcomes, non-goals, and risks;
- `prd.md`: personas, user stories, Gherkin acceptance criteria, scope, and risks;
- `tech-docs/README.md`: technical entry point, architecture, decisions, and reading order;
- `delivery.md`: detailed ordered tasks, executors, proof, phases, and gates; and
- `learnings.md`: capture approach and transient observations awaiting disposition.

Keep applicable data contracts, migration, specification changes, File Impact, UI design, and assets in `tech-docs/`. Give each one reader job and a technical-map link; the plan map links the entry point.

Apply [minimal sufficiency](../principles/minimal-sufficiency.md): add companions only for required distinct detail. Split mixed reader jobs, then integrate unique content and delete superseded/duplicate files. Add `evidence/` only for committed execution evidence.

Every directory follows [directory maps](directory-maps.md). Plans have no word limit. Never include secrets or sensitive user/runtime data.

Write for a junior engineer: define terms, select decisions, and give ordered mechanics and proof. File Impact is an exact annotated tree: `[E]` update, `[N]` new, `[M]` moved, `[D]` deleted. Use an unknown filename only when the plan explains the discovery prerequisite. Follow applicable [migration](plan-migrations.md), [specification-change](plan-specification-changes.md), and [UI-design](plan-ui-design.md) conventions.

PRD Gherkin accepts the plan; it does not map one-to-one to `specs/`. The technical set selects durable canonical contracts. Delivery proves plan-only operational, migration, and rollout criteria.

## Delivery Ownership

Every executable non-archived checkbox carries relevant `[AC-...]` labels and:

- `[AI]` for work within available authority, tools, and safety boundaries;
- `[HUMAN]` only for a decision, credential, physical action, production mutation, or external authority unavailable to AI.

Prefer `[AI]`; never use `[HUMAN]` to postpone discovery or a settled decision. Split mixed tasks. Each task names context/input, action, outcome, and proof for a junior. End every phase with a blocking checkpoint.

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at completion. After explicit direction, [execute](../workflows/plan-execution.md), synchronize delivery, and archive.

## Transitions and Specifications

Move, never copy; update stage indexes and status. Archive only after acceptance, verification, and learning disposition.

Plans may propose architecture and behavior, but `specs/` remains as-built truth. Execution updates every affected specification with implementation under [specification maintenance](../development/specification-maintenance.md).
