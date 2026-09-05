# Bnest Application Behaviours

The `.feature` files in this directory form the canonical executable behaviour corpus shared by every Bnest test adapter.

Unit implements every scenario. A scenario may omit Integration, E2E, or both only when each omitted boundary fundamentally cannot express the behaviour, using independently documented `@integration-exempt` and `@e2e-exempt` tags from the repository [BDD standard](../../../../../repo-governance/development/behaviour-driven-development.md). Binding counts are necessary but not sufficient; adapter changes require the [manual implementation review](../../../../../repo-governance/workflows/gherkin-implementation-review.md).

## Directory Map

- [Chat](chat.feature) specifies the local Codex conversation experience.
- [Authentication](authentication.feature) specifies one-time setup, persistent independent login sessions, roles, and isolation.
- [Centralized data](centralized_data.feature) specifies confirmed browser import and server-owned continuation.
- [Sifat Allah](sifat_allah.feature) specifies the authenticated user-owned learning activity.
- [SQLite storage](sqlite_storage.feature) specifies config/data separation, local database migration, relocation, activation, and verified legacy cleanup.
- [Scheduled backups](scheduled_backups.feature) specifies contextual daily schedules, verified SQLite backups, retention, typed admin configuration, and authorization.
