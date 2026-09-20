# Product Requirements — Family Chat Room

## Personas

- **Family member:** an approved child, parent, or administrator using their own authenticated account.
- **Notification subscriber:** a family member who explicitly enables one supported browser/PWA device.
- **Household operator:** the person maintaining the private host, SQLite database, backup destination, and release route.
- **Trusted producer:** future internal code that may post a system-authored room message without browser authority.

## User Stories

- As a family member, I can enter **Ruang Keluarga** and see current and older conversation.
- As a family member, I can send while disconnected, understand the state, and resume from the same account later.
- As a family member, I receive committed messages after reconnect without duplicates or a forced refresh.
- As a family member, I can opt one device into notifications and disable it again.
- As the household operator, I can back up, restore, release, and roll back the feature without stopping Bnest.
- As a future trusted producer, I have an internal system-message service that does not expose browser impersonation.

## Acceptance Criteria

### AC-FC-01 — Authenticated canonical room access

```gherkin
Scenario Outline: An approved family role opens Ruang Keluarga
  Given an approved <role> is logged in
  When the member follows the "Family chat" home link
  Then the route is "/family-chat/ruang-keluarga"
  And the visible room name is "Ruang Keluarga"

Examples:
  | role |
  | children |
  | parents |
  | admin |
```

```gherkin
Scenario: The family-chat root selects the default room
  Given an approved family member is logged in
  When the member opens "/family-chat"
  Then the response redirects to "/family-chat/ruang-keluarga"
```

```gherkin
Scenario: A logged-out visitor requests the family room
  Given no approved user is logged in
  When the visitor opens "/family-chat/ruang-keluarga"
  Then the visitor is redirected to login with a safe return path
  And no family message is rendered
```

### AC-FC-02 — Durable GraphQL text

```gherkin
Scenario: Two family members exchange a message through GraphQL
  Given two approved family members have subscribed to "ruang-keluarga"
  When the first member sends "Dinner is ready" with a new client message ID
  Then the mutation returns one committed user message
  And both members observe that server message ID once
```

```gherkin
Scenario: A retry returns the existing committed message
  Given a user message was acknowledged for one client message ID
  When the same room sender and client message ID are submitted again
  Then the mutation returns the original server message ID
  And no second message or push delivery is stored
```

```gherkin
Scenario Outline: Invalid text stops without publication
  Given an approved member is authenticated to GraphQL
  When the member submits <text>
  Then the response contains a validation error
  And no message or subscription event is produced

Examples:
  | text |
  | whitespace only |
  | more than 4,000 graphemes |
  | more than 16 KiB |
```

```gherkin
Scenario: Markup-like text remains text
  Given an approved member has Ruang Keluarga open
  When the member sends "<script>alert('no')</script>"
  Then every member sees the literal text without script execution
```

### AC-FC-03 — Bounded GraphQL history

```gherkin
Scenario: Opening a long room loads only the latest page
  Given Ruang Keluarga contains 125 messages
  When the member queries messages with no cursor
  Then the latest 50 messages return in chronological order
```

```gherkin
Scenario: Scrolling upward loads the preceding page
  Given the latest 50 of 125 messages are rendered
  When the member queries with the oldest rendered ID as beforeId
  Then the preceding 50 appear above without changing the reading anchor
```

```gherkin
Scenario: Catch-up returns every later commit
  Given server message 80 is the last committed message held by the browser
  When the member queries with 80 as afterId
  Then every later authorized message returns once in ascending ID order
```

```gherkin
Scenario: Conflicting pagination cursors are rejected
  Given an approved member is authenticated to GraphQL
  When a messages query supplies both beforeId and afterId
  Then the response contains an input error and no history data
```

### AC-FC-04 — Persistent room and sender foundation

```gherkin
Scenario: A fresh database receives Ruang Keluarga
  Given the family-chat migration has not run
  When the additive migration completes
  Then exactly one room has ID 1 slug "ruang-keluarga" name "Ruang Keluarga"
  And that room allows member posting as a conversation
```

```gherkin
Scenario: A trusted producer posts a system message
  Given an internal producer has a stable system sender ID
  When it posts through the Family Chat service to "ruang-keluarga"
  Then one committed system message contains that sender identity and display snapshot
```

```gherkin
Scenario: A browser cannot post a system message
  Given an approved member is authenticated to the public GraphQL schema
  When the client inspects available mutations
  Then no system-message mutation is available
```

```gherkin
Scenario: The old release overlaps the additive schema
  Given the family-chat tables exist while the prior release is healthy
  When the prior release serves an existing journey
  Then that journey continues without reading or mutating the new tables
```

### AC-FC-05 — Voluntary per-device notifications

```gherkin
Scenario: A supported device enables notifications by explicit action
  Given notifications are supported and disabled on this device
  When the member activates "Enable notifications"
  Then the browser permission request follows that action
  And the GraphQL mutation binds the subscription to the current user and session
```

```gherkin
Scenario: A member disables one device
  Given notifications are enabled on two devices for one member
  When the member disables notifications on the first device
  Then future messages target only the second device
```

```gherkin
Scenario Outline: An unsafe push endpoint is rejected without egress
  Given an approved member is authenticated to GraphQL
  When the browser submits an endpoint with <condition>
  Then no active subscription is stored
  And Bnest makes no request to that endpoint

Examples:
  | condition |
  | an unapproved host |
  | an IP literal |
  | a non-default port |
  | a redirect target |
```

### AC-FC-06 — Useful bounded push content

```gherkin
Scenario: Another member's message creates bounded notification content
  Given a recipient enabled notifications and another member committed a message longer than 120 graphemes
  When the service worker handles the resulting family-chat push event
  Then it calls showNotification once with the committed sender display name
  And the newline-collapsed preview passed to that call is no longer than 120 graphemes
```

```gherkin
Scenario: A sender does not notify their own devices
  Given sender and recipient devices are enabled
  When the sender commits a message
  Then no sender-owned subscription receives a delivery row
  And each active recipient subscription receives one delivery row
```

```gherkin
Scenario: A member opens a family-chat notification
  Given a family-chat notification is visible
  When the member activates it
  Then Bnest focuses or opens "/family-chat/ruang-keluarga"
```

### AC-FC-07 — Bounded push recovery

```gherkin
Scenario: A retryable push failure reaches its ceiling
  Given a delivery keeps receiving retryable failures
  When every due attempt is processed
  Then the waits before attempts two through five are 30 seconds 2 minutes 8 minutes and 32 minutes
  And no sixth attempt or attempt after one hour occurs
```

```gherkin
Scenario: A dead subscription is retired
  Given an active subscription receives a 404 or 410 response
  When the dispatcher records the response
  Then the subscription is unavailable to delivery selection
  And its delivery becomes terminal without retry
```

### AC-FC-08 — Session and browser privacy

```gherkin
Scenario: Logout clears the current user's local and server device state
  Given the current user has queued messages and an enabled push subscription
  When that user logs out successfully
  Then that user's IndexedDB outbox records are removed
  And that session's server subscription is disabled
```

```gherkin
Scenario: Authentication expiry pauses queued work
  Given one user's queued message is waiting for retry
  When the session expires before a retry
  Then the queue pauses without sending
  And a later different user cannot drain that record
```

```gherkin
Scenario: Authenticated content is not cached
  Given the service worker controls the installed PWA
  When the member uses and logs out of family chat
  Then Cache Storage contains no authenticated HTML transcript push payload or subscription secret
```

```gherkin
Scenario: Diagnostics disclose no private values
  Given chat push backup or GraphQL work succeeds or fails
  When logs health and delivery evidence are inspected
  Then no message body endpoint key cookie session value private origin or user value appears
```

### AC-FC-09 — Responsive and accessible operation

```gherkin
Scenario Outline: The room remains operable at each supported viewport
  Given Ruang Keluarga is shown at the <viewport> viewport
  When the member uses history notifications queued messages and composer by keyboard
  Then focus remains visible and follows reading order
  And no control or message requires horizontal page scrolling

Examples:
  | viewport |
  | desktop 1280 by 800 |
  | tablet 768 by 1024 |
  | mobile 393 by 852 |
  | 200 percent zoom |
```

```gherkin
Scenario: Dynamic send and history changes are announced
  Given a screen-reader user has focus in the composer
  When connectivity or message delivery state changes
  Then one concise live-region update announces the new state
  And focus remains in the composer
```

### AC-FC-10 — Continuity-safe active release

**V1 scope note (2026-09-20, explicit user decision):** the "Connected clients recover without refresh" and "A
commit during socket cutover is caught up exactly once" scenarios below require holding authenticated GraphQL
sockets across a real production Caddy promotion driven by the actual `release:run` pipeline. Proving them for real
needs backend scope this delivery never built — a service-account auth path for the family-chat socket, an isolated
probe room, and a telemetry mechanism tech-doc 009 does not specify. Every real release this plan ran instead
proved `routed-liveview` continuity (zero failed routed samples, budgeted latency), and Phase 8 proved the
subscribe/resubscribe/catch-up mechanism itself against an isolated FE_E2E test environment — but neither
constitutes the literal proof these two scenarios describe. Formally accepted as residual risk for v1 rather than
built now; a future plan may pick this up if warranted. See `delivery.md`'s AC-FC-10 item and `learnings.md`'s
Resolution Ledger for the full trail.

```gherkin
Scenario: Compatibility and experience releases preserve the route
  Given the current revision is healthy and two members hold connected room clients
  When compatible and experience revisions are promoted in order through Caddy
  Then the intended revision serves with zero failed routed samples
  And routed p95 is at most 500 milliseconds with every sample at most 2 seconds
```

```gherkin
Scenario: Connected clients recover without refresh
  Given the active and candidate slots use independent local PubSub
  And two members hold GraphQL sockets on the active slot
  And one member retains a draft
  When Caddy reload promotes the candidate without a nonzero stream close delay
  Then both prior-slot sockets close
  And both clients acknowledge replacement subscriptions on the promoted revision within 10 seconds
  And the draft remains without a page refresh
```

```gherkin
Scenario: A commit during socket cutover is caught up exactly once
  Given the prior-slot socket has closed during Caddy promotion
  When a message commits before the replacement subscription is acknowledged
  Then the promoted client subscribes before querying after its last committed message ID
  And the committed message renders exactly once
  And queued sends remain paused until catch-up completes
```

```gherkin
Scenario: The prior slot remains a warm rollback floor during observation
  Given Caddy routes new HTTP and WebSocket handshakes only to the promoted slot
  When the five-minute post-promotion observation runs
  Then the prior slot remains healthy but receives no routed handshake
  And it is retired only after the routed and reconnect budgets pass
```

### AC-FC-11 — Bounded delivery-record retention

```gherkin
Scenario Outline: Final delivery history becomes inactive after seven days
  Given a push delivery completed as <state> more than seven days ago
  When the daily retention schedule runs
  Then ordinary delivery inspection no longer returns it

Examples:
  | state |
  | delivered |
  | terminal |
```

```gherkin
Scenario Outline: Retention preserves unfinished delivery work
  Given a push delivery in <state> is older than seven days
  When the retention schedule runs
  Then that delivery remains in <state>

Examples:
  | state |
  | pending |
  | claimed |
  | retryable |
```

```gherkin
Scenario: Soft-deleted delivery evidence is purged after its grace period
  Given a final delivery was soft-deleted more than seven days ago
  When the retention schedule runs
  Then no row for that delivery remains in SQLite
```

### AC-FC-12 — Offline outbox and recovery

```gherkin
Scenario: An offline send waits across app reopen
  Given an authenticated member is offline with fewer than 100 queued records for the room
  When the member submits a message and later reopens the app as the same user
  Then the same client message ID remains in IndexedDB as "Waiting for connection"
```

```gherkin
Scenario: Reconnect catches up before draining FIFO
  Given the browser missed committed messages and has two queued sends
  When connectivity returns
  Then it subscribes and queries after the last committed server ID before sending queued work
  And the two queued messages are acknowledged in FIFO order
```

```gherkin
Scenario: Retryable failure uses bounded backoff
  Given a queued message receives network or server failures
  When automatic retry remains active
  Then waits progress through 1 2 4 8 16 and 32 seconds and then at most 60 seconds with jitter
  And an online event makes the next retry immediately eligible
```

```gherkin
Scenario Outline: A non-retryable GraphQL result stops automatic retry
  Given a queued message is being sent
  When GraphQL returns <result>
  Then its status becomes "Couldn't send"
  And no automatic retry occurs

Examples:
  | result |
  | validation failure |
  | forbidden |
  | room not found |
```

```gherkin
Scenario: A seven-day-old queued message requires manual retry
  Given an unacknowledged queue record is older than seven days
  When the same user reopens Ruang Keluarga
  Then automatic delivery does not start
  And the UI offers a manual retry or discard action
```

```gherkin
Scenario: The per-room queue limit is enforced
  Given one user has 100 queued records for Ruang Keluarga
  When that user submits another offline message
  Then no 101st record is stored
  And the UI explains how to retry or discard existing work
```

### AC-FC-13 — Whole-database backup and capacity

```gherkin
Scenario: Existing and fresh schedules converge to 01:00 WIB
  Given compatible Scheduler and Backup services are active
  When release reconciliation runs for "prod-sqlite-backup-daily"
  Then its daily time is 18:00 UTC
  And an operator can change the time afterward through the supported settings boundary
```

```gherkin
Scenario: Backup refuses insufficient capacity before snapshot work
  Given measured free space is below the required database snapshot reserve
  When the backup service performs preflight
  Then no VACUUM INTO starts
  And the scheduler records a retryable capacity failure
```

```gherkin
Scenario: Concurrent writes continue during backup
  Given routed write probes and a dedicated backup connection are active
  When VACUUM INTO creates the complete SQLite snapshot
  Then every routed probe finishes within 2 seconds with zero failures
  And the measured p95 is at most 500 milliseconds
```

```gherkin
Scenario: A restored backup contains all family-chat state
  Given a verified whole-database backup was created
  When it is restored into an isolated marked root
  Then room messages push subscriptions delivery state and scheduler state are readable
  And proof contains no secret or message body
```

## Product Constraints

- Public operations are exactly `familyChatRooms`, `familyChatRoom(slug)`,
  `familyChatMessages(roomSlug, beforeId, afterId, limit)`,
  `sendFamilyChatMessage(roomSlug, clientMessageId, body)`, `webPushConfiguration`,
  `currentWebPushSubscription`, `upsertWebPushSubscription(input)`,
  `disableCurrentWebPushSubscription`, and `familyChatMessageCommitted(roomSlug)`.
- Pagination accepts at most one cursor; limit defaults to 50 and never exceeds 50.
- GraphiQL is disabled in production. HTTP mutations require the authenticated session cookie and CSRF protection.
  Socket identity comes from the server-side session, and every resolver authorizes the requested room.
- The browser retains one UUID until acknowledgement. It deletes acknowledged or logged-out records and never stores
  committed history in IndexedDB or Cache Storage.
- `navigator.onLine` is only a hint. Any actual request failure returns to bounded backoff.
- Queue retry runs while the app is active and resumes on reopen; Background Sync is not used.
- Message ordering uses SQLite integer ID. Timestamps use UTC storage and local presentation.
- No room CRUD, calendar, attachment, edit/delete, presence, typing, or public system-message mutation exists in v1.
- The backup schedule remains configurable after the release-owned one-time convergence to 01:00 WIB.

## Out of Scope

WhatsApp import, multiple-room UX, calendar behavior, offline transcript storage, background delivery, message mutation,
attachments, rich content, mentions, reactions, threads, presence, typing, read state, badges, search, export, message
retention, and generalized notifications are deferred.
