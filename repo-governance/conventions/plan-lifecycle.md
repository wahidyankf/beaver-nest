# Plan Lifecycle

What this repository adds to the [Plans Convention](plans.md). The lifecycle roots, the six required documents, the
technical shape and its three-digit ordered companions, the delivery contract, the terminal verdicts and the archival
sequence are stated there once and are not restated here.

## Authorization

`plans/` artifacts require an explicit user request; Plan mode never authorizes a repository plan document.

## Ideas

Store rough two-pagers at `plans/ideas/<quadrant>/<slug>.md` and select `q1`–`q4` from dated urgency and importance
evidence. The quadrant directory is this repository's own layout; the convention fixes the root, not what sits beneath
it.

Include summary, evidence, timing, prior art, direction, scope and non-goals, risks, success, and promotion signal.
Exclude implementation detail, Gherkin, and delivery checklists; search and consolidate first.

## Scope of a Plan

Plan documentation exists so a reader can understand why the plan exists, its intended outcome, the options and
trade-offs considered, the selected decision, and how delivery and proof will work.

Cross-repository work is planned here; each affected repository then executes its own change under its own rules. A plan
never edits another repository directly.

Follow [maps](directory-maps.md). Plans have no word limit but exclude secrets and sensitive runtime data. Write for
juniors. Record File Impact as exact paths: `[E]` updated, `[N]` new, `[M]` moved, `[D]` deleted; discover unknowns.
Follow the applicable [migration](plan-migrations.md), [specification-change](plan-specification-changes.md) and
[UI-design](plan-ui-design.md) conventions.

PRD Gherkin accepts the plan, not `specs/`; technical documents select contracts, and delivery proves operational,
migration, and rollout criteria.

## Active-Service Plans

The technical document set and `delivery.md` apply [continuity](../development/live-service-continuity.md) and the
deployment workflow. Bnest plans name Caddy, candidate and revision health, continuous exact-origin responsiveness with
numeric p95 and per-sample maximum acceptance criteria from preflight through drain, LiveView and WebSocket reconnect,
drain and cleanup, mixed-version safety, routed proof, and the responsiveness rollback trigger. Never stop the sole
backend, repoint Tailscale, require a refresh, or accept a 2xx status alone as responsiveness proof.

## Local Delivery Rules

A checklist item that ships code expresses its [red-green-refactor cycle](../workflows/red-green-refactor.md) as
separate RED, GREEN, and REFACTOR checkboxes, each naming the exact test path, command, and expected failure or pass.
Never combine the cycle into one checkbox or into prose.

Give recovery and rollback checkboxes an explicit trigger. Keep them dormant until triggered; otherwise record an
evidence-backed `Not triggered` disposition at reconciliation.

When execution may create, change, move, or delete a repository rule, `delivery.md` includes an `[AI]` task that applies
the bounded [rules-propagation workflow](../workflows/rules-propagation.md) to the resulting rule change and records its
terminal result; it may return `PASS_NO_CHANGE`. When execution changes a documented C4 element, `delivery.md` includes
an `[AI]` task that updates the exact affected canonical file and view with the final as-built model under the
[plan specification-change convention](plan-specification-changes.md).

End every phase with a blocking checkpoint.

Run the [plan quality gate](../workflows/plan-quality-gate.md) before execution, after material changes, and at
completion, only on explicit user direction. Authorize [execution](../workflows/plan-execution.md) separately.

## Transitions and Specifications

Refuse an existing dated destination. Archive only after acceptance, verification, learnings, and conditional items are
reconciled, then run the deterministic repository gate.

Plans may propose architecture and behaviour, but `specs/` remains as-built truth. Execution updates every affected
specification with the implementation under
[specification maintenance](../development/specification-maintenance.md).
