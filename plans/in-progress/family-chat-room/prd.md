# Product Requirements — Family Chat Room

## Personas

- **Family member:** any approved child, parent, or administrator using their own authenticated account.
- **Notification subscriber:** a family member who explicitly enables notifications on one supported browser or installed
  PWA instance.
- **Household operator:** the person maintaining the private Bnest host, SQLite database, and routed PWA.

## User Stories

- As a family member, I can open one shared room and immediately see the newest conversation.
- As a family member, I can send plain text and see it appear for other connected family members without refreshing.
- As a family member, I can scroll upward for older messages without losing my reading position.
- As a family member, I can opt one device into notifications and disable it again.
- As a notification subscriber, I can recognize who wrote and preview the message before opening Bnest.
- As the household operator, I can deploy and recover the capability without interrupting the existing service.

## Acceptance Criteria

### AC-FC-01 — Authenticated family access

Affected routes: `/`, `/login`, and `/family-chat`. Affected states: logged out, child, parent, administrator. Viewports:
desktop, tablet, and mobile.

```gherkin
Scenario Outline: An approved family role opens the shared room
  Given an approved <role> is logged in
  When the family member follows the "Family chat" home link
  Then the current route is "/family-chat"
  And the visible channel is "Main"

Examples:
  | role |
  | children |
  | parents |
  | admin |
```

```gherkin
Scenario: A logged-out visitor requests the family room
  Given no approved user is logged in
  When the visitor opens "/family-chat"
  Then the visitor is redirected to login with a safe return path
  And no family message is rendered
```

### AC-FC-02 — Durable realtime text

Affected route: `/family-chat`. States: empty, sending, committed, validation failure, storage failure. Viewports: desktop,
tablet, and mobile.

```gherkin
Scenario: Two family members exchange a message
  Given two approved family members have the main channel open
  When the first member sends "Dinner is ready"
  Then both members see one committed message "Dinner is ready" from the first member
```

```gherkin
Scenario: A reconnect retries the same submission identity
  Given a family member has an acknowledged client message identity
  When that identity is submitted again after reconnect
  Then the main channel contains exactly one matching message
```

```gherkin
Scenario Outline: Invalid text is rejected
  Given an approved family member has the main channel open
  When the member submits <text>
  Then no message is stored or broadcast
  And the composer explains <reason>

Examples:
  | text | reason |
  | whitespace only | that a message is required |
  | more than 4,000 graphemes | the supported message limit |
  | more than 16 KiB | the supported message limit |
```

```gherkin
Scenario: Markup-like text remains text
  Given an approved family member has the main channel open
  When the member sends "<script>alert('no')</script>"
  Then every member sees the literal text without script execution
```

### AC-FC-03 — Bounded history loading

Affected route: `/family-chat`. States: initial load, loading older, more history, end of history, live arrival while
reading older history. Viewports: desktop, tablet, and mobile.

```gherkin
Scenario: Opening a long conversation loads only the latest window
  Given the main channel contains 125 messages
  When a family member opens the room
  Then exactly the latest 50 messages are rendered in chronological order
  And the newest message is at the bottom
```

```gherkin
Scenario: Scrolling upward loads the preceding page
  Given the latest 50 of 125 messages are rendered
  When the member reaches the history sentinel above the oldest rendered message
  Then the preceding 50 messages appear above without changing the visible reading anchor
```

```gherkin
Scenario: The beginning of history is terminal
  Given all main-channel messages are rendered
  When the member requests older history
  Then no duplicate message appears
  And the room reports that the beginning has been reached
```

```gherkin
Scenario: A live message arrives while older history is visible
  Given a member is reading away from the bottom of the main channel
  When another member sends a message
  Then the reading position stays stable
  And a control announces that a new message is available below
```

### AC-FC-04 — Persistent channel foundation

Affected route: `/family-chat`. States: fresh migration, process restart, mixed old/new release overlap.

```gherkin
Scenario: A fresh database receives the main channel
  Given the family-chat migration has not run
  When the additive release migration completes
  Then exactly one active channel with slug "main" exists
```

```gherkin
Scenario: A committed transcript survives restart
  Given the main channel contains committed messages
  When a fresh application process opens the authoritative SQLite database
  Then the same ordered messages are readable through the family-chat boundary
```

```gherkin
Scenario: The old release overlaps the additive schema
  Given the family-chat tables exist while the prior release is still healthy
  When the prior release serves an existing user-owned journey
  Then that journey continues without reading or mutating the new tables
```

### AC-FC-05 — Voluntary per-device notifications

Affected route: `/family-chat`. States: supported and disabled, permission prompt, enabled, denied, unsupported, not
installed where installation is required. Viewports: desktop, tablet, and mobile.

```gherkin
Scenario: A supported device enables notifications by explicit action
  Given notifications are supported and not enabled on this device
  When the member activates "Enable notifications"
  Then the browser permission request follows that user action
  And an allowed subscription is bound to the authenticated member and device
```

```gherkin
Scenario: A member disables one device
  Given notifications are enabled on two devices for one member
  When the member disables notifications on the first device
  Then future messages target only the second device
```

```gherkin
Scenario Outline: An unsafe push endpoint is rejected without egress
  Given an approved family member has the main channel open
  When the browser submits a subscription endpoint with <condition>
  Then no active subscription is stored
  And Bnest makes no request to that endpoint

Examples:
  | condition |
  | an unapproved host |
  | an IP literal |
  | user information |
  | a non-default port |
  | a URL fragment |
```

```gherkin
Scenario Outline: Notifications cannot be enabled
  Given the current device is <state>
  When the member opens notification settings in family chat
  Then chat remains available
  And the page explains <next action>

Examples:
  | state | next action |
  | unsupported | that this browser cannot receive Web Push |
  | denied | how to change the browser or operating-system permission |
  | iOS web page not installed | how to add Beaver Nest to the Home Screen |
```

### AC-FC-06 — Useful private push content

Affected boundary: installed PWA notification surface and `/family-chat` after activation.

```gherkin
Scenario: Another member's message reaches an enabled phone
  Given a recipient has enabled notifications on a supported installed PWA
  When another member commits a message longer than 120 graphemes
  Then one notification names the sender
  And its body contains a newline-collapsed preview no longer than 120 graphemes
```

```gherkin
Scenario: A sender does not notify their own devices
  Given the sender and recipient each have enabled devices
  When the sender commits a message
  Then no sender-owned subscription receives a delivery job
  And every active recipient subscription receives one delivery job
```

```gherkin
Scenario: A member opens a chat notification
  Given a family-chat notification is visible
  When the member activates it
  Then an existing Beaver Nest window is focused at "/family-chat" or a new one opens there
```

### AC-FC-07 — Bounded push recovery

Affected states: pending, claimed, retryable, delivered, terminal, expired subscription, interrupted claim.

```gherkin
Scenario: A retryable push failure reaches its ceiling
  Given a delivery keeps receiving a retryable failure
  When the dispatcher processes every due attempt
  Then the first attempt occurs immediately
  And the waits before attempts two through five are 30 seconds, 2 minutes, 8 minutes, and 32 minutes
  And no sixth attempt occurs or any attempt after one hour
```

```gherkin
Scenario: A dead subscription is retired
  Given an active subscription receives a 404 or 410 push response
  When the dispatcher records the response
  Then the subscription is unavailable to ordinary delivery selection
  And its delivery becomes terminal without retry
```

```gherkin
Scenario: A push-provider redirect is not followed
  Given an active subscription's approved provider returns a redirect
  When the dispatcher records the response
  Then the delivery becomes terminal as a provider redirect
  And Bnest makes no request to the redirect location
```

```gherkin
Scenario: An interrupted claim is recovered once
  Given a dispatcher claim expires before recording an outcome
  When another healthy dispatcher reconciles due work
  Then one next attempt is claimed with an incremented attempt number
  And the attempt ceiling remains five
```

### AC-FC-08 — Session and cache privacy

Affected routes: `/family-chat` and `/logout`; affected service-worker caches and application logs.

```gherkin
Scenario: Logout disables the current user's device binding
  Given notifications are enabled for the current browser and user
  And notifications are enabled in another browser session for that user
  When that user logs out
  Then the server no longer targets that binding
  And the other browser session remains enabled
```

```gherkin
Scenario: A subscription-store failure does not claim logout succeeded
  Given notifications are enabled for the current browser and user
  When subscription deactivation fails during logout
  Then the browser remains in its authenticated session
  And the page explains that logout must be retried
```

```gherkin
Scenario: Authenticated chat is not cached
  Given the service worker controls the installed PWA
  When the member opens and later logs out of family chat
  Then no authenticated HTML, transcript, subscription secret, or push payload exists in Cache Storage
```

```gherkin
Scenario: Notification secrets stay out of diagnostics
  Given a push request succeeds or fails
  When logs, health responses, and delivery evidence are inspected
  Then no endpoint, encryption key, VAPID private key, message body, or preview is present
```

### AC-FC-09 — Responsive and accessible operation

Affected route: `/family-chat`. States: empty, populated, loading older, end of history, validation error, notification
unsupported/denied/enabled, and new-message-below. Viewports: desktop at 1280×800, tablet at 768×1024, and mobile at
393×852, plus 200% zoom.

```gherkin
Scenario Outline: The room remains operable at each supported viewport
  Given family chat is shown at the <viewport> viewport
  When the member navigates messages, history, notification settings, and composer by keyboard
  Then focus remains visible and follows reading order
  And no control or message requires horizontal page scrolling

Examples:
  | viewport |
  | desktop |
  | tablet |
  | mobile |
```

```gherkin
Scenario: Dynamic chat changes are announced without stealing focus
  Given a keyboard or screen-reader user has focus in the composer
  When an older page loads or a new message arrives
  Then a concise live-region update is announced
  And focus remains in the composer
```

### AC-FC-10 — Continuity-safe active release

Affected boundaries: local slot, Caddy origin, routed Tailscale origin, LiveView/WebSocket reconnect, SQLite, and Web Push
dispatcher.

```gherkin
Scenario: Family chat is promoted without interrupting Bnest
  Given the active revision is healthy and the additive migration is verified
  When a compatible candidate is promoted through Caddy
  Then the routed origin serves the intended revision with zero failed samples
  And routed p95 remains at or below 500 milliseconds with every sample at or below 2 seconds
```

```gherkin
Scenario: Connected family chat survives compatible promotion
  Given two members have the room open with one unsent draft
  When their LiveView connections move to the promoted revision
  Then committed messages and the draft remain visible without a manual refresh
  And subsequent messages are stored and broadcast once
```

## Product Constraints

- The channel is family-wide and uses the current authenticated account as the actor; no user-supplied author identity is
  accepted.
- `use_family_chat` is a shared capability for every valid `children`, `parents`, and `admin` role value, including
  valid combinations; unlike an owned capability, it accepts no owner ID and never broadens an unknown or malformed
  role.
- The server commits before broadcasting or clearing the composer.
- Message ordering is the SQLite integer message ID, not client time or display time.
- Timestamps are stored in UTC and rendered in the browser's locale and timezone.
- The browser creates one stable client message UUID per composer submission and retains it through LiveView recovery.
- Push permission is never requested during page load, login, or PWA installation.
- A submitted push endpoint must use HTTPS port 443 on a code-owned, reviewed browser-provider allowlist. IP literals,
  user information, fragments, non-default ports, unapproved hosts, and redirects are rejected without egress.
- Push acceptance is best-effort beyond the application boundary; successful provider acceptance does not claim that the
  operating system displayed the notification.
- No REST or GraphQL product API is introduced; browser interaction remains behind authenticated LiveView events and the
  existing service-worker scope.

## Out of Scope

WhatsApp import, channel creation or selection, private memberships, message mutation, attachments, rich content,
mentions, reactions, threads, presence, typing state, read state, badges, search, export, retention automation, offline
transcript access, and generalized notifications are deferred to separate plans.
