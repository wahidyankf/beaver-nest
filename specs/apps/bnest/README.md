# Bnest Specifications

Bnest specifications are organized by application surface. `bnest-app` is the one production owner of every surface
below: it runs the unit and local-only integration adapters against the aggregate of every declared canonical root.
Each dedicated E2E project owns exactly one root and proves complete adapter coverage for it alone. Every scenario
has exactly one canonical root; the same scenario is never duplicated across roots.

| Root                         | Owns                                                                                                                        | Aggregate adapters | E2E owner          |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------ | ------------------ |
| [`app-be`](app-be/README.md) | GraphQL, authentication/authorization at the server boundary, SQLite, Scheduler, Backup, push delivery, internal services   | `bnest-app`        | `bnest-app-be-e2e` |
| [`app-fe`](app-fe/README.md) | Routes and rendered UI, IndexedDB, connection status, reconnect orchestration, push UX, responsive behaviour, accessibility | `bnest-app`        | `bnest-app-fe-e2e` |

## Directory Map

- [Backend](app-be/README.md) contains the backend architecture and behaviour specifications.
- [Frontend](app-fe/README.md) contains the frontend architecture and behaviour specifications.
