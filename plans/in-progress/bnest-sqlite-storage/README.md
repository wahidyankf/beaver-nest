# Bnest SQLite Storage

**Status:** In Progress  
**Created:** 2026-08-29  
**Started:** 2026-08-29  
**Scope:** Bnest storage configuration, reproducible SQLite schema, flat-file backfill, and active-service cutover

## Context

Bnest currently persists accounts, sessions, import records, chat, Sifat Allah progress, and theme preferences as versioned JSON below one `data/prod/`-shaped runtime root. Flat files were an intentional interim store. This plan moves every supported Bnest record into one machine-local SQLite database while preserving the current repository facade, immutable recovery evidence, browser behavior, and blue/green continuity.

The database folder is configurable in the UI. The displayed default is `~/.config/bnest/`, which resolves on the server to the service account's home directory; the fixed database filename is `bnest.sqlite3`. New installations select storage before creating accounts. Existing installations use an admin-only storage screen to inventory, migrate, verify, and activate SQLite.

![Selected desktop storage setup: a guided migration ledger with database folder, safety checks, and progress](assets/ui-ledger-hifi-desktop.svg)

## Scope

- Add a versioned, deterministic SQLite DDL migration file and an idempotent flat-file backfill adapter shared by the UI and a headless Nx task.
- Add setup and admin UI states for default or custom database-folder selection.
- Migrate all current system and user-owned record types, not only chat and learning data.
- Keep SQLite authoritative only after source inventory, checksummed copy, normal read-back, restore rehearsal, and parity proof pass.
- Keep the flat-file reader and a compatible mirror during the rollback window; defer deletion and destructive contraction.
- Integrate the migration with release manifests, the host migration lock, Caddy rollout, revision proof, and LiveView/WebSocket reconnect.

## Non-goals

- Cloud or networked databases, multi-host replication, public registration, account-management features, or arbitrary SQL access.
- A general database browser or file picker with access to client-device paths.
- Deleting legacy flat files, removing their reader, or moving an initialized database to another folder in this plan.
- Redesigning chat, Sifat Allah, theme, or browser-import product flows.

## Approach

1. Expand the repository behind its existing facade with SQLite and storage coordination while flat files remain authoritative.
2. Let an authorized setup flow validate one server-local directory, run the versioned DDL, and record private machine-local configuration.
3. Inventory and backfill supported records in deterministic path order with per-item checksums and resumable outcomes.
4. Verify domain reads, restore into an isolated database, and flat/SQLite parity before an atomic authority switch.
5. Keep compatibility during the rollback window, deploy through an independent candidate, promote through Caddy, prove routed revision and LiveView reconnect, then drain and clean up.

## Dependencies

- Existing typed repository schemas and facade under `apps/bnest-app/lib/bnest_app/data_repository/`.
- Existing managed release, Caddy, and migration-manifest boundaries.
- A reviewed SQLite Ecto adapter and its locked transitive dependencies.
- A writable, private server-local directory owned by the Bnest service account.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)
- [UI assets](assets/README.md)
- Prior art: [centralized flat-file delivery](../../done/2026-08-26__bnest-centralized-data/README.md) and [release migration contract](../../done/2026-08-27__single-machine-release-simplification/tech-docs/migration-design.md)

## Directory Map

- [`assets/`](assets/README.md) — required lo-fi alternatives and selected hi-fi responsive design.
- [`brd.md`](brd.md) — business goals, roles, outcomes, boundaries, and risks.
- [`delivery.md`](delivery.md) — ordered implementation, verification, rollout, and reconciliation tasks.
- [`learnings.md`](learnings.md) — safe observations and follow-up routing during execution.
- [`prd.md`](prd.md) — personas, stories, and plan-level acceptance criteria.
- [`tech-docs.md`](tech-docs.md) — architecture, data contracts, migration, UI, specifications, and file impact.
