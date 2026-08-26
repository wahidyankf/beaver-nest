# Plan Lifecycle

Keep each temporary plan artifact in one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

Create `plans/` artifacts only after an explicit user request. Harness Plan mode permits in-memory or temporary working plans, never repository plan docs.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md`; select q1–q4 from dated urgency/importance evidence.

Include summary, provenance, evidence, why now, prior art, direction, scope/non-goals, risks, success, and promotion signal. Exclude implementation detail, Gherkin, and delivery checklists. Search and consolidate first.

## Formal Plans

Use `plans/backlogs/<slug>/` for queued, `plans/in-progress/<slug>/` for active, and `plans/done/YYYY-MM-DD__<slug>/` for completed work. Use kebab-case.

Each active or backlogged plan contains:

- `README.md`: status, context, scope, approach, dependencies, and navigation;
- `brd.md`: business goal, roles, outcomes, non-goals, and risks;
- `prd.md`: personas, user stories, Gherkin acceptance criteria, scope, and risks;
- `tech-docs/README.md`: technical entry point, architecture, decisions, and order;
- `delivery.md`: detailed ordered tasks, executors, proof, phases, and gates; and
- `learnings.md`: capture approach and transient observations awaiting disposition.

Keep applicable contracts, migration, specification changes, File Impact, UI design, and assets in `tech-docs/`. Give each a reader job and technical-map link; the plan map links its entry point.

Apply [minimal sufficiency](../principles/minimal-sufficiency.md): add companions only for required detail. Split mixed reader jobs; integrate unique content and delete duplicates. Add `evidence/` only for committed evidence.

Every directory follows [directory maps](directory-maps.md). Plans have no word limit. Exclude secrets and sensitive user/runtime data.

Write for a junior: define terms, decisions, ordered mechanics, and proof. File Impact is an exact tree: `[E]` update, `[N]` new, `[M]` moved, `[D]` deleted. Unknown filenames require discovery first. Follow applicable [migration](plan-migrations.md), [specification-change](plan-specification-changes.md), and [UI-design](plan-ui-design.md) conventions.

PRD Gherkin accepts the plan; it does not map one-to-one to `specs/`. Technical docs select durable canonical contracts. Delivery proves remaining operational, migration, and rollout criteria.

## Delivery Ownership

Every executable non-archived checkbox carries relevant `[AC-...]` labels and:

- `[AI]` for work within available authority, tools, and safety boundaries;
- `[HUMAN]` only for a decision, credential, physical action, production mutation, or external authority unavailable to AI.

Prefer `[AI]`; never use `[HUMAN]` to postpone discovery or settled decisions. Split mixed tasks. Each task names input, action, outcome, and proof for a junior. End every phase with a blocking checkpoint.

Give recovery/rollback checkboxes an explicit trigger. Keep them dormant until triggered; otherwise record an evidence-backed `Not triggered` disposition at reconciliation. The verified move completes the separate archival checkbox.

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at completion. After explicit direction, [execute](../workflows/plan-execution.md), synchronize delivery, and archive.

## Transitions and Specifications

Move, never copy; update indexes and status together. Refuse an existing dated destination. Archive only after acceptance, verification, learnings, and conditional items are reconciled; then verify archive links/maps directly.

Plans may propose architecture and behavior, but `specs/` remains as-built truth. Execution updates every affected specification with implementation under [specification maintenance](../development/specification-maintenance.md).
