# Learnings — Family Chat Room

## Capture Contract

Record a dated entry before editing when repository reality differs from schema, reader/writer inventory, browser
capability, release path, or File Impact. Record after every phase checkpoint, RED/GREEN/REFACTOR cycle, fault injection,
backup/load/restore drill, API/UI proof, release/rollback, and final reconciliation.

Allowed evidence: revision IDs, migration versions/checksums, synthetic IDs, browser family, attempt numbers, durations,
rounded sizes, counts from isolated fixtures, outcome categories, and pass/fail. Prohibited: production usernames/IDs,
message bodies/previews, endpoints, browser/VAPID keys, cookies, session values, private origins, absolute runtime paths,
account counts, or database contents.

## Planning Decisions — 2026-09-18

- The domain hierarchy is **Family Chat → Room**. V1 seeds ID 1, slug `ruang-keluarga`, name `Ruang Keluarga`, room kind
  `conversation`, and member posting enabled. Room creation/switching and calendar behavior remain out of scope.
- The canonical URL is `/family-chat/ruang-keluarga`; `/family-chat` redirects to it.
- All UI-facing backend work uses GraphQL at `/api/graphql` and authenticated `/api/graphql/socket`. Scheduler, Backup,
  push retention, dispatcher, and future system producers remain internal service boundaries.
- Absinthe HTTP/Phoenix subscriptions are selected. Its reliability guidance requires an explicit fixed subscription pool
  size when instances can report different CPU counts; every Bnest slot therefore uses code-owned `pool_size: 8`.
  Source: [Absinthe subscriptions](https://hexdocs.pm/absinthe/subscriptions.html).
- SQLite and catch-up queries remain authority. Reconnect order is subscribe, query after the highest committed server ID,
  deduplicate by server ID, then drain the client outbox FIFO.
- Offline sends persist in IndexedDB, capped at 100 records per user/room. Queue retry runs only while the app is active,
  resumes on reopen, and does not use Background Sync. Committed history is never stored in IndexedDB or Cache Storage.
- Browser retry uses 1, 2, 4, 8, 16, and 32 seconds, then a jittered delay capped at 60 seconds. Network/5xx retries;
  validation/forbidden/room-not-found stops; authentication expiry pauses without cross-user replay; seven-day-old work
  requires manual retry.
- Messages store room, sender kind `user|system`, stable sender ID, display snapshot, idempotency key, body, and commit
  time. Uniqueness is `(room_id, sender_kind, sender_id, idempotency_key)`. Public GraphQL exposes no system mutation;
  future producers call an internal idempotent service.
- Specifications split into `specs/apps/bnest/app-be/` and `specs/apps/bnest/app-fe/`, aggregated by
  `specs/apps/bnest/README.md`. Each scenario has one canonical owner. `bnest-app` remains the production owner.
- `bnest-app-e2e` is replaced by `bnest-app-be-e2e` for routed GraphQL HTTP/WebSocket and `bnest-app-fe-e2e` for
  Playwright/PWA. Frontend queue/backoff/reconcile receives a Vitest Gherkin unit adapter.
- The split adapts the boundary-specific corpus principle in the
  [OSE behavior map](https://raw.githubusercontent.com/wahidyankf/ose-public/main/specs/apps/ose/www/behaviours/README.md)
  and its explicit
  [backend coverage config](https://raw.githubusercontent.com/wahidyankf/ose-public/main/apps/ose-www-be-e2e/behaviour-coverage.json),
  while keeping Bnest ownership and naming.
- Prior generator discovery found no installed/local Nx generator appropriate for the repository-specific ExBDD,
  Vitest, GraphQL, and Playwright split. Delivery records the assessment and performs a manual split after rules
  propagation; it does not force an unrelated generator.
- Push delivery records retain seven active days plus seven soft-deleted days. Permanent messages have no retention.
- Backup remains the complete SQLite database under `prod-sqlite-backup-daily`. Fresh and existing installations are
  forced once to 01:00 WIB (`18:00 UTC`) through Scheduler after compatible code is active; operators may change it later.
- The forced `PRAGMA wal_checkpoint(FULL)` is removed from the backup hot path. `VACUUM INTO` uses a dedicated connection,
  preflight, cancellation/timeout, independent proof, atomic rename, receipt, and existing seven-date retention. SQLite
  documents it as a consistent live-backup alternative; the incremental Backup API is not exposed by current Exqlite.
  Sources: [SQLite VACUUM INTO](https://www.sqlite.org/lang_vacuum.html) and
  [Exqlite issue 144](https://github.com/elixir-sqlite/exqlite/issues/144).
- The locked Exqlite 0.40 API exposes `cancel/1`, which interrupts VM execution and wakes its busy handler. Backup timeout
  therefore cancels, awaits the query result, releases the statement, and only then closes the connection; immediate close
  during execution is explicitly avoided. Source: [Exqlite.Sqlite3](https://exqlite.hexdocs.pm/Exqlite.Sqlite3.html#cancel/1).
- Disk planning uses 200 messages/day baseline, 2 KiB effective message/index, seven 1 KiB recipient delivery rows per
  message, and a 14-day delivery footprint. Provisioning uses
  `9 × (B0 + chat_live) + WAL + 256 MiB`; runtime preflight uses measured file/page/WAL/free bytes.
- Production delivery uses one reviewed revision in two staged slot configurations: compatibility first with dormant UI,
  then the same SHA with the experience flag enabled. The drained flag-off configuration is the rollback floor. Neither
  release requires browser refresh.
- Blue/green slots remain independent with `RELEASE_DISTRIBUTION=none`; no cross-slot PubSub is assumed. The current Caddy
  generator's `stream_close_delay 5m` is removed for this feature because Caddy otherwise preserves a prior-slot socket
  whose local subscription registry cannot receive promoted-slot publishes. Config reload closes old streams, the client
  reconnects and subscribes on the promoted slot within ten seconds, and SQLite catch-up repairs the bounded gap. The
  prior process—not its sockets—stays warm for the five-minute rollback observation. Source:
  [Caddy reverse proxy streaming](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#streaming).
- OS-owned installed-PWA notification display is outside plan completion and has no delivery checkbox. Automated scope
  still proves GraphQL lifecycle, provider policy, service-worker handlers, permission UX, payload shape, and
  cache/outbox isolation.

## Rejected Alternatives

- **Keep `main` channel terminology:** rejected because the requested domain and canonical localized room identity are
  explicit and future room creation should not inherit a misleading v1 channel abstraction.
- **Continue LiveView command events:** rejected because every UI-facing backend operation is required to use GraphQL.
- **Treat subscription/PubSub as durable:** rejected because disconnect/release gaps require an authoritative catch-up.
- **Memory-only queue:** rejected because app closure/reload would lose unacknowledged intent.
- **Background Sync:** rejected because the requirement scopes retry to active/reopened app and platform support is uneven.
- **Store committed transcript offline:** rejected for privacy and dual-authority risk.
- **One mixed Gherkin corpus and E2E project:** rejected because backend protocol and frontend browser boundaries need
  independent complete adapters without duplicated scenarios.
- **Chat-only backup:** rejected because existing whole-database backup must restore relational and scheduler consistency.
- **Forced WAL checkpoint before backup:** rejected because it adds hot-path contention and `VACUUM INTO` already creates
  a consistent snapshot.
- **Incremental SQLite Backup API:** preferred in CPU behavior but unavailable through the selected Exqlite boundary.
- **One production cutover with UI immediately active:** rejected because the compatible backend/schema must become a
  proven rollback floor before clients depend on it.
- **Keep `stream_close_delay 5m` during promotion:** rejected because independent slots do not share PubSub; a surviving
  prior-slot socket could miss realtime events until the delay expires.
- **Add Distributed Erlang or Redis only for blue/green overlap:** rejected because Caddy-enforced reconnect plus durable
  catch-up satisfies continuity at single-host household scale with fewer operational and security boundaries.

## Open Execution Questions

- Exact compatible package versions after dependency/runtime inspection.
- Whether measured `VACUUM INTO` duration on current hardware justifies changing the locked 30-minute default within the
  documented 1-minute-to-2-hour configuration range; changing it requires recorded load/restore evidence.
- Whether `BroadcastChannel` is needed as a duplicate-attempt optimization after two-tab tests; server idempotency remains
  correctness regardless.
- Whether current release tooling already has a durable one-time reconciliation receipt suitable for backup-time
  convergence or needs the narrow path listed in File Impact.

## Historical Quality Gate

The earlier authoring snapshot based on `ae30736c860eb1d0c5a2f4d3258551692b47d40b` received `PASS`, but it specified a
`main` channel, LiveView commands, memory-only reconnect assumptions, one corpus/E2E project, and the older backup design.
It is historical evidence only and does not authorize this materially revised plan. Delivery Phase 0 requires a fresh,
explicitly directed quality gate.

## Authoring Quality Gate — 2026-09-18

Snapshot: in-progress `family-chat-room` plan at Git base `822da522e750f30d6089c5a566f187d934373fdb` with dirty
paths limited to this plan, its plan-owned assets, and `plans/in-progress/README.md`. Scope was the requested multi-room
foundation, GraphQL/offline contract, split specifications/E2E topology, whole-SQLite backup, and no-downtime release.
Cycle 1 findings were frozen before repair:

| ID      | Location                                    | Material gap                                                                | Repair and proof                                                                                            | Status  |
| ------- | ------------------------------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------- |
| `QG-01` | `delivery.md`, tech doc 009, `learnings.md` | Release wording could be read as two application revisions and branches     | One reviewed SHA now has flag-off compatibility and flag-on experience slots; branch/rollback text agrees   | `FIXED` |
| `QG-02` | tech docs 001 and 008                       | HTTP/CSRF/room authorization classifications left choices to implementation | Exact 400/403/405/413/415/200 mapping, 64 KiB JSON-only boundary, and non-enumerating error order are fixed | `FIXED` |
| `QG-03` | tech doc 003                                | Pagination allowed an executor to clamp or reject an oversized limit        | Values outside 1–50 now deterministically return `VALIDATION_FAILED`                                        | `FIXED` |
| `QG-04` | `learnings.md`                              | Locked GraphQL status and backup-timeout decisions still appeared as open   | Removed the HTTP question and narrowed timeout work to evidence-based tuning inside the fixed range         | `FIXED` |

Semantic re-read found no open or blocked row and no new material gap. HIPPO run
`73573b695175fcb1ec06bb5a931d52ca` passed `rhino-consumer:test:repo`, including public safety, repository config, word
budget, directory maps, harness parity, internal links, Mermaid, and plan checks. Terminal authoring verdict: **PASS**.
This verdict validates the revised documents only; it does not authorize product implementation, delivery commits,
deployment, or production mutation. Plan-document integration still requires its own explicit authority. Delivery Phase
0 deliberately requires a fresh execution-time gate because repository state may drift.

## Execution Log

No implementation phase has started. This 2026-09-18 activity revises plan documents and plan-owned visual assets only.

## Final Readiness Audit — 2026-09-18

Snapshot: the same in-progress plan at Git base `822da522e750f30d6089c5a566f187d934373fdb`, after the Caddy
promotion correction and before integration. The semantic-audit ledger was frozen before repair:

| ID       | Location                                    | Material gap                                                                                                     | Required repair                                                                                                 | Status  |
| -------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------- |
| `QG2-01` | `prd.md` AC-FC-06                           | The scenario named an enabled phone even though OS-owned physical-device display is outside plan completion      | End the acceptance boundary at one observable service-worker notification call with bounded sender/preview data | `FIXED` |
| `QG2-02` | tech docs 002 and 007                       | The migration contract deferred timestamp selection while File Impact preselected one                            | Lock the currently unused inspected path and require collision revalidation before creation                     | `FIXED` |
| `QG2-03` | `README.md`, `delivery.md`, prior gate note | Authoring status said commit/push would not occur although this plan-integration task now has explicit authority | Distinguish plan integration from still-pending product delivery and production mutation                        | `FIXED` |

No repair broadened product scope or marked a delivery checkbox complete. Semantic re-read covered all six plan
documents, all nine technical companions, the plan/asset maps, acceptance-to-delivery traceability, the current migration
inventory, and the current Caddy generator/release topology. No open or blocked ledger row and no new material gap
remains. HIPPO run `development-ephemeral-1789700631224-20638` passed `rhino-consumer:test:repo`, including public
safety, repository configuration, word budget, directory maps, harness parity, internal links, Mermaid, and plan checks.
Terminal final-readiness verdict: **PASS**. This authorizes no product implementation; Delivery Phase 0 still requires
its fresh execution-time verdict against the then-current repository.

## Destination

Before archival, route each entry into canonical specifications, tests, code comments, durable documentation,
governance, a deduplicated idea, or a recorded discard reason. Do not archive unresolved notes.
