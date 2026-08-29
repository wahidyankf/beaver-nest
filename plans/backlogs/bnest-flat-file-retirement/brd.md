# Business Requirements

## Goal

Permanently remove Bnest's old flat-file data as soon as SQLite is proven authoritative, while making it impossible for an incomplete, changed, unsupported, or unrelated source to be deleted by the retirement operation.

## Roles

- **Family member:** continues authenticated Bnest journeys without a storage-visible change.
- **Administrator:** may view SQLite storage status, but does not manually select deletion targets.
- **Maintainer:** authorizes execution of the queued plan and verifies value-free deletion outcomes.
- **Retirement coordinator:** matches evidence, serializes contraction, deletes exact files, and fails closed.

## Required Outcomes

- Every deleted file was first validated, migrated, normally read back from SQLite, checksum-matched, and included in the private retirement manifest.
- SQLite is the only application reader/writer before the first deletion.
- Unknown, malformed, changed, unproven, or unrelated files remain untouched and block a false “complete” result.
- Retrying after interruption does not delete an unexpected file or misreport a missing target.
- Local and routed Bnest behavior remains healthy after restart and deletion.

## Business Rules

- Deletion targets come only from compiled allow-listed templates plus verified migration evidence; no browser or arbitrary path input can add a target.
- A file whose current checksum differs from its migration receipt is not deleted.
- A previously deleted file counts as complete only when its manifest item already records an accepted deletion receipt.
- The shared runtime root, unknown siblings, directory placeholders, SQLite, backups, and evidence are never recursive deletion targets.
- Completion does not claim secure erasure from snapshots or hardware-level remnants.

## Non-goals

- Deleting general repository runtime infrastructure used by other applications.
- Removing SQLite recovery, migration, or retirement evidence.
- Changing authentication, authorization, feature payloads, or database location.

## Risks and Controls

- **Wrong target:** fixed path templates, normalized containment, no symlinks, exact checksum, and file-by-file deletion.
- **Incomplete migration:** full source/evidence/target join plus normal SQLite read-back before contraction.
- **Rollback loss:** active and previous eligible artifacts must both use SQLite; restore rehearsal precedes deletion.
- **Partial deletion:** transactional receipt ordering, fsync where applicable, and idempotent retry.
- **Service degradation:** independent candidate, Caddy promotion, revision proof, LiveView/WebSocket reconnect, drain, cleanup, and SQLite-only rollback.
- **Private evidence exposure:** receipts remain machine-local and logs expose only migration IDs, generic record types, and outcome categories.

## Success Measures

- Zero allow-listed legacy source files remain after verified deletion.
- Zero unknown or unrelated files change.
- Every manifest item ends `deleted` with pre-delete checksum and target proof, or safely blocks completion.
- SQLite integrity, isolated restore, restart, representative journeys, and routed revision remain green.
