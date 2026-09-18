# Technical Documentation — Family Chat Room

Read these documents in order. Each answers the next question a cold executor needs before changing the application.

1. [Architecture and Data Flow](001-architecture-and-data-flow.md) — boundaries, trust, message flow, processes, and
   interfaces.
2. [Data Model and Migration Contract](002-data-model-and-migration-contract.md) — exact SQLite schema, field guide,
   indexes, delivery retention, audit policy, expand/verify/rollback, and ERD.
3. [Realtime, Pagination, and Consistency](003-realtime-pagination-and-consistency.md) — ordering, idempotency, PubSub,
   history windows, reconnect, and scroll behavior.
4. [Web Push Notifications and Privacy](004-web-push-notifications-and-privacy.md) — permission, VAPID, subscriptions,
   outbox, retry, scheduled retention, service worker, and safe evidence.
5. [UI Design](005-ui-design.md) — three responsive alternatives, selected direction, states, copy, accessibility, and
   asset map.
6. [Specification Delta and Adapter Map](006-specification-delta-and-adapter-map.md) — canonical Gherkin/C4 changes and
   unit, integration, and E2E ownership.
7. [File Impact, Dependencies, and Operations](007-file-impact-dependencies-and-operations.md) — exact expected paths,
   dependency decision, configuration, rollout, recovery, documentation, and cleanup.
8. [GraphQL API, Authentication, and Errors](008-graphql-api-authentication-and-errors.md) — exact operations, envelopes,
   session/CSRF/socket authentication, error classification, subscription lifecycle, and manual proof.
9. [Backup, Capacity, Restore, and Release](009-backup-capacity-restore-and-release.md) — scheduler/service boundaries,
   disk preflight, cancellable snapshot algorithm, concurrency proof, restore drill, staged release, and rollback.

[`delivery.md`](../delivery.md) is the authoritative execution order. These documents define contracts; they do not
authorize skipping its RED/GREEN/REFACTOR tasks, checkpoints, active-service proof, or cleanup.

## Directory Map

- [`001-architecture-and-data-flow.md`](001-architecture-and-data-flow.md) — component, process, scheduler/service boundary,
  trust, and message flow.
- [`002-data-model-and-migration-contract.md`](002-data-model-and-migration-contract.md) — SQLite DDL, ERD, field guide,
  and transition contract.
- [`003-realtime-pagination-and-consistency.md`](003-realtime-pagination-and-consistency.md) — ordering, paging, scrolling,
  realtime, and reconnect rules.
- [`004-web-push-notifications-and-privacy.md`](004-web-push-notifications-and-privacy.md) — Web Push permission, outbox,
  retries, retention, privacy, and service-worker behavior.
- [`005-ui-design.md`](005-ui-design.md) — responsive alternatives, selected visual direction, states, and accessibility.
- [`006-specification-delta-and-adapter-map.md`](006-specification-delta-and-adapter-map.md) — Gherkin, C4, bindings, and
  verification ownership.
- [`007-file-impact-dependencies-and-operations.md`](007-file-impact-dependencies-and-operations.md) — exact files,
  dependency choice, configuration, rollout, and recovery.
- [`008-graphql-api-authentication-and-errors.md`](008-graphql-api-authentication-and-errors.md) — GraphQL request,
  response, authentication, authorization, error, and subscription protocol contracts.
- [`009-backup-capacity-restore-and-release.md`](009-backup-capacity-restore-and-release.md) — whole-database backup,
  capacity, cancellation, restore, compatibility/experience release, and rollback operations.
