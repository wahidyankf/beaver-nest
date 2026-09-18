# Business Requirements — Family Chat Room

## Business Need

Bn​est has private individual experiences but no shared household conversation. Family members therefore leave the app
for ordinary coordination. The missing capability is not a general messaging platform: it is one dependable family room
that opens quickly, survives unreliable connectivity, preserves history locally, and does not weaken a 24/7 home service.

The first room must also avoid a dead-end data shape. Naming Family Chat and Room separately now allows a later calendar
or other trusted producer to create room messages without redesigning storage, URLs, or subscriptions.

## People Served

- **Children** need a simple shared room with clear send status and no administrative controls.
- **Parents** need durable conversation that recovers after network loss or closing the installed PWA.
- **Administrators** participate as family members; administration grants no extra chat power in v1.
- **The household operator** needs bounded operational data, complete backups, predictable capacity, and no-downtime
  releases with a safe rollback floor.

## Desired Outcomes

1. Every approved account reaches one canonical family room only after authentication.
2. Accepted messages become durable exactly once before subscribers or push delivery are notified.
3. Offline submissions remain visibly owned by the same signed-in user and resume without manual reconstruction.
4. Reconnect catches up every committed message without duplication or a forced refresh.
5. A future trusted producer can post a system message through an internal service without a public v1 mutation.
6. Optional per-device notifications never determine message durability.
7. Completed push bookkeeping stays bounded while permanent messages and unfinished delivery work remain.
8. The existing full SQLite backup includes chat, runs at 01:00 WIB by default, and remains operator-configurable.
9. Production release and backup work preserve routed availability within the repository latency budgets; Caddy
   promotion moves connected clients off the prior slot without a page refresh or a cross-slot PubSub dependency.

## Business Rules

- Version one has exactly one seeded room: **Ruang Keluarga**. There is no creation, switching, or membership policy.
- All approved roles share room visibility. Browser input never selects another sender or server-side session.
- Messages are permanent plain text. Users cannot edit, delete, or expire them.
- System messages can enter only through an internal authenticated service boundary.
- SQLite is authoritative. Subscriptions may be missed and IndexedDB may be cleared without corrupting history.
- An outbox record is scoped to one stable user identity and room and is deleted after server acknowledgement or logout.
- Authentication expiry pauses the outbox; it must never replay under a different user.
- Notification permission is voluntary per device. The sender's devices are not targeted.
- Final push-delivery rows remain active seven days, soft-deleted seven days, and are then purged. Unfinished rows are not
  age-purged.
- Backup remains a whole-database responsibility. Family Chat does not create a chat-only backup.
- Fresh and existing `prod-sqlite-backup-daily` schedules converge to 01:00 WIB through the public Scheduler service
  after compatible code is active; operators may change the time afterward.

## Success Measures

- Two isolated `test-user-` contexts exchange and catch up messages through GraphQL HTTP/WebSocket at the routed origin.
- A repeated `(room, sender kind, sender ID, client message ID)` returns the original message and creates no duplicate
  delivery rows.
- Offline, reload, reconnect, and release-drain journeys render each server message once and preserve FIFO intent.
- A Caddy promotion closes prior-slot GraphQL sockets, acknowledges replacement subscriptions on the promoted slot within
  ten seconds, catches up a commit made in the gap exactly once, and keeps the prior slot warm for the rollback window.
- Queue status and seven-day expiry remain understandable at desktop, tablet, mobile, keyboard, and screen-reader layers.
- Every named GraphQL query/mutation receives manual `curl` proof; the subscription receives protocol-capable proof.
- A complete restored backup contains room, messages, push subscriptions, delivery state, and scheduler state without
  exposing secrets or message bodies in evidence.
- During backup and release, routed probes record zero failures, p95 at or below 500 ms, and every sample at or below
  two seconds.
- Capacity preflight uses actual database size/page count and refuses a snapshot before disk exhaustion.

## Non-Goals

- Replacing WhatsApp or importing its history.
- Multiple rooms, room management, calendar behavior, or a public system-message operation.
- Offline-readable committed transcript or service-worker caching of authenticated content.
- Background Sync or delivery while the app is closed.
- Guaranteed OS display after a push provider accepts a request.
- User-configurable message retention, export, discovery, or moderation.

## Risks and Responses

| Risk                                                                 | Business impact                                   | Planned response                                                                                 |
| -------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| A reconnect misses a realtime event                                  | Conversation appears incomplete                   | Subscribe first, query by last committed ID, and dedupe                                          |
| Offline work crosses accounts                                        | A message could be sent as the wrong person       | Namespace by stable user/room, pause on auth expiry, clear on logout                             |
| Queue growth becomes invisible                                       | Users believe unsent text was delivered           | Cap at 100 and show explicit states and expiry                                                   |
| Notification preview appears on lock screen                          | Family content may be visible                     | Explicit opt-in and clear preview disclosure                                                     |
| Backup competes with writes                                          | Routed service slows or fails                     | Dedicated `VACUUM INTO`, capacity guard, timeout, telemetry, and load proof                      |
| Snapshot exhausts disk                                               | Backup or service can fail                        | Reserve from measured `B0`; fail before starting when capacity is insufficient                   |
| Mixed releases disagree on handlers/schema                           | Rollout or rollback becomes unsafe                | Compatibility release, fixed subscription pool, dormant UI, drain, rollback floor                |
| A socket remains on the independent prior slot after Caddy promotion | Realtime commits on the promoted slot are delayed | Omit nonzero `stream_close_delay`, reconnect to the promoted slot, then subscribe-first catch up |
| Split specs duplicate behavior                                       | No single source of truth                         | One canonical BE or FE owner per scenario plus aggregate ownership checks                        |

## Material Decisions

- The user selected room terminology and canonical Indonesian room identity over the previous `main` channel model.
- GraphQL is the sole UI-facing backend boundary; internal scheduler, backup, retention, and producer services stay typed
  in-process interfaces.
- IndexedDB persistence is selected over memory-only retry or Background Sync.
- Absinthe subscriptions are an update transport; subscribe-then-catch-up is selected over treating PubSub as storage.
- Whole-SQLite `VACUUM INTO` is retained because it produces a consistent live snapshot and Exqlite does not expose the
  incremental SQLite Backup API; the forced full WAL checkpoint leaves the hot path.
- The specification and E2E split uses OSE's boundary-specific corpus principle while retaining Bnest names and owners.
