# Business Requirements

## Goal

Replace Bnest's interim production flat-file store with a private, configurable SQLite database without losing household data or interrupting the routed 24/7 service.

## Roles

- **Family member:** keeps using chat, learning, theme, login, and logout without understanding storage internals.
- **Administrator:** optionally replaces the default server-side database folder before migration and reviews value-free status or retry outcomes.
- **Maintainer:** deploys compatible revisions, verifies recovery and routed behavior, and retains rollback capacity.
- **Bnest application:** validates storage configuration, serializes migration, preserves sources, and refuses unsafe authority changes.

## Required Outcomes

- A fresh or existing installation uses `~/.config/bnest/bnest.sqlite3` when no explicit custom location exists; visiting storage UI is not required.
- An existing installation copies every recognized current record through one reproducible headless schema migration and checksum-identified backfill.
- SQLite becomes authoritative automatically in the same managed run after read-back, parity, restart, and isolated restore proof; no browser confirmation intervenes.
- Unknown, malformed, changed, or unsupported sources remain untouched and are reported with a safe retry category.
- Existing authenticated journeys and sessions remain usable across Caddy promotion and compatible LiveView reconnect without a manual refresh.
- A failed migration leaves the current flat-file route healthy and retryable.

## Business Rules

- Managed release/headless tooling may migrate without a browser step. Only an authenticated user with the `admin` role may open storage UI or override the default before migration starts; fresh installs therefore use the headless default.
- The optional browser UI selects a folder on the Bnest host, not a folder on the browser device.
- The UI never displays record values, password material, token digests, user identifiers, or recovery contents.
- An initialized database location is immutable in this plan. Relocation requires a later migration plan.
- Destructive flat-file cleanup is owned by the explicitly authorized follow-up plan and may begin immediately after this plan's acceptance gates pass.

## Non-goals

- External database hosting, synchronization between machines, database encryption key management, or a backup product.
- New account recovery, password reset, role management, or storage quotas.
- Normalizing every JSON payload into feature-specific relational tables.
- Retiring current record schema versions or browser import compatibility.

## Risks and Controls

- **Data loss or partial copy:** immutable source bytes, deterministic item identities, per-item checksums, transactions, parity proof, and isolated restore rehearsal.
- **Split-brain writers:** storage-phase gate, host-wide migration lock, SQLite transactions, and migration disabled while an incompatible slot can write.
- **Unsafe custom path:** server-side normalization, fixed filename, symlink and ownership checks, private permissions, and rejection of repository/source/test roots.
- **SQLite corruption or lock pressure:** WAL-aware health checks, bounded busy timeout, disk admission, integrity checks, and backup through SQLite APIs rather than copying live files.
- **Service interruption:** flat-primary expand release, independent candidate, Caddy promotion, revision readiness, automatic LiveView/WebSocket reconnect, bounded drain, and rollback.
- **Sensitive evidence:** synthetic `test-user-` fixtures and structural/status-only logs.

## Success Measures

- All accepted inventory items have matching source and target checksums and normal repository read-back.
- A second migration run produces no duplicate records or data changes.
- Fresh and migrated installations pass unit, integration, behavior, focused E2E, restart, and routed revision checks.
- The active route stays healthy throughout rollout; old clients reconnect without `page.reload()`.
- No production runtime record, database file, sidecar, path value, or credential enters Git.
