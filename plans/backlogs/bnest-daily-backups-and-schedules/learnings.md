# Learnings

## Decisions

- 2026-08-30: Production flat-file data no longer exists and is explicitly excluded; only the authoritative SQLite database is backed up.
- 2026-08-30: The default destination is ignored repository `data/backup/`; its data is never committed, and an admin may configure a safe override.
- 2026-08-30: The schedules dashboard is visible only to a current server-authorized admin.
- 2026-08-30: Built-in Elixir/OTP owns wake-up, supervision, and task execution. Persistent definitions, claims, leases, retries, and results live in SQLite.
- 2026-08-30: No Oban, Quantum, cron parser, or timezone dependency is justified for one fixed daily WIB schedule.
- 2026-08-30: Host cron is also rejected because it would split operational ownership while Bnest would still need the same durable claims, context, history, configuration, and blue/green overlap protection.
- 2026-08-30: The scheduler core is shared. Persisted `family` and `admin_system` contexts separate product-purpose jobs from operational jobs; production backup is `admin_system`.
- 2026-08-30: Admin home routes to one typed Admin settings registry; each domain keeps its own validation and persistence rather than a generic key/value store.
- 2026-08-30: Expiration supports `never`, absolute UTC time, and a unique-occurrence limit. Retries do not consume extra occurrences; production backup is fixed `never`.
- 2026-08-30: Backup defaults to Git-ignored repository `data/backup/` so immutable completed snapshots sync through Dropbox while live SQLite remains outside it; admins may choose a safe override.
- 2026-08-30: Retention is fixed to the newest verified owned pair on each of the latest seven WIB dates, preventing repeated same-day setup runs from growing the folder.

## Technical Findings

- Process timers are ephemeral; persistence must come from SQLite reconciliation, not from a timer surviving restart.
- A unique `(schedule_key, scheduled_for)` claim plus a short immediate SQLite transaction is the duplicate barrier during Caddy blue/green overlap.
- A code allowlist must resolve stored handler keys so database content can never select arbitrary modules or functions.
- Context is persisted classification and an enforced presentation boundary, not a replacement for server-side role authorization.
- Expiry and occurrence increments belong in the same immediate claim transaction as the unique slot barrier.
- WIB is fixed at UTC+07:00 and has no daylight-saving transition, allowing deterministic daily arithmetic without an IANA timezone package.
- SQLite `VACUUM INTO` creates a consistent snapshot, but interrupted output may be incomplete and therefore requires partial naming plus independent verification.

## Delivery Questions

- Record the chosen destination's storage medium, free-space baseline, and recovery ownership without committing its absolute path.
- Confirm Dropbox has completed syncing the first final artifact using value-free filename/size evidence; never inspect or commit its payload.
- Measure production database size and backup duration before deciding whether same-host storage remains adequate.
- Record the first verified artifact receipt and isolated restore proof using value-free evidence only.

## Capture Practice

Update this file at every phase checkpoint, after any failed promotion or recovery, and when a revisit trigger changes. Keep only value-free decisions, measurements, safe artifact basenames, revision/status evidence, and unresolved questions here; never record absolute private paths, payloads, users, credentials, or production counts. Detailed command output remains ephemeral unless an existing repository-owned evidence location is required by the executing workflow.

## Revisit Triggers

- Multiple cadence kinds, user-authored schedules, distributed hosts, or materially higher throughput may justify evolving the shared scheduler or evaluating a maintained framework; merely adding allowlisted daily schedules does not.
- A timezone with offset transitions requires explicit IANA timezone handling.
- Total-disk-loss protection requires separately designed remote replication and encryption/key ownership.
