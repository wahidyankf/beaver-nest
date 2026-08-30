# Business Requirements

## Problem

The family application depends on one production SQLite database. A device, filesystem, or operator failure could remove irreplaceable household data, while administrators currently have no application-owned view of recurring operational work or its outcomes.

## Goal

Give administrators a reliable daily SQLite backup, one reusable contextual scheduler, and one trustworthy settings dashboard for every parameter Bnest expects an admin to manage.

## Roles

- **Admin:** chooses the private backup destination, sees schedules and safe operational details, and acts on failures.
- **Non-admin household member:** continues using Bnest without access to schedule, filesystem, or backup information.
- **Bn​est release operator:** performs compatible schema expansion, no-downtime promotion, routed proof, and recovery.

## Outcomes

- One verified production SQLite backup is attempted each day at 02:00 WIB.
- Schedule and run state survives application restart.
- Blue/green release overlap never creates two artifacts for one scheduled slot.
- The admin dashboard accurately shows enabled daily schedules, next execution, current state, and last safe result.
- An admin can reach the dashboard from the normal admin home without manually entering a URL.
- Family-purpose schedules and admin/system-only schedules remain visibly and structurally separated while sharing one execution mechanism.
- Every admin-editable parameter is discoverable from Admin settings and validated by its owning domain.
- A schedule may never expire, expire at a date/time, or expire after a bounded number of unique occurrences.
- Backup failure preserves the active application and last verified backup.

## Business Rules

- SQLite is the only production data source in scope; retired flat files are never consulted.
- Only a current server-authorized admin can read or change schedule/backup information.
- The admin home shows the schedules entry point only for a current admin; hidden navigation never replaces route authorization.
- Every schedule declares `family` or `admin_system` context; context classifies purpose and presentation, never grants authorization.
- Expiration counts schedule occurrences, not retry attempts. Production backup is fixed to never expire so protection cannot stop silently.
- The destination defaults to Git-ignored repository `data/backup/` so closed snapshots are Dropbox-synced; live SQLite remains outside Dropbox. An admin may select a safe override.
- Bnest deletes only verified artifacts it owns in the current marked destination and keeps at most the newest pair for each of the latest seven WIB calendar days.
- Schedules are application-defined and persisted; dashboard users cannot supply executable code or arbitrary cron.
- Admin settings is a typed registry of domain-owned panels, not a generic key/value editor. Handler keys, contexts, executable code, retry policy, and protected boundaries are never editable.
- Backup content is never downloadable from the dashboard.

## Success Measures

- Focused automated proof covers persistence, catch-up, exact-once claiming, no overlap, retry, retention, and authorization.
- The first default or overridden backup is independently opened and verified.
- Candidate rollout proves the intended routed revision and LiveView/WebSocket state recovery without refresh.
- No new external package is required for the approved allowlisted-daily-schedule scope.
- Adding another allowlisted daily schedule in either context reuses the same tables, coordinator, supervised runner, and dashboard inventory.

## Non-goals

- A generic key/value settings editor, user-authored executable jobs, arbitrary cadence expressions, or a family-facing schedules page.
- Backing up retired flat files, browser state, credentials, Codex state, or repository content other than final ignored backup artifacts.
- Automated restore, backup download, remote-object storage, encryption/key management, or a promise that Dropbox alone is complete disaster recovery.

## Risks

- Dropbox synchronization improves off-machine availability but is not a complete tested disaster-recovery or version-retention guarantee; separate remote recovery design remains future scope.
- SQLite permits one writer, so claim transactions must be immediate and short.
- A process may die during backup; leases and exact owned partial names must make recovery deterministic.
- Filesystem paths are sensitive operational data and must not enter run rows, logs, telemetry, or non-admin responses.
