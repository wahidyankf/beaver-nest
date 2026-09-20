# Backup, Capacity, Restore, and Release

## Operational Objective

Family Chat changes the size and write pattern of authoritative SQLite but does not create a separate backup product.
The existing `prod-sqlite-backup-daily` schedule continues to create a whole-database snapshot. This plan changes its
default to 01:00 WIB, makes the live-backup path lower impact, proves the added data on restore, and releases the feature
without stopping the routed service.

## Service Boundaries

```text
Scheduler
  → Registry entry prod_sqlite_backup
    → Backup.Run registered handler
      → BnestApp.Backup public service
        → dedicated Exqlite connection
          → authoritative SQLite file

Scheduler
  → Registry entry family_chat_push_retention
    → PushNotifications.RetentionJob
      → BnestApp.PushNotifications public service
        → BnestApp.FamilyChat.Store
          → authoritative SQLite file
```

Scheduler owns definitions, due claims, leases, attempts, completion/failure, and run receipts. Registered handlers adapt
a scheduler claim to a service call. Services own domain policy. Scheduler, registry, handlers, and release tooling never
query family-chat/backup tables or construct raw retention SQL.

## Backup Schedule Migration

- Key remains `prod-sqlite-backup-daily`; no chat-specific schedule is added.
- Desired migration time is `daily_at_utc = 18:00`, displayed as 01:00 WIB.
- The additive database migration does not update the live schedule row directly.
- After the compatibility revision is routed and every runnable slot supports the new Backup service, managed release
  calls a public Scheduler operation that force-converges this key once, even if an existing installation used another
  time. The response includes old/new revisions but evidence records no private destination.
- Fresh installations traverse the same service reconciliation after their compatible revision starts.
- The one-time release reconciliation is recorded and not repeated on startup or later releases. Afterward the existing
  admin settings path may change the time normally; later operator choice wins.
- Scheduler recomputes the next future slot from the new time. It does not fabricate a missed 18:00 UTC run unless the
  supported schedule policy says the latest slot is due. The release test locks the chosen transition.

Push retention remains a separate fixed disabled seed at 00:15 WIB and becomes enabled only after old-slot drain.

## Capacity Model and Preflight

Planning estimates are in technical doc 002. Runtime preflight uses measurement, never the estimates alone:

1. Resolve and validate authoritative database and owned backup destination through existing configuration services.
2. Read database file bytes, `PRAGMA page_count`, `PRAGMA page_size`, and WAL file bytes without printing paths.
3. Read destination available bytes using the existing platform-safe capacity adapter.
4. Compute `sourceLogicalBytes = page_count × page_size` and conservatively use
   `sourceBytes = max(databaseFileBytes, sourceLogicalBytes)`.
5. Compute `requiredFree = sourceBytes + walBytes + 256 MiB` for the new output and operational headroom. Existing seven
   retained backups are already consumed space, not added again to required free; the long-horizon `9 ×` formula is a
   provisioning model for the whole destination.
6. Require enough free bytes for `requiredFree` and a new non-existing partial filename. A failed guard returns
   `insufficient_capacity` before `VACUUM INTO` or partial output creation.

The release evidence records rounded source/WAL/free/required byte counts and pass/fail, not paths. A platform capacity
command parse failure is a backup failure, never assumed sufficient.

## Snapshot Algorithm

1. Verify claim attempt/lease remains current.
2. Run capacity preflight and emit a start telemetry event with size buckets.
3. Construct an owned `.partial` output path beside the final artifact. Remove only a stale partial whose name belongs to
   this exact run ID; refuse an unrelated existing file.
4. Open a dedicated Exqlite 0.40 connection to authoritative SQLite with explicit `busy_timeout` and
   `progress_handler_steps` so cancellation can interrupt both busy waits and VM execution. Do not use
   `BnestApp.SqliteRepo` and do not execute `PRAGMA wal_checkpoint(FULL)`.
5. Execute parameterized `VACUUM INTO` to the partial path under a supervised task with a configured maximum duration.
6. On deadline or cancellation, call `Exqlite.Sqlite3.cancel/1`, await the query task's cancelled/error result, release
   its statement, and only then close the dedicated connection. Do not immediately close an executing connection. Remove
   only the owned partial, emit categorized telemetry, and return a retryable Scheduler error. Never rename a timed-out
   file. See [Exqlite cancellation](https://exqlite.hexdocs.pm/Exqlite.Sqlite3.html#cancel/1).
7. Close the writer connection. Open the partial through a separate read-only connection and run `PRAGMA quick_check`,
   schema-migration inventory, and logical schema proof.
8. Set mode `0600`, fsync the partial, recheck the Scheduler attempt fence, and atomically rename to the final `.sqlite3`.
9. Hash the final artifact, build/write/fsync/rename its receipt atomically, complete the Scheduler claim, then retain one
   newest owned artifact/receipt pair for each of seven WIB dates.
10. Preserve unknown files and every artifact in previous destinations. Cleanup failure is surfaced and retried; it is not
    hidden by a successful snapshot.

`VACUUM INTO` creates a consistent snapshot while the source stays live. SQLite may require CPU/I/O and the operation is
not incremental; the concurrency gate below decides whether the measured household deployment can tolerate it.

## Timeout, Cancellation, and Retry

- `BNEST_BACKUP_TIMEOUT_MS` is a non-secret machine-local setting with a 1,800,000 ms (30 minute) default and accepted
  range of 60,000–7,200,000 ms. Startup rejects malformed/out-of-range values. The deadline is not dynamically extended
  by progress.
- Scheduler, not the Backup service, owns retry count/backoff and missed-slot recovery. The service returns categorized
  `insufficient_capacity`, `busy`, `timeout`, `cancelled`, `integrity_failed`, `stale_claim`, or `io_failed` without raw
  exception/path text.
- A process crash may leave an owned partial. The next attempt identifies it by run ID, never treats it as verified, and
  removes it before starting.
- No retry overlaps another active backup claim. Claim/attempt fencing prevents a late task from publishing an artifact.

## Concurrent-write Proof

Run against an isolated marked database through the exact Caddy origin, not the production database:

1. Seed the default room, paginated messages, subscriptions, deliveries, schedules, and enough synthetic padding to
   exercise measurable snapshot I/O.
2. Start continuous authenticated GraphQL read and send probes from isolated `test-user-` sessions; use unique
   idempotency keys and discard body values from evidence.
3. Start the backup through Scheduler→handler→service, never by calling private functions.
4. Sample from before `VACUUM INTO` until receipt/retention completes. Each probe has a two-second client timeout.
5. Require zero HTTP/GraphQL failures, every sample ≤2 seconds, and p95 ≤500 ms. Also require all sent IDs in the live
   database and a self-consistent point-in-time subset in the restored snapshot.
6. Cancel once in a separate case and prove routed traffic continues, no final artifact appears, owned partial disappears,
   and Scheduler state remains retryable.
7. Cleanup all sessions, rows, server, port lease, database, backup artifacts, and destination marker in `finally`.

Any responsiveness breach blocks release and triggers design review; the test does not weaken thresholds or reduce the
fixture until it passes.

## Restore Drill

1. Select an owned verified receipt/artifact pair without exposing its path.
2. Recheck receipt ownership, artifact SHA-256, mode, and size.
3. Copy to an isolated marked restore root and start a fresh application process against the copy.
4. Run quick check and migration/schema verification.
5. Through normal services, prove exact room seed, ordered user/system messages, push subscription structure, delivery
   states, `prod-sqlite-backup-daily` state, and retention schedule state.
6. Prove secrets are usable structurally only where required but never print endpoint/key/session/message body.
7. Stop the process and delete only the marked restore root. Cleanup failure fails the drill.

Production verification waits for the next ordinary backup and restores only a copy. It never injects a synthetic user,
message, subscription, delivery, or schedule into production.

## Observability and Readiness

Backup telemetry: operation phase, outcome category, duration, rounded source/output/free byte buckets, integrity result,
and Scheduler run/attempt opaque IDs. Retention telemetry: aggregate soft-deleted/purged/stale-nonfinal counts. Neither
surface records paths, SQL, messages, users, endpoints, keys, session digests, cookies, or origins.

Release telemetry records prior-socket close observed, replacement handshake revision match, subscription-ack latency,
catch-up count bucket, exact-once result, and new-handshake count by active/prior slot. It records no socket token,
subscription document variables, room content, origin, cookie, or user identity.

Compatibility readiness requires expected schema/seed, registered handlers, Backup service callable, Absinthe supervisor
with manifest pool size, dispatcher/task supervisors, and valid production VAPID shape. It does not contact a push
provider or execute a backup. Experience readiness additionally reports the expected feature-flag state and asset
manifest revision.

## Single-host Slot and Socket Topology

Blue and green slots are separate OS/BEAM processes launched with `RELEASE_DISTRIBUTION=none`. Their Phoenix PubSub and
Absinthe subscription registries are local; the plan does not introduce Distributed Erlang, Redis, or another broker.
Candidate GraphQL HTTP/socket proof therefore keeps both sides on the candidate origin, and ordinary routed traffic keeps
both sides on the active origin.

Caddy config reload is the cutover boundary. The generated `reverse_proxy` block must omit `stream_close_delay` (or any
other nonzero stream-close delay). Caddy then closes WebSocket streams held by the unloaded prior proxy config, and every
replacement handshake uses the newly routed slot. The existing global `grace_period 5m` remains: it governs HTTP-server
shutdown during Caddy config changes or process stop, not the reverse-proxy module's explicit stream-survival policy. The
five-minute release observation also remains, but it keeps the prior Phoenix process warm for rollback; it must not keep
its browser sockets alive.

This relies on Caddy's documented default: WebSockets are closed when reverse-proxy configuration unloads, while
`stream_close_delay` explicitly postpones that close; the global grace period separately governs HTTP-server shutdown.
Sources: [Caddy reverse proxy streaming](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#streaming) and
[Caddy global `grace_period`](https://caddyserver.com/docs/caddyfile/options#grace-period).

The observable promotion sequence is fixed:

1. Hold two authenticated GraphQL sockets and the existing LiveView continuity probe on the currently routed revision;
   record only safe revision/context labels.
2. Prove the candidate directly, including one candidate-local mutation/subscription pair.
3. Reload Caddy to route the candidate and observe both prior connections close.
4. Require new HTTP and socket handshakes to report the promoted revision; no handshake may reach the warm prior slot.
5. Within ten seconds, each browser acknowledges `familyChatMessageCommitted`, runs `afterId` catch-up, deduplicates, and
   only then resumes FIFO sending. The LiveView probe also reconnects without path/draft loss. A synthetic isolated
   commit in the close/reconnect gap must render once.
6. Keep the prior slot process-warm for the remainder of the five-minute routed observation. Roll back by reloading Caddy
   to it if a budget fails; that reload closes candidate sockets and exercises the same reconnect/catch-up path.
7. Retire the prior slot only after routed, revision, reconnect, catch-up, and latency evidence passes.

This design intentionally accepts lossy realtime transport during the bounded cutover because SQLite remains durable
authority. Configuring a nonzero `stream_close_delay` while slots are independent is a release defect: it can leave a
healthy browser subscribed to the wrong local PubSub for the whole delay.

## Release Invariants

| Invariant           | Compatibility stage                                          | Experience stage                        |
| ------------------- | ------------------------------------------------------------ | --------------------------------------- |
| Database            | Additive schema; old code ignores it                         | No breaking schema change               |
| GraphQL             | Full stable schema/socket active                             | Same schema; UI begins consuming it     |
| UI                  | Room assets/shell dormant, nav hidden                        | Nav/route experience enabled            |
| IndexedDB           | Code present but no ordinary entry path                      | Active for authenticated room           |
| Retention handler   | Registered; seed disabled through overlap                    | Already safe/enabled after drain        |
| Backup              | New service live; time converged after drain                 | Unchanged/configurable                  |
| Rollback            | Prior revision until drain; then flag-off compatibility slot | Same revision with flag off             |
| PubSub topology     | Independent slot-local registries                            | Same; no cross-slot delivery assumption |
| Caddy stream policy | No nonzero `stream_close_delay`                              | Same                                    |
| Client behavior     | Old socket closes; reconnect ≤10 s; catch up; no refresh     | Same, then drain queued intent          |

## Compatibility Release Procedure

1. Confirm clean landed SHA, healthy active route, measured capacity, one inactive slot, and valid secrets without values.
2. Build the exact SHA and migration manifest through the managed transactional release target.
3. Apply/verify additive migration while old slot remains routed; keep retention disabled and UI flag off.
4. Start inactive candidate; prove direct liveness/readiness/revision, GraphQL HTTP, authenticated socket, fixed pool,
   registered handlers, and existing non-chat journeys.
5. Start continuous local-Caddy and routed-origin probes, attach authenticated sockets to the active route, and assert the
   generated candidate Caddy config contains no nonzero `stream_close_delay`. Promote only while all evidence is green.
6. Observe prior-socket close, promoted revision on every replacement handshake, subscription acknowledgement within ten
   seconds, subscribe-first catch-up, exact-once rendering of a gap commit, and no forced refresh.
7. Keep the prior slot warm and unrouted for at least five minutes while enforcing zero failures, p95 ≤500 ms, every
   routed sample ≤2 seconds, and zero new handshakes to that prior slot.
8. Retire old slot. This compatibility SHA becomes the rollback floor.
9. Enable push retention and force backup time to 18:00 UTC through public Scheduler calls. Verify safe schedule state and
   registered handler; do not run direct SQL.
10. Stop candidates/watchers/stubs/proxies not serving the active route; retain valid rollback artifact only.

## Experience Release Procedure

1. Reuse the exact reviewed compatibility SHA and prepare the inactive slot with `BNEST_FAMILY_CHAT_ENABLED=true`; the
   active compatibility slot remains the same SHA with the flag off.
2. Repeat baseline/candidate/revision/readiness/continuous-probe sequence. No repository edit, migration, or schema
   contraction is allowed. Readiness must prove both identical revision and different intended flag state.
3. Against an isolated candidate/runtime root, use two `test-user-` contexts to prove draft, offline queue, reconnect,
   catch-up, FIFO drain, and exact-once rendering.
4. Promote through Caddy with no nonzero stream-close delay. Existing clients close, reconnect to the flag-on slot within
   ten seconds, subscribe, catch up, and continue without reload. Production verification observes only
   health/readiness/schema/revision/operational evidence and does not create synthetic production records.
5. Keep the same-SHA flag-off slot warm and unrouted through bounded observation, then retire it and clean temporary
   resources.

## Rollback Matrix

| Trigger                                                       | Action                                                                       | Data treatment                                 |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------- |
| Preflight health/capacity fails                               | Do not build/migrate/promote                                                 | No change                                      |
| Migration or compatibility candidate fails                    | Keep old route; retire candidate                                             | Preserve additive objects/evidence             |
| Compatibility routed budget fails before handler activation   | Managed rollback to prior revision                                           | Preserve additive tables                       |
| Old socket stays open or replacement misses ten-second budget | Reload Caddy to the warm prior slot; reject candidate                        | Catch up from SQLite; preserve queue and draft |
| Failure after new handler activation                          | Disable unsupported handler through Scheduler before old code is claimable   | Preserve messages/schedules                    |
| Experience candidate/routed/UI fails                          | Roll back to same-SHA flag-off compatibility slot                            | Keep schema, queue retries idempotently        |
| External push provider unavailable                            | Keep healthy chat active                                                     | Server push retry reaches bounded ceiling      |
| Backup capacity/timeout/integrity fails                       | Keep application active; Scheduler retries                                   | Publish no unverified artifact                 |
| Secret exposure                                               | Stop release, sanitize evidence, rotate through separate authorized response | Preserve data; no casual retry                 |

Every conditional recovery receives execution evidence or a dated `Not triggered` disposition. A commit/push is never
reported as a release; completion requires the routed intended revision and cleanup.
