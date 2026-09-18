# Bnest Backend Behaviours

The `.feature` files in this directory form the canonical executable backend behaviour corpus. They own GraphQL,
authentication/authorization at the server boundary, SQLite, Scheduler, Backup, push delivery, and internal services.
`bnest-app` runs the unit and local-only integration adapters against this root as part of its aggregate corpus;
`bnest-app-be-e2e` is this root's one dedicated E2E owner.

Unit implements every scenario. A scenario may omit Integration, E2E, or both only when each omitted boundary
fundamentally cannot express the behaviour, using independently documented `@integration-exempt` and `@e2e-exempt`
tags from the repository [BDD standard](../../../../../repo-governance/development/behaviour-driven-development.md).
Binding counts are necessary but not sufficient; adapter changes require the
[manual implementation review](../../../../../repo-governance/workflows/gherkin-implementation-review.md).

## Directory Map

- [Authentication](authentication.feature) specifies password hashing, session persistence/independence, capability
  policy, and cross-user data isolation.
- [Centralized data](centralized_data.feature) specifies input validation, idempotency, stale-write rejection, and
  persisted continuation/recovery.
- [Family chat GraphQL](family_chat_graphql.feature) specifies the public schema surface: authenticated
  queries/mutations/subscription, pagination, and safe errors.
- [Family chat operations](family_chat_operations.feature) specifies system messages, atomic delivery commit, push
  retry/retention/purge, Scheduler handler routing, backup capacity/concurrency/restore, and slot/socket policy.
- [Scheduled backups](scheduled_backups.feature) specifies destination policy, schedule persistence/catch-up,
  snapshot, claims/retries, retention, and registry behaviour.
- [SQLite storage](sqlite_storage.feature) specifies migration, authority, safety, relocation, retirement, and the
  continuity contract.
