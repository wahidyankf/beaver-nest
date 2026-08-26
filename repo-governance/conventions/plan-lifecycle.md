# Plan Lifecycle

Plans are temporary change records, not canonical descriptions of the as-built system. Store each artifact in exactly one stage:

```text
ideas/ → backlogs/ → in-progress/ → done/
```

## Authorization

Create a plan document under `plans/` only in response to an explicit user request. Do not infer a request to plan from a request to change code, specifications, or other documentation.

## Ideas

Store one rough two-pager at `plans/ideas/<quadrant>/<slug>.md`. Use `q1-urgent-important`, `q2-not-urgent-important`, `q3-urgent-not-important`, or `q4-not-urgent-not-important` according to evidence in `Why now` and the idea's material impact.

Each brief must contain a summary and dated provenance, problem and evidence, why now, linked prior art, proposed direction, scope and non-goals, risks and open questions, and success plus a promotion signal. Keep implementation detail, Gherkin, and delivery checklists out. Search and consolidate before adding a brief.

## Formal Plans

Store queued work at `plans/backlogs/<slug>/`, active work at `plans/in-progress/<slug>/`, and completed work at `plans/done/YYYY-MM-DD__<slug>/`. Use lowercase kebab-case; the done prefix is the completion date.

Every formal plan must contain:

- `README.md`: status, context, scope, approach summary, dependencies, and navigation;
- `brd.md`: business goal, rationale, roles, outcomes, non-goals, and business risks;
- `prd.md`: personas, user stories, product requirements, acceptance criteria, scope, and product risks;
- `tech-docs.md`: proposed architecture, decisions, mechanics, file impact, dependencies, testing, rollback, and technical risks;
- `delivery.md`: granular executable checklist, ordered phases, and verification gates; and
- `learnings.md`: transient execution observations awaiting disposition.

Add `evidence/` only when execution produces committed evidence. Additional files are permitted when their responsibility is distinct and linked from the README.

Every directory under `plans/` must follow the recursive [README and directory-map convention](directory-maps.md). Planning Markdown has no word-count limit; split content only for clear ownership and readability.

## Transitions and Specifications

Move, never copy, one artifact through stages. Update source and destination indexes plus plan status in the same change. Promotion replaces the idea brief while preserving its evidence and decisions. Archive only after acceptance and verification pass; route useful learnings to permanent documentation, specifications, governance, or a new idea first.

Plans may propose architecture and behavior, but C4 and Gherkin under `specs/` remain the as-built truth. Execution must update every affected specification in the same change under the [specification-maintenance standard](../development/specification-maintenance.md).
