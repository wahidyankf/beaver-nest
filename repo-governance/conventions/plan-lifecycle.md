# Plan Lifecycle

Keep each plan in one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

`plans/` artifacts require explicit user request; Plan mode never authorizes repository plan docs.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md`; select q1–q4 from dated urgency/importance evidence.

Include summary, evidence, timing, prior art, direction, scope/non-goals, risks, success, and promotion signal. Exclude implementation detail, Gherkin, and delivery checklists; search and consolidate first.

## Formal Plans

Use `plans/backlogs/<slug>/` for queued, `plans/in-progress/<slug>/` for active, and `plans/done/YYYY-MM-DD__<slug>/` for completed work. Use kebab-case.

Plan documentation exists so a reader can understand why the plan exists, its intended outcome, the options and trade-offs considered, the selected decision, and how delivery and proof will work. Organization should feel natural because it serves that communication goal. Split and unsplit technical documents are only presentation mechanisms, never quality outcomes by themselves.

Each formal plan contains:

- `README.md`: status, context, scope, approach, dependencies, navigation;
- `brd.md`: goal, roles, outcomes, non-goals, risks;
- `prd.md`: personas, stories, Gherkin criteria, scope, risks;
- `tech-docs.md`, or `tech-docs/README.md` with mapped companions: technical entry point, architecture, decisions;
- `delivery.md`: ordered tasks, executors, proof, phases, gates; and
- `learnings.md`: capture approach and transient observations.

Use exactly one technical shape: a single `tech-docs.md`, or `tech-docs/README.md` with mapped companions. Choose by reader needs, cohesion, and navigation: keep one document while it remains coherent; split when distinct responsibilities benefit from their own reading order and ownership; collapse fragments with no distinct job. File length is a review signal, never a requirement or prohibition for either shape. Never keep both shapes or pre-create empty companions. Follow [minimal sufficiency](../principles/minimal-sufficiency.md).

Follow [maps](directory-maps.md); plans have no word limit but exclude secrets and sensitive runtime data. Write for juniors. File Impact: exact `[E]` update, `[N]` new, `[M]` moved, `[D]` deleted paths; discover unknowns. Follow applicable [migration](plan-migrations.md), [specification-change](plan-specification-changes.md), [UI-design](plan-ui-design.md) conventions.

PRD Gherkin accepts the plan, not `specs/`; technical docs select durable contracts and delivery proves operational, migration, and rollout criteria.

Active-service plans: the technical document set and `delivery.md` apply [continuity](../development/live-service-continuity.md) and deployment workflow. Bnest plans name Caddy, candidate/revision health, continuous exact-origin responsiveness with numeric p95 and per-sample maximum acceptance criteria from preflight through drain, LiveView/WebSocket reconnect, drain/cleanup, mixed-version safety, routed proof, and the responsiveness rollback trigger; never stop the sole backend, repoint Tailscale, require refresh, or accept 2xx status alone as responsiveness proof.

## Delivery Ownership

Every executable non-archived checkbox carries relevant `[AC-...]` labels and:

- `[AI]` for work within available authority, tools, and safety boundaries;
- `[HUMAN]` only for a decision, credential, physical action, production mutation, or external authority unavailable to AI.

Prefer `[AI]`; never use `[HUMAN]` to postpone discovery or settled decisions. Split mixed tasks. Each task names input, action, outcome, and proof for a junior. End every phase with a blocking checkpoint.

Give recovery/rollback checkboxes an explicit trigger. Keep them dormant until triggered; otherwise record an evidence-backed `Not triggered` disposition at reconciliation. The verified move completes the separate archival checkbox.

When execution may create, change, move, or delete a repository rule, `delivery.md` must include an `[AI]` task that applies the [rules-propagation workflow](../workflows/rules-propagation.md) to the resulting rule change and records its verification; the workflow's idempotence gate may produce a verified no-op. When execution changes a documented C4 element, `delivery.md` must include an `[AI]` task that updates the exact affected canonical file and view with the final as-built model under the [plan specification-change convention](plan-specification-changes.md).

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at completion. After explicit direction, [execute](../workflows/plan-execution.md), synchronize delivery, and archive.

## Transitions and Specifications

Move, never copy; update indexes and status together. Refuse an existing dated destination. Archive only after acceptance, verification, learnings, and conditional items are reconciled; then verify archive links/maps directly.

Plans may propose architecture and behavior, but `specs/` remains as-built truth. Execution updates every affected specification with implementation under [specification maintenance](../development/specification-maintenance.md).
