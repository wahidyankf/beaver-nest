# Bnest Flat-File Retirement

**Status:** Backlog  
**Created:** 2026-08-29  
**Scope:** Disable Bnest flat-file readers/writers and permanently delete only proven migrated legacy sources

## Context

The [SQLite storage plan](../../in-progress/bnest-sqlite-storage/README.md) deliberately preserves flat files while it expands, migrates, verifies, activates SQLite, and proves rollback compatibility. Repository migration rules require destructive contraction to occur in a later explicitly authorized plan. The user has authorized that deletion, provided every legacy source is genuinely migrated first.

This plan has no arbitrary waiting period. It becomes executable immediately after the SQLite plan is accepted and archived, both the active and rollback-eligible application artifacts can operate from SQLite, and the fresh deletion-entry proofs pass.

## Scope

- Prove every allow-listed legacy source has a matching accepted SQLite record or recovery BLOB and checksum.
- Promote an SQLite-only compatible revision through Caddy before deleting source files.
- Run one manifest-driven, idempotent retirement task that deletes only exact proven sources.
- Remove Bnest flat-file read/write/mirror behavior and obsolete production runtime-root configuration.
- Prove routed application behavior, restart, backup/restore, and absence of supported legacy files after deletion.

## Non-goals

- Deleting unknown files, unrelated application data, the shared `data/prod/` root, placeholders, backups, SQLite files, or migration evidence.
- Secure-erasure guarantees for filesystem snapshots, backups, SSD remapping, or external copies.
- Moving the SQLite database, changing its schema, or redesigning feature payloads.

## Dependencies

- The SQLite plan is Done with `sqlite_primary`, complete parity, integrity, restore, routed revision, and cleanup evidence.
- Active and rollback-eligible artifacts both support SQLite without flat-file fallback.
- A fresh SQLite backup restores successfully into an isolated marked destination.

## Approach

1. Re-inventory exact legacy templates and join each source checksum to accepted SQLite migration evidence.
2. Deploy SQLite-only reader/writer behavior, promote through Caddy, drain, and retire all flat-only processes.
3. Produce a private retirement manifest; delete each exact matching file idempotently and remove only proven-empty directories.
4. Prove no allow-listed legacy source remains and every representative journey still reads/writes SQLite.
5. Keep SQLite backup and migration/retirement receipts; never recreate flat files.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)

## Directory Map

- [`brd.md`](brd.md) — deletion authorization, outcomes, boundaries, and risks.
- [`delivery.md`](delivery.md) — ordered proof, contraction, deletion, rollout, and archival tasks.
- [`learnings.md`](learnings.md) — safe execution observations and follow-up routing.
- [`prd.md`](prd.md) — acceptance criteria for proof-gated exact deletion.
- [`tech-docs.md`](tech-docs.md) — deletion manifest, compatibility, recovery, specifications, and file impact.
