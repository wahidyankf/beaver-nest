# Learnings

## Capture Timing

- Record discovery before editing when implementation differs from the plan's source inventory, readers, writers, release state, or active-route baseline.
- Record a dated note after every phase checkpoint, migration interruption, rollback, restore rehearsal, routed proof, and final reconciliation.
- Record only durable reasoning or a transient fact needed to resume; do not copy command noise.

## Safe Evidence

- Allowed: revision identifiers, migration IDs/checksums, schema versions, generic record types, outcome categories, target names, durations, and pass/fail states.
- Prohibited: usernames, user IDs, token digests, account counts tied to a household, payloads, hostnames, absolute custom paths, cookies, credentials, or database/recovery contents.
- Production inspection remains structural and read-only until an explicitly authorized migration transition.

## Expected Questions

- Whether the selected SQLite adapter behaves correctly with two local release processes and WAL sidecars.
- Whether the existing repository facade can stay stable or needs a narrower backend behaviour.
- Whether the storage path and migration state can be activated dynamically without restarting the sole backend.
- Whether a rollback mirror/outbox is necessary for every record type or can be proven synchronous under one coordinator.

## Destination

- Amend this plan when a learning changes current delivery, verification, or acceptance work.
- Merge general rollout learning into [`plans/ideas/q1-urgent-important/zero-downtime-local-rollouts.md`](../../ideas/q1-urgent-important/zero-downtime-local-rollouts.md).
- Search all idea quadrants before adding a new brief; create one only for a distinct, evidenced future problem such as encrypted-at-rest storage or post-cutover flat-file retirement.

## Log

- 2026-08-29 — Planning inventory confirmed that SQLite had not yet been selected and the existing release controller deliberately rejects non-empty migration sets until a concrete adapter is approved.
- 2026-08-29 — Default migration must run through managed/headless tooling without a storage-UI visit; UI is optional only for a custom pre-migration folder and status/retry review.
- 2026-08-29 — SQLite activation occurs automatically after verified migration; repository migration rules require legacy flat-file deletion to run through the separately authorized retirement plan, which has no arbitrary waiting period beyond its safety gates.
