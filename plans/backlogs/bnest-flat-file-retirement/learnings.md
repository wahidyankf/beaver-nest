# Learnings

## Capture Timing

- Record a dated note at entry reconciliation, every blocked source, deletion interruption, Caddy transition, recovery, final absence proof, and archive.
- Capture only information needed to resume or improve a durable contract.

## Safe Evidence

- Allowed: retirement/migration IDs, schema versions, generic record types, checksum-match booleans, outcome categories, revision IDs, durations, and pass/fail states.
- Prohibited: concrete relative paths containing IDs, usernames, token digests, payloads, absolute host paths, account counts, credentials, database contents, and source bytes.
- Runtime manifests and receipts remain private machine-local artifacts.

## Expected Questions

- Whether any source template exists in production that was never exercised by the prior migration inventory.
- Whether deletion receipt ordering survives a crash between filesystem deletion and atomic manifest replacement.
- Whether filesystem snapshots or external backups need a separate privacy-retention policy.

## Destination

- Amend this plan when a learning changes deletion, verification, or recovery work.
- Search all idea quadrants before creating a distinct future brief; do not duplicate the existing rollout or storage plans.

## Log

- 2026-08-29 — User explicitly authorized deletion once legacy data is genuinely migrated and asked for meticulous migration proof.
- 2026-08-29 — No arbitrary waiting period is required, but repository migration rules require deletion to be a separately gated contraction after SQLite activation.
- 2026-08-29 — Storage configuration and retirement status UI is restricted to authenticated users whose current server-side role set includes `admin`.
