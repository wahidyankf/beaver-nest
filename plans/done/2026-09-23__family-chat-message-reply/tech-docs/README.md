# Technical Documentation — Family Chat Message Reply

Read these in order. Each answers the next question a cold executor needs before changing the application, and the
order is the order the answers depend on each other: what is stored decides what the API can say, what the API says
decides what the interface can show, how the interface behaves decides what has to be proven, what has to be proven
decides what has to be touched, and what has to be touched decides how it reaches production.

1. [Data Model and Migration Contract](001-data-model-and-migration.md) — the column, why a reference rather than a
   snapshot, the read path, preview truncation, and the forward and reverse migration.
2. [GraphQL Contract](002-graphql-contract.md) — the quote type, the mutation argument, operation documents,
   validation, idempotency, and manual proof.
3. [UI Design](003-ui-design.md) — three responsive alternatives, the selected direction, tokens, components, copy,
   and state expectations, with all twelve assets.
4. [Interaction and Accessibility](004-interaction-and-accessibility.md) — the menu's triggers and focus contract,
   keyboard navigation of the history, the composer strip, the quote card, bounded jump, and offline behaviour.
5. [Specification Changes](005-specification-changes.md) — which acceptance outcomes become durable contracts,
   the exact Gherkin and C4 delta, the binding map, and what stays plan-only with its reason.
6. [File Impact, Documentation, and Release](006-file-impact-and-release.md) — exact paths, specification and
   documentation updates, configuration, and the two-stage release with its rollback triggers.

[`delivery.md`](../delivery.md) is the authoritative execution order. These documents define contracts; they do not
authorize skipping its RED/GREEN/REFACTOR tasks, checkpoints, active-service proof, manual passes, or cleanup.

## Directory Map

- [`001-data-model-and-migration.md`](001-data-model-and-migration.md) — SQLite column, reference-versus-snapshot
  decision, validation rules, read path, ERD, and transition contract.
- [`002-graphql-contract.md`](002-graphql-contract.md) — schema delta, operation documents, error matrix,
  idempotency, resolver boundary, and manual proof.
- [`003-ui-design.md`](003-ui-design.md) — alternatives, selection rationale, prior-art adoption and rejection,
  tokens, components, copy inventory, and responsive and state behaviour.
- [`004-interaction-and-accessibility.md`](004-interaction-and-accessibility.md) — gestures, focus, roving tabindex,
  screen-reader wording, bounded jump algorithm, and the offline record shape.
- [`005-specification-changes.md`](005-specification-changes.md) — durable-contract selection, Gherkin and C4
  delta, layer ownership, binding map, and plan-only outcomes with their verification tasks.
- [`006-file-impact-and-release.md`](006-file-impact-and-release.md) — exact file impact, specification and
  documentation impact, configuration, two-stage release, rollback triggers, and backup implications.
