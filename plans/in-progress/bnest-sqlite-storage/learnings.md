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
- 2026-08-29 — StorageLive's mount/refresh path called `Config.phase()`/`resolved_database_path()` for display, but an earlier draft's read helper had the side effect of writing a default pointer on first read; that would have locked in the default location on mere page load, before an admin ever chose a custom folder. Fixed so only an explicit action (`move_data` event or the CLI migrate task) calls `Config.ensure_default!/0`. Reads must stay reads.
- 2026-08-29 — E2E CLI scenarios spawn `mix` with an overridden `HOME` (per-scenario storage isolation) but asdf's `mix` shim resolves its own version via `$HOME/.asdf`; overriding `HOME` alone breaks the shim (exit 126). Fix: pass `ASDF_DIR`/`ASDF_DATA_DIR` derived from the real `os.homedir()` alongside the scratch `HOME`.
- 2026-08-29 — Rollback mirror/outbox question (see Expected Questions) resolved by explicit user decision: `StorageCoordinator.active_backend/1` routes each write to exactly one backend once `sqlite_primary`, so no live dual-write exists. Decision: accept the flat-file tree as a point-in-time snapshot taken at migration, not a continuously-current rollback target. Rollback means restoring that snapshot or reverting the pre-cutover code revision — not flipping the phase pointer back after further SQLite writes have occurred. Documented in delivery.md Phase 3; no further build work follows.
- 2026-08-29 — Every test layer confirmed isolated to its own SQLite storage: unit tests never touch a repo; each integration test gets a random-suffixed `TestRuntimeRoot` + pointer + db (`async: false`); each E2E CLI scenario gets a digest-keyed scratch dir under the OS tmp dir, wiped before and cleaned after; E2E admin-UI/live-server scenarios share one pointer only within their own run's random `BNEST_E2E_RUNTIME_ROOT`, swept by globalTeardown. No suite or scenario shares a database/pointer with another.
- 2026-08-29 — During production release, `chat.feature`'s "An automatic LiveView reconnect safely restores a persisted in-progress user-owned turn" (the interrupted-response alert, `browser.steps.ts:256`) intermittently failed its 5000ms assertion across three separate release attempts, each time on a different viewport project (chromium, tablet-chromium, mobile-chromium) — never twice on the same project, and clean in an isolated standalone rerun. This scenario predates this plan and touches no storage code; the flat_primary backend (unchanged `Store`) was the only one exercised. Root cause: sustained high background CPU load on the release host that day (independently confirmed via repeated `resource-monitor` capacity deferrals — Spotlight indexing, media analysis, and normal desktop load pushing system-wide CPU near the release tool's own 6-core headroom threshold) made this already-tight 5s timing assertion flaky. Not a regression from this plan; worth hardening the assertion's timeout or the alert's render path separately, out of this plan's scope.
