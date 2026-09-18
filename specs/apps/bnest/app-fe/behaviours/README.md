# Bnest Frontend Behaviours

The `.feature` files in this directory form the canonical executable frontend behaviour corpus. They own routes and
rendered UI, IndexedDB, connection status, reconnect orchestration, push UX, responsive behaviour, and accessibility.
`bnest-app` runs the unit and local-only integration adapters against this root as part of its aggregate corpus;
`bnest-app-fe-e2e` is this root's one dedicated E2E owner.

Unit implements every scenario. A scenario may omit Integration, E2E, or both only when each omitted boundary
fundamentally cannot express the behaviour, using independently documented `@integration-exempt` and `@e2e-exempt`
tags from the repository [BDD standard](../../../../../repo-governance/development/behaviour-driven-development.md).
Binding counts are necessary but not sufficient; adapter changes require the
[manual implementation review](../../../../../repo-governance/workflows/gherkin-implementation-review.md).

## Directory Map

- [Authentication](authentication.feature) specifies redirect/login/setup/logout and visible home behaviour.
- [Centralized data](centralized_data.feature) specifies browser-source discovery, confirmation, key cleanup, and
  visible resume outcome.
- [Chat](chat.feature) specifies the local Codex conversation experience.
- [Family chat](family_chat.feature) specifies the room route, GraphQL-driven message list/composer, push permission
  UX, IndexedDB outbox, and reconnect/catch-up behaviour.
- [Scheduled backups](scheduled_backups.feature) specifies admin settings discovery, form authorization, contextual
  inventory, and typed link behaviour.
- [Sifat Allah](sifat_allah.feature) specifies the authenticated user-owned learning activity.
- [SQLite storage](sqlite_storage.feature) specifies admin storage selection/access and routed reconnect UI.
