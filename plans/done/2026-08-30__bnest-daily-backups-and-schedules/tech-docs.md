# Technical Design

## Current State

Bnest's authoritative production data is the SQLite database resolved by `BnestApp.Storage.Config`; retired repository flat files are not a backup source. Existing storage relocation already uses SQLite `VACUUM INTO` and logical proof, but there is no recurring backup process, durable schedule ledger, private backup-destination configuration, or application-owned schedule inventory.

The existing `/storage` route is server-side admin-only but there is no central inventory for admin-owned configuration. This plan adds `/admin/settings` and `/admin/settings/schedules` under the same authenticated `admin_only` pipeline. Admin home links to both the settings index and its schedules shortcut; non-admin users see neither.

The managed release controller currently emits an empty migration set and rejects any non-empty set without an approved adapter. Execution must therefore add and test the named schedule-schema adapter before a candidate can start; merely adding an Ecto migration would leave production rollout blocked.

## Requirements and Assumptions

- Back up only the authoritative production SQLite database; never copy retired flat files, WAL/SHM files, repository data, browser storage, Codex state, or credentials.
- Default `prod-sqlite-backup-daily` to `02:00 WIB (UTC+07:00)` and let an admin change its enabled state and daily WIB time.
- Default the destination to `@data/backup/`, meaning repository-root `data/backup/`, and let an admin choose a validated safe override.
- Keep at most one newest verified owned pair for each of the latest seven WIB calendar dates; preserve unknown files and every backup in a previous destination.
- Persist each schedule's `family` or `admin_system` context, claims, retries, and safe results in SQLite so restart and blue/green overlap cannot lose or duplicate a due run.
- Reuse one scheduler core for every allowlisted daily handler; do not build backup-specific scheduling machinery.
- Show persisted daily schedules in separate Family and Admin/system groups with next run, state, last result, and safe recovery guidance.
- Make every admin-editable configuration area discoverable through one code-declared Admin settings registry while preserving domain-owned validation and persistence.

## Decision

Use built-in Elixir/OTP supervision: a generic `GenServer` wakes on `Process.send_after/3`, SQLite is the scheduling source of truth, and a named `Task.Supervisor` runs allowlisted handlers from both contexts. Do not add Oban, Quantum, a cron parser, or a timezone package.

OTP is capable of the process lifecycle and execution needed here. A timer alone is not durable, so each wake-up atomically claims due work and advances its schedule in SQLite. The application reconciles overdue schedules and expired leases at startup. Schedule rows store a fixed UTC daily time and display offset; `02:00 WIB` is `19:00 UTC` on the preceding date, and WIB has no daylight-saving transition. IANA timezone support becomes a new decision only if schedules with offset transitions are required.

This is smaller than adopting a job framework for allowlisted daily workloads and follows the repository's [dependency-selection standard](../../../repo-governance/development/dependency-selection.md). Adding another daily handler reuses persistent contextual schedules, unique claims, bounded retry, missed-run recovery, no overlap, safe history, and supervised execution.

Use a code-owned `AdminConfig.Registry` to enumerate typed settings panels. The registry stores no values and accepts no dynamic modules. Each panel declares its key, label, admin authorization, owner module, editable fields, and safe summary in code; its domain performs reads, validation, and atomic save. The initial index registers existing **Data storage** as a link to its owner and **Schedules & backups** as the new panel. The scheduler registry owns presentation labels and fixed timezone metadata; schedule enabled/time and permitted expiry stay in SQLite. An optional destination override stays in private `backup.json`; seven-day retention is code-owned, not editable. Separate owner forms prevent a cross-store partial save.

### Scheduler Alternatives

| Option                                | Benefit                                                                        | Cost or gap                                                                                         | Decision                                    |
| ------------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| OTP wake-up plus SQLite ledger        | Reuses the runtime and makes claims, history, context, and admin reads durable | Bnest owns a small daily-only coordinator                                                           | Selected for the approved scope             |
| Oban, Quantum, or another job package | Supplies broader scheduling features                                           | Adds dependencies and abstractions not needed by allowlisted daily jobs                             | Revisit only when scope triggers justify it |
| Host cron invoking Bnest              | Simple outside-process wake-up                                                 | Splits ownership and still needs in-app claims, context, history, configuration, and overlap safety | Rejected                                    |

## Architecture

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    admin[Admin browser] --> home[Admin home]
    home --> settings[Admin settings]
    settings --> panels[Typed settings panels]
    panels --> inventory[Contextual inventory]
    inventory --> schedules[(Schedule ledger)]
    timer[OTP wake-up] --> scheduler[Schedule coordinator]
    schedules --> scheduler
    scheduler -->|Atomic claim| runs[(Run ledger)]
    scheduler --> tasks[Task supervisor]
    tasks --> handlers[Allowlisted handlers]
    handlers --> backup[SQLite backup]
    backup -->|VACUUM INTO| source[(Production SQLite)]
    backup --> target[(Backup folder)]
    target -.-> sync{{Dropbox desktop sync}}
    backup --> runs

    classDef person fill:#808080,stroke:#000000,color:#000000
    classDef app fill:#0173B2,stroke:#000000,color:#ffffff
    classDef data fill:#029E73,stroke:#000000,color:#000000
    classDef external fill:#DE8F05,stroke:#000000,color:#000000
    class admin person
    class home,settings,panels,inventory,timer,scheduler,tasks,handlers,backup app
    class schedules,runs,source,target data
    class sync external
```

The dotted edge means the host's existing Dropbox client observes the ignored folder; Bnest itself performs no network transfer and does not treat synchronization as complete disaster recovery.

`BnestApp.Application` starts the existing data repository/SQLite repo, the named `Task.Supervisor`, then the scheduler before the endpoint. The scheduler contains no backup business logic: it asks the store for due claims, resolves stored `handler_key` through a code allowlist, and supervises the task. Registry entries require a `family` or `admin_system` context. Production readiness checks schema and coordinator liveness, but a failed handler does not take the family application offline. Tests disable automatic ticking and inject a clock.

## Persistent Scheduling Model

Add an expand-only Ecto migration with these logical tables:

### Logical ERD

```mermaid
erDiagram
    direction TB
    BNEST_SCHEDULES ||--o{ BNEST_SCHEDULE_RUNS : owns

    BNEST_SCHEDULES {
        text schedule_key PK
        text handler_key
        text schedule_context
        text cadence
        text expiration_kind
        integer claimed_occurrences
        text next_run_at
        integer revision
    }

    BNEST_SCHEDULE_RUNS {
        text schedule_key PK, FK
        text claim_key PK
        text claim_kind
        text scheduled_for
        text run_id UK
        integer schedule_revision
        integer occurrence_number
        integer attempt
        text state
        text lease_expires_at
        text artifact_basename
    }
```

In the ERD, `PK` means the column participates in the primary key, `FK` points to a parent row, `||` means exactly one parent schedule, and `o{` means zero or many run rows.

One schedule owns many historical claims. The composite key `(schedule_key, claim_key)` is the duplicate barrier. A daily claim uses `claim_key = "slot:" || scheduled_for`; a destination-setup claim uses `claim_key = "setup:" || destination_id`. Retries update that claim's attempt and state rather than creating another occurrence, and repeated saving of one destination cannot create another setup claim.

```sql
CREATE TABLE bnest_schedules (
  schedule_key TEXT PRIMARY KEY,
  handler_key TEXT NOT NULL,
  schedule_context TEXT NOT NULL CHECK
    (schedule_context IN ('family', 'admin_system')),
  cadence TEXT NOT NULL CHECK (cadence = 'daily'),
  daily_at_utc TEXT NOT NULL CHECK
    (daily_at_utc GLOB '[0-2][0-9]:[0-5][0-9]'),
  enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
  expiration_kind TEXT NOT NULL CHECK
    (expiration_kind IN ('never', 'at', 'after_occurrences')),
  expires_at TEXT,
  max_occurrences INTEGER CHECK
    (max_occurrences IS NULL OR max_occurrences > 0),
  claimed_occurrences INTEGER NOT NULL CHECK (claimed_occurrences >= 0),
  expired_at TEXT,
  next_run_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (
    (expiration_kind = 'never' AND expires_at IS NULL AND max_occurrences IS NULL) OR
    (expiration_kind = 'at' AND expires_at IS NOT NULL AND max_occurrences IS NULL) OR
    (expiration_kind = 'after_occurrences' AND expires_at IS NULL AND max_occurrences IS NOT NULL)
  )
);

CREATE TABLE bnest_schedule_runs (
  schedule_key TEXT NOT NULL REFERENCES bnest_schedules(schedule_key),
  claim_key TEXT NOT NULL,
  claim_kind TEXT NOT NULL CHECK (claim_kind IN ('scheduled', 'setup')),
  scheduled_for TEXT,
  run_id TEXT NOT NULL UNIQUE,
  schedule_revision INTEGER NOT NULL CHECK (schedule_revision >= 1),
  occurrence_number INTEGER CHECK
    (occurrence_number IS NULL OR occurrence_number >= 1),
  attempt INTEGER NOT NULL CHECK (attempt >= 1),
  state TEXT NOT NULL CHECK (state IN
    ('running','retryable','verified','failed','skipped')),
  lease_expires_at TEXT,
  next_attempt_at TEXT,
  artifact_basename TEXT,
  artifact_sha256 TEXT,
  artifact_bytes INTEGER CHECK (artifact_bytes IS NULL OR artifact_bytes >= 0),
  failure_category TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  PRIMARY KEY (schedule_key, claim_key),
  CHECK (
    (claim_kind = 'scheduled' AND claim_key = 'slot:' || scheduled_for AND
      scheduled_for IS NOT NULL AND occurrence_number IS NOT NULL) OR
    (claim_kind = 'setup' AND claim_key LIKE 'setup:%' AND
      scheduled_for IS NULL AND occurrence_number IS NULL)
  )
);

CREATE INDEX bnest_schedules_due_idx
  ON bnest_schedules(enabled, expired_at, next_run_at);
CREATE INDEX bnest_schedules_context_idx
  ON bnest_schedules(schedule_context, schedule_key);
CREATE INDEX bnest_schedules_expiry_idx
  ON bnest_schedules(expired_at, expiration_kind, expires_at);
CREATE INDEX bnest_schedule_runs_retry_idx
  ON bnest_schedule_runs(state, next_attempt_at, lease_expires_at);
```

### Column Guide

Except for `daily_at_utc`, every time column stores a full UTC ISO 8601 instant. `daily_at_utc` stores only strict `HH:MM`; the code-owned registry presents it as fixed `WIB (UTC+07:00)`. `Scheduler.Store` produces every column and supplies every value explicitly because the schema has no implicit defaults. Non-null columns are never cleared; nullable policy, lease, artifact, failure, and completion fields are cleared only on the state transitions described below. Schedule keys, run IDs, basenames, timestamps, sizes, and digests are safe operational metadata, but no row may contain an absolute path, user identity, payload, credential, or other private value.

#### `bnest_schedules`

| Column                | Purpose                                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `schedule_key`        | Stable code-owned identifier for one application schedule; run rows reference it.                                          |
| `handler_key`         | Safe allowlist key resolved to executable code; it is never a module or function supplied by the database.                 |
| `schedule_context`    | Classifies the schedule as `family` or `admin_system` for policy-bound reads and grouped presentation.                     |
| `cadence`             | Recurrence kind. This version accepts only `daily`.                                                                        |
| `daily_at_utc`        | UTC `HH:MM` at which each daily slot becomes due; `02:00 WIB` is stored as `19:00` UTC.                                    |
| `enabled`             | Controls whether the coordinator may create new run claims. Disabling preserves definition and history.                    |
| `expiration_kind`     | Selects `never`, absolute `at`, or `after_occurrences` expiration behavior.                                                |
| `expires_at`          | Exclusive UTC cutoff for `at`; claims at or after this instant are blocked. Null for other expiration kinds.               |
| `max_occurrences`     | Maximum unique scheduled slots allowed for `after_occurrences`. Null for other expiration kinds.                           |
| `claimed_occurrences` | Unique slots claimed in the current lifecycle; retries never increment it. A validated reactivation resets it.             |
| `expired_at`          | UTC instant when the coordinator marked the lifecycle expired. Null while it remains eligible.                             |
| `next_run_at`         | Exact next UTC slot considered by due reconciliation; a schedule is due when this is at or before `now`.                   |
| `revision`            | Optimistic-concurrency version incremented by a validated configuration or reactivation change and copied into each claim. |
| `inserted_at`         | UTC instant when the schedule row was first created.                                                                       |
| `updated_at`          | UTC instant of the latest accepted schedule-row change.                                                                    |

#### `bnest_schedule_runs`

| Column              | Purpose                                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `schedule_key`      | Parent schedule identifier and first half of the composite primary key.                                                  |
| `claim_key`         | Second primary-key field: `slot:<UTC instant>` for one daily slot or `setup:<destination ID>` for one destination setup. |
| `claim_kind`        | Code-owned `scheduled` or `setup`; it controls the cross-field constraint and whether the claim consumes an occurrence.  |
| `scheduled_for`     | Logical UTC slot for a scheduled claim; null only for setup, whose claim key supplies its idempotent identity.           |
| `run_id`            | Random base64url identifier generated once with the claim, unique across rows, and reused in the owned artifact pair.    |
| `schedule_revision` | Snapshot of the schedule revision at claim time, preserving which configuration produced the run.                        |
| `occurrence_number` | One-based scheduled-slot number within the lifecycle; every retry retains it and setup claims leave it null.             |
| `attempt`           | One-based attempt currently represented by the row; incremented for a retry and capped at three.                         |
| `state`             | Current safe lifecycle result: `running`, `retryable`, `verified`, `failed`, or `skipped`.                               |
| `lease_expires_at`  | UTC deadline protecting a running attempt from overlap; after it passes, reconciliation may recover the abandoned work.  |
| `next_attempt_at`   | Earliest UTC instant when a `retryable` row may run again; null outside retry waiting.                                   |
| `artifact_basename` | Safe filename of a verified backup artifact, never an absolute path; null for non-artifact or unfinished runs.           |
| `artifact_sha256`   | SHA-256 digest of the verified final artifact; null until verification succeeds.                                         |
| `artifact_bytes`    | Verified final artifact size in bytes; null until verification succeeds.                                                 |
| `failure_category`  | Allowlisted value-free reason for retry, failure, or skip; never contains a path, payload, or exception dump.            |
| `started_at`        | UTC instant when the current or latest attempt began; a retry replaces it with that attempt's start.                     |
| `finished_at`       | UTC instant when the current or latest attempt ended; null while that attempt is running.                                |

The due, context, expiry, and retry indexes keep coordinator and dashboard queries bounded as history grows; they do not change the ownership or uniqueness rules above.

The release seeds `prod-sqlite-backup-daily` with handler `prod_sqlite_backup`, context `admin_system`, UTC time `19:00`, expiration `never`, zero claimed occurrences, and revision `1`. Its initial `next_run_at` is the most recent `19:00 UTC` slot at or before migration time so startup creates one catch-up backup instead of waiting up to a day or replaying history. Production backup's registry policy fixes expiration to `never` and display timezone to `WIB (UTC+07:00)` so protection cannot stop silently. Another schedule may expose `never`, an absolute `at` entered/displayed in WIB and stored in UTC, or positive `after_occurrences` through its typed admin panel.

There are no implicit schema defaults: migrations and store commands supply every value. The store validates strict `HH:MM`, UTC ISO 8601, known context/cadence/state/expiration values, compatible nullable expiration fields, positive limits/revisions/attempts, and allowlisted schedule/handler pairs. Executable module/function names never come from SQLite. A future daily schedule in either context adds a migration plus allowlist entry and reuses the same coordinator, supervisor, tables, claims, retries, expiry logic, and read models.

Context is classification plus a presentation boundary. The admin reader returns both contexts in separate groups. Any future family-facing reader must request only `family`; no public unscoped list exists. Context never grants access by itself.

Registry policy declares which schedule fields an admin may edit. Saving enabled state or daily time uses one immediate SQLite transaction, increments `revision`, and recomputes the next future occurrence without creating a retroactive run. Expiry editing is exposed only when the registry entry permits it. Handler, context, cadence kind, retry/lease policy, and executable code are always code-owned. Invalid or stale revisions change nothing and return a conflict-safe form error.

Every minute, and once at startup, the coordinator opens `Repo.transaction(mode: :immediate)` to serialize writers. It first expires absolute policies whose instant has arrived, without catch-up. It then finds due enabled, unexpired schedules or retryable/expired leases, inserts the unique run claim, increments `claimed_occurrences` once per scheduled slot, and advances `next_run_at` atomically. A final `after_occurrences` claim also sets `expired_at` but still dispatches that final run. Setup claims never change the occurrence counter. Retry attempts reuse the claim and occurrence number and never increment either counter.

When multiple days were missed, startup creates at most one latest-slot catch-up only if the schedule is still unexpired, then moves `next_run_at` forward; it never manufactures obsolete snapshots. A running claim starts with a 15-minute lease and renews it every minute in a short immediate transaction. An expired lease becomes retryable; the attempt number is a fencing token checked before final rename and ledger completion. Transient failures retry after 5 minutes and then 30 minutes, for at most three attempts; permanent/configuration failures become `failed` or `skipped`. An explicitly editable expired schedule can start a new revision only through a validated admin action that sets a new policy, resets the lifecycle occurrence counter, recomputes the next future run, and explicitly enables it; history remains in the run ledger.

```mermaid
stateDiagram-v2
    direction TB
    [*] --> Running
    Running --> Verified: proof passes
    Running --> Retryable: transient failure
    Retryable --> Running: retry due
    Running --> Failed: permanent failure
    Running --> Skipped: policy blocks
    Retryable --> Failed: attempt limit
```

Rows contain no absolute path, payload, or user identity. The down migration refuses while schedule/run records exist.

### Migration Inventory and Transition

| Source or record                                                       | Current owner/readers/writers                                                   | Result and disposition                                                                                                                                           |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authoritative SQLite at the path resolved by `BnestApp.Storage.Config` | `BnestApp.SqliteRepo` and existing repository domains read/write current tables | The approved release adapter adds only the two schedule tables, indexes, and one idempotent seed; existing tables and rows remain untouched.                     |
| Schedule and run records                                               | No current source, reader, or writer                                            | `Scheduler.Store` becomes the sole writer; coordinator, handlers, readiness, and policy-bound admin/family readers consume the new rows.                         |
| `~/.config/bnest/backup.json`                                          | No current file or reader/writer                                                | `Backup.Config` becomes the sole reader/writer; absence continues to mean repository-root `data/backup/`.                                                        |
| Current destination ownership marker                                   | No current marker owner                                                         | `Backup.Location` creates/reads the exact marker below; an absent marker claims only future Bnest pairs, while a malformed or mismatched marker blocks mutation. |
| Backup artifact and receipt pairs                                      | No current Bnest-owned pairs                                                    | `Backup.Run` writes and `Backup.Receipt` verifies them; unknown pre-existing files remain opaque and untouched.                                                  |

1. **Expand:** add `BnestApp.Release.Migrations.PersistentSchedules`, declare `bnest-persistent-schedules-v1` and its checksum in the immutable release manifest, and run the adapter under the release/storage locks before candidate startup. The adapter applies the exact Ecto migration idempotently, reconciles the seed, and verifies tables, indexes, constraints, and seed policy.
2. **Migrate:** there are no old schedule, run, backup-config, marker, receipt, or artifact records to copy. The only initialization is the deterministic schedule seed; unknown destination files are preserved opaque and never adopted.
3. **Verify:** read the seeded row through `Scheduler.Store`, prove a repeat adapter run is a no-op, start the candidate, and create/open one isolated verified snapshot through the normal handler before promotion.
4. **Contract:** the previous release continues to read and write existing SQLite tables while ignoring the additive tables. Rollback leaves the expanded schema, seed, private config, marker, and verified pairs in place. Destructive table or artifact retirement requires a later explicit plan.

If adapter apply or verification fails, the release controller rejects the candidate and keeps the active route. The adapter is retryable with the same manifest identity and must neither duplicate the seed nor rewrite an existing valid schedule. Slot startup never applies migrations implicitly.

## Private Configuration and Artifacts

With no override, `BnestApp.Backup.Config` resolves `@data/backup/` to `<repo-root>/data/backup/`. This exact ignored runtime directory is the only repository-contained destination allowed. It exists under the Dropbox-synced repository so completed immutable snapshots sync, while the authoritative live SQLite database remains outside Dropbox.

An optional pointer at `~/.config/bnest/backup.json`, or test-only `BNEST_BACKUP_CONFIG`, is atomically written `0600` beneath a `0700` parent:

```json
{
  "schemaVersion": 1,
  "destinationDirectory": "<absolute-private-folder>"
}
```

The exact destination marker and receipt shapes are:

```json
{
  "schemaVersion": 1,
  "ownershipScope": "bnest-production-backups-v1",
  "destinationId": "<22-char-base64url>",
  "createdAt": "<UTC-ISO-8601>"
}
```

```json
{
  "schemaVersion": 1,
  "ownershipScope": "bnest-production-backups-v1",
  "destinationId": "<22-char-base64url>",
  "scheduleKey": "prod-sqlite-backup-daily",
  "claimKind": "scheduled",
  "claimKey": "slot:<UTC-ISO-8601>",
  "scheduledFor": "<UTC-ISO-8601>",
  "runId": "<22-char-base64url>",
  "scheduleRevision": 1,
  "createdAt": "<UTC-ISO-8601>",
  "sourceGeneration": null,
  "artifactBasename": "bnest-prod-<utc-timestamp>-<run-id>.sqlite3",
  "artifactSha256": "<sha256>",
  "artifactBytes": 1,
  "quickCheck": "ok",
  "schemaVersions": [20260829000000, 20260830000000],
  "logicalProofSha256": "<sha256>"
}
```

### Private Record Field Guide

| Record / field                | Purpose, producer, null/default, and lifecycle                                                                                                            |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config `schemaVersion`        | Required integer `1`, written by `Backup.Config`; no in-file default and changed only by a future migration.                                              |
| Config `destinationDirectory` | Required sensitive absolute path written atomically by `Backup.Config`; never logged or stored in SQLite; deleting the whole config restores the default. |
| Marker `schemaVersion`        | Required integer `1`, written once by `Backup.Location`; no default.                                                                                      |
| Marker `ownershipScope`       | Required fixed `bnest-production-backups-v1`; rejects another owner or schema.                                                                            |
| Marker `destinationId`        | Required random 22-character base64url ID generated once; never null or changed in place and referenced by setup claims and receipts.                     |
| Marker `createdAt`            | Required UTC creation instant written once; never updated.                                                                                                |
| Receipt `schemaVersion`       | Required integer `1`, written by `Backup.Receipt`; no default.                                                                                            |
| Receipt `ownershipScope`      | Required fixed scope matching the current marker.                                                                                                         |
| Receipt `destinationId`       | Required reference to the current marker; a mismatch makes the pair unowned.                                                                              |
| Receipt `scheduleKey`         | Required code-owned schedule identifier referencing the ledger parent.                                                                                    |
| Receipt `claimKind`           | Required `scheduled` or `setup`, copied from the run row.                                                                                                 |
| Receipt `claimKey`            | Required composite-key value copied from the run row and unique within its schedule.                                                                      |
| Receipt `scheduledFor`        | Required UTC slot for `scheduled`; null only for `setup`.                                                                                                 |
| Receipt `runId`               | Required random run-row ID used in both owned basenames.                                                                                                  |
| Receipt `scheduleRevision`    | Required positive schedule revision captured by the claim.                                                                                                |
| Receipt `createdAt`           | Required UTC finalization instant; the immutable receipt is never updated.                                                                                |
| Receipt `sourceGeneration`    | Storage pointer generation string, or null only when the existing pointer has none.                                                                       |
| Receipt `artifactBasename`    | Required basename only, never a path; must equal the final SQLite filename derived from `createdAt` and `runId`.                                          |
| Receipt `artifactSha256`      | Required lowercase SHA-256 of the final artifact, produced after independent open.                                                                        |
| Receipt `artifactBytes`       | Required positive byte size of the final artifact.                                                                                                        |
| Receipt `quickCheck`          | Required literal `ok`, produced by the independent candidate connection.                                                                                  |
| Receipt `schemaVersions`      | Required ascending non-empty integer list read from `schema_migrations`; immutable after finalization.                                                    |
| Receipt `logicalProofSha256`  | Required lowercase SHA-256 of the canonical value-free storage proof; never a payload digest exposed to the UI.                                           |

Every JSON record rejects unknown keys. A marker is private operational metadata and must not be copied into logs or committed. The validator permits the exact resolved default or an absolute, existing or creatable, writable, non-symlinked override. An override must be outside the repository; the authoritative database directory and its ancestors/descendants; the storage/backup configuration directory and its ancestors/descendants; all production and marked test roots; and current deployment/runtime roots. The only repository exception is exact `data/backup/`. Marker creation never claims pre-existing files. The repository's existing `/data/*` ignore rule already covers the default; release/readiness uses `git check-ignore` and rejects a tracked marker or artifact. Unsupported permissions, overlap, any other repository path, or a changed marker blocks configuration. Changing the destination never moves or deletes old backups.

```text
<backup-folder>/
├── .bnest-backup-root.json
├── bnest-prod-<utc-timestamp>-<run-id>.sqlite3
└── bnest-prod-<utc-timestamp>-<run-id>.receipt.json
```

The receipt contains schema version, schedule/run identity, UTC time, source generation, artifact basename, SHA-256, byte size, and `quick_check` outcome. It contains no absolute path, record count, account identity, or payload. Artifacts are `0600`; temporary files use the same directory and `.partial` suffix.

## Backup Flow

1. The task reads the claimed schedule/run identity; the destination is never passed in logs or persisted run payloads.
2. It confirms `sqlite_primary` and production profile, reads the current private destination, and validates its marker. A setup claim proceeds only when its `setup:<destination ID>` key matches that marker; a later destination change safely skips the stale setup claim and creates/reuses the new destination's claim.
3. It requires destination free space of at least twice the current source database byte size plus 256 MiB, creates an exact owned partial name, and runs `VACUUM INTO` through the authoritative repo. Raw file copy is forbidden.
4. It opens the candidate independently, runs `PRAGMA quick_check`, compares schema versions, and computes a value-free logical checksum in the backup proof routine, then fsyncs and atomically renames the artifact.
5. It writes the receipt atomically and marks the run `verified`. It keeps the newest verified owned pair for each of the current and previous six WIB dates, removing older-date and superseded same-date owned pairs only after verification. Unknown, unowned partial, mismatched, or previous-folder files remain untouched.
6. Invalid destination policy or an ownership-marker mismatch records `skipped` with a safe category. Transient availability, capacity, or SQLite failures become retryable. A corrupt candidate is removed only by its exact owned partial path; the last verified backup remains.

Snapshot creation uses a destination-local `.partial` name, private permissions, fsync, verification, then atomic rename to the final `.sqlite3` name. Dropbox may observe a clearly partial transient file but never treats it as a final Bnest artifact; interrupted owned partials are reconciled by exact name. Bnest never opens a final backup for mutation.

The default works headlessly without an admin visit. Saving a valid override creates one idempotent setup claim so the new location is proved without waiting until the next day. Repeated submission cannot create concurrent backups.

## Restore and Recovery

Automated restore is out of scope. Delivery proves the newest verified artifact opens in an isolated marked test destination, passes integrity/schema checks, and serves normal repository reads. Operational recovery validates a selected artifact, then changes the storage pointer through existing relocation/recovery controls; it never overwrites the active database.

If a release stops mid-backup, startup reconciles the expired lease and retries. If the destination disappears, the application remains healthy, the run becomes retryable/failed, and the dashboard keeps the last verified result plus corrective guidance. Rollback uses the previous compatible release against the expanded schema and does not remove schedule tables or backup files.

## UI Design

The user is an authenticated admin entering **Admin settings**, then **Schedules & backups**. Real copy includes **Family schedules**, **Admin/system schedules**, **Production database backup**, **Enabled**, **Daily time (WIB)**, **Expiration: Never**, **Backup folder**, **Default: @data/backup/**, **Keep one per day for 7 days**, and **Save and create first backup**. States are setup required, queued, running, retrying, verified, failed, expired, disabled, and destination unavailable.

Admin home exposes **Admin settings** and a **Schedules & backups** shortcut. The settings index lists every code-declared area; the schedules section separates Family and Admin/system groups, shows expiry summaries, and provides independent forms for SQLite schedule fields and private backup fields. It links back to Admin settings and admin home. Direct navigation remains supported but is never required.

### Alternatives

- **A — Context ledger, selected:** family/admin-system groups plus one row per daily job and typed settings panels. It scales to more jobs and becomes stacked cards on mobile.
- **B — Seven-day timeline, not selected:** upcoming runs are visually clear, but history and recovery compete with calendar space.
- **C — Status cards, not selected:** easiest implementation, but multiple schedules lose comparison and next-run ordering.

| Alternative        | Usability                  | Accessibility               | Cost   | Product fit                    |
| ------------------ | -------------------------- | --------------------------- | ------ | ------------------------------ |
| Schedule ledger    | Fast comparison and detail | Table-to-list reading order | Medium | Selected for future daily jobs |
| Seven-day timeline | Strong upcoming-time view  | Dense at zoom/mobile        | High   | Too calendar-centric           |
| Status cards       | Clear with one job         | Repeated headings           | Low    | Weak when the registry grows   |

#### Lo-fi A — schedule ledger (selected)

![Schedule-ledger lo-fi desktop](assets/ui-ledger-lofi-desktop.svg)
![Schedule-ledger lo-fi tablet](assets/ui-ledger-lofi-tablet.svg)
![Schedule-ledger lo-fi mobile](assets/ui-ledger-lofi-mobile.svg)

#### Lo-fi B — seven-day timeline (not selected)

![Timeline lo-fi desktop](assets/ui-timeline-lofi-desktop.svg)
![Timeline lo-fi tablet](assets/ui-timeline-lofi-tablet.svg)
![Timeline lo-fi mobile](assets/ui-timeline-lofi-mobile.svg)

#### Lo-fi C — status cards (not selected)

![Status-cards lo-fi desktop](assets/ui-cards-lofi-desktop.svg)
![Status-cards lo-fi tablet](assets/ui-cards-lofi-tablet.svg)
![Status-cards lo-fi mobile](assets/ui-cards-lofi-mobile.svg)

#### Selected hi-fi — schedule ledger

![Schedule-ledger hi-fi desktop](assets/ui-ledger-hifi-desktop.svg)
![Schedule-ledger hi-fi tablet](assets/ui-ledger-hifi-tablet.svg)
![Schedule-ledger hi-fi mobile](assets/ui-ledger-hifi-mobile.svg)

The selected design reuses Bnest's Nest workshop tokens: ink `#153f42`, canvas `#d8f1ec`, paper `#fff9ed`, sunflower `#f7b84b`, coral `#e5633d`, and lagoon `#80c5b8`. Desktop uses contextual groups with a settings rail; tablet uses one column; mobile converts each row to a labeled card. No new font, color system, chart library, or animation is added.

Keyboard order is page heading, schedule detail control, folder field, then save. The selected row uses `aria-current`, status changes use `aria-live="polite"`, failures use `role="alert"`, and folder errors focus the summary. Status always pairs text and icon with color. Loading preserves navigation; focus survives LiveView patches; 200% zoom reflows without horizontal scrolling; reduced motion removes decorative transitions.

## Authorization and Privacy

`/storage`, `/admin/settings`, and `/admin/settings/schedules` share one admin LiveView session inside `[:browser, :authenticated_browser, :admin_only]`. The HTTP plug rejects non-admin and unauthenticated requests before LiveView mount and before registry, schedule, run-ledger, or config reads; an admin-specific `on_mount` rechecks the current server-side role for LiveView connect/reconnect. Revoked sessions and users without a current `admin` role receive the existing not-found response. Tests cover children, parents, mixed non-admin roles, revoked sessions, direct navigation, context grouping, and exclusion of `admin_system` rows from family-scoped readers.

Home renders both entry points only after resolving the current server-side admin role. This presentation rule is defense in depth; each destination route authorizes independently. The registry is code-owned and every submitted panel key and field is allowlisted before owner reads or writes.

Logs, telemetry, errors, and committed fixtures use schedule keys and safe categories only. The full configured path is rendered only to the authorized admin. No endpoint returns backup files for download.

## Testing Strategy

- **Unit — `bnest-app:test:unit`:** prove daily-time arithmetic, context/handler allowlists, expiry boundaries, occurrence counting, retry classification, receipt parsing, and retention selection with an injected clock and synthetic names.
- **Integration — `bnest-app:test:integration`:** use an isolated migrated SQLite database and marked temporary backup root to prove immediate claims, restart/catch-up, two-coordinator overlap, leases, `VACUUM INTO`, independent verification, atomic artifacts, and safe cleanup.
- **Behavior — `bnest-app:test:coverage:behaviour`:** bind every selected canonical scenario through both app adapters and the E2E compliance adapter; no step may be undefined or exempted.
- **E2E — `bnest-app-e2e:test:e2e`:** run only the affected exact-origin admin journey with unique `test-user-<run-id>` identities, connected LiveView/WebSocket, desktop/tablet/mobile viewports, reconnect, and non-admin direct-route denial.

Tests never read production records or expose configured paths or payloads. Each run records only value-free pass/fail, schedule keys, synthetic artifact basenames, and revision evidence. Its finalizer stops browsers and test servers, then removes only the exact validated marked SQLite and backup roots; cleanup failure fails the gate.

## Active-Service Rollout

Follow [live-service continuity](../../../repo-governance/development/live-service-continuity.md). Baseline the active Caddy route and SQLite readiness. The managed `release:run` transaction builds the immutable artifact, applies and verifies `bnest-persistent-schedules-v1` through its approved release adapter under the storage lock, then starts an independent candidate whose readiness proves schedule schema, coordinator liveness, and allowlist reconciliation. Each slot receives `BNEST_REPOSITORY_ROOT` for the permanent checkout, so runtime-relative backup defaults never inherit the detached build worktree that is removed before candidate startup. Promote through Caddy, prove intended revision plus connected LiveView/WebSocket recovery without refresh, drain five minutes, and retain the previous artifact until the first isolated scheduled-backup smoke succeeds. A scheduler, backup, or dashboard failure rolls the route back without changing Tailscale; backup files and expanded tables remain safe.

## Specification Changes

AC-01 through AC-11 become durable contracts because they change storage ownership, reusable scheduling, context/expiry policy, authorization, failure behavior, admin configuration, and UI. Rollout mechanics remain plan-level operational criteria proved in `delivery.md`.

### [E] `specs/apps/bnest/app/architecture.md`

```diff
+ System Context: add Administrator and Dropbox desktop sync nodes plus admin-settings and ignored-folder sync relationships.
+ Container View: add the backup folder data store and Dropbox sync boundary; extend Local SQLite database ownership to schedule/run rows.
+ Component View: add Admin settings, Schedule coordinator, Task supervisor, Handler registry, and Backup proof components and their Authorization/Data repository relationships.
+ Architectural Constraints: add exact-source, current-admin, additive-overlap, marker ownership, and no-download rules.
+ SQLite remains the sole production backup source.
```

- = Preserve Caddy, authentication, user ownership, and SQLite authority.
- ✓ Proof: architecture map gate, candidate readiness, and routed admin journey.

### [N] `specs/apps/bnest/app/behaviours/scheduled_backups.feature`

```diff
+ Admin discovers typed settings and configures allowed backup parameters.
+ Non-admin cannot view settings, schedules, or backup details.
+ Persistent daily schedule produces one verified SQLite backup.
+ Restart catches up once and overlapping releases cannot duplicate a slot.
+ Date/time and occurrence policies expire without duplicate counts.
+ Failure preserves the last verified backup and reports safe recovery.
+ Dashboard separates family and admin/system schedules.
+ A second allowlisted handler reuses the same scheduler core.
```

No existing scenario changes because this is a new feature file.

<details>
<summary>New scenario inventory</summary>

- **Use the Dropbox-synced default:** an admin with no override resolves a backup and receives the verified `@data/backup/` result.
- **Save a safe override:** an admin submits a valid private folder and gets one atomic save plus one idempotent setup run.
- **Persist a daily schedule across restart:** a saved schedule restarts before due time and retains one future UTC slot.
- **Catch up only the latest missed slot:** startup after multiple missed days claims only the newest eligible occurrence.
- **Back up authoritative SQLite:** a claimed production run snapshots only the configured SQLite primary and verifies the candidate independently.
- **Claim a slot once and recover:** overlapping releases or an expired lease produce one slot identity, no overlap, and at most three attempts.
- **Show contextual daily schedules:** an admin enters from home and sees family and admin/system rows, safe state, and typed settings.
- **Deny schedule and configuration access:** an unauthenticated, revoked, or non-admin visitor receives not-found before any protected read.
- **Retain only owned verified artifacts:** a verified run keeps the current seven-WIB-day window and preserves every unowned or previous-folder file.
- **Reuse one scheduler across contexts:** a second allowlisted handler uses the shared claim, runner, ledger, and contextual inventory.
- **Discover typed admin configuration:** an admin sees every declared panel while each domain validates and commits independently.
- **Expire schedules deterministically:** date/time and occurrence policies block future claims without counting retries or suppressing the final occurrence.

</details>

- → Bindings: `apps/bnest-app/test/behaviour/steps/scheduled_backup_steps.exs`, `apps/bnest-app/test/integration/support/home_page_driver.ex`, `apps/bnest-app/test/unit/support/home_page_driver.ex`, `apps/bnest-app-e2e/tests/steps/scheduled-backups.steps.ts`, and `apps/bnest-app-e2e/tests/support/scheduled-backups.ts`.
- ✓ Proof: `bnest-app:test:coverage:behaviour`, isolated `bnest-app:test:integration`, `bnest-app-e2e:test:coverage:behaviour:e2e`, and focused exact-origin `bnest-app-e2e:test:e2e`.

## File Impact

```text
apps/bnest-app/assets/css/app.css                                          [E]
apps/bnest-app/lib/bnest_app/application.ex                               [E]
apps/bnest-app/lib/bnest_app/admin_config/registry.ex                     [N]
apps/bnest-app/lib/bnest_app/data_repository/storage_coordinator.ex      [E]
apps/bnest-app/lib/bnest_app/release/migrations/persistent_schedules.ex   [N]
apps/bnest-app/lib/bnest_app/scheduler.ex                                 [N]
apps/bnest-app/lib/bnest_app/scheduler/registry.ex                        [N]
apps/bnest-app/lib/bnest_app/scheduler/policy.ex                          [N]
apps/bnest-app/lib/bnest_app/scheduler/store.ex                           [N]
apps/bnest-app/lib/bnest_app/scheduler/run.ex                             [N]
apps/bnest-app/lib/bnest_app/backup/config.ex                             [N]
apps/bnest-app/lib/bnest_app/backup/location.ex                           [N]
apps/bnest-app/lib/bnest_app/backup/receipt.ex                            [N]
apps/bnest-app/lib/bnest_app/backup/run.ex                                [N]
apps/bnest-app/lib/bnest_app_web/controllers/health_controller.ex        [E]
apps/bnest-app/lib/bnest_app_web/user_auth.ex                             [E]
apps/bnest-app/lib/bnest_app_web/live/admin_settings_live.ex              [N]
apps/bnest-app/lib/bnest_app_web/live/admin_schedule_settings_live.ex     [N]
apps/bnest-app/lib/bnest_app_web/router.ex                                [E]
apps/bnest-app/lib/bnest_app_web/controllers/page_html/home.html.heex     [E]
apps/bnest-app/mix.exs                                                     [E]
apps/bnest-app/priv/sqlite_repo/migrations/20260830000000_add_persistent_schedules.exs [N]
apps/bnest-app/tools/deployment.mjs                                       [E]
apps/bnest-app/tools/release.mjs                                          [E]
apps/bnest-app/tools/release.test.mjs                                     [E]
apps/bnest-app/README.md                                                   [E]
README.md                                                                  [E]
repo-governance/conventions/runtime-flat-file-data.md                     [E]
```

```text
apps/bnest-app/test/behaviour/steps/scheduled_backup_steps.exs            [N]
apps/bnest-app/test/integration/support/home_page_driver.ex               [E]
apps/bnest-app/test/unit/support/home_page_driver.ex                      [E]
apps/bnest-app/test/unit/bnest_app/scheduler/policy_test.exs             [N]
apps/bnest-app/test/integration/bnest_app/scheduler_test.exs              [N]
apps/bnest-app/test/integration/bnest_app/scheduled_backup_test.exs       [N]
apps/bnest-app/test/integration/bnest_app/persistent_schedules_migration_test.exs [N]
apps/bnest-app/test/integration/bnest_app/sqlite_storage_test.exs        [E]
apps/bnest-app/test/integration/bnest_app_web/admin_settings_live_test.exs [N]
apps/bnest-app/test/integration/bnest_app_web/health_controller_test.exs  [E]
apps/bnest-app-e2e/README.md                                               [E]
apps/bnest-app-e2e/tests/steps/scheduled-backups.steps.ts                 [N]
apps/bnest-app-e2e/tests/support/scheduled-backups.ts                     [N]
specs/apps/bnest/app/architecture.md                                      [E]
specs/apps/bnest/app/behaviours/README.md                                 [E]
specs/apps/bnest/app/behaviours/scheduled_backups.feature                 [N]
```

```text
~/.config/bnest/backup.json                                               [N private]
<backup-folder>/.bnest-backup-root.json                                  [N private]
<backup-folder>/bnest-prod-<utc-timestamp>-<run-id>.sqlite3               [N private]
<backup-folder>/bnest-prod-<utc-timestamp>-<run-id>.receipt.json          [N private]
```

No dependency manifest or lockfile changes are planned.

## Primary References

- [Erlang process timers](https://www.erlang.org/doc/apps/erts/erlang.html#send_after/3) document process message timers and their process-local lifecycle.
- [Elixir `Task.Supervisor`](https://hexdocs.pm/elixir/Task.Supervisor.html) documents supervised task execution and non-linking task APIs.
- [Ecto SQLite transactions](https://hexdocs.pm/ecto_sqlite3/Ecto.Adapters.SQLite3.html#module-transaction-locking) document immediate transactions for serialized write claims.
- [SQLite `VACUUM INTO`](https://sqlite.org/lang_vacuum.html#vacuum_with_an_into_clause) documents consistent live snapshots and incomplete-output risk on interrupted execution.
