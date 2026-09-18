# GraphQL API, Authentication, and Errors

## Purpose and Endpoints

This document is the executable public-boundary contract for every UI-facing family-chat and Web Push operation.

- HTTP: `POST /api/graphql`
- Subscription socket: `/api/graphql/socket`
- Browser shell: Phoenix-rendered `/family-chat/ruang-keluarga`
- GraphiQL: development/test only; no production route or production compile-time enablement

There is no REST or LiveView-command alternative. Internal Scheduler, Backup, retention, dispatcher, and system-message
operations remain typed Elixir service calls and are intentionally absent from GraphQL.

## HTTP Pipeline

1. Accept only `POST` with `application/json`. Reject malformed JSON with HTTP 400, request envelopes above 64 KiB with
   413, unsupported methods with 405, and unsupported media types with 415 before resolver execution. The endpoint does
   not support multipart uploads.
2. Fetch the existing signed HTTP-only Phoenix session and resolve the current user through the normal identity service.
3. For every cookie-authenticated GraphQL POST, validate the same-origin CSRF token supplied by the authenticated shell.
   This uniform pre-parse rule necessarily covers every mutation. The browser uses `credentials: "same-origin"` and an
   `x-csrf-token` header; the token is never written to IndexedDB or logs.
4. Build context with server-owned `current_user`, approved role/capabilities, and current `session_digest`.
5. Parse/validate the GraphQL document, then run resolver middleware that requires authentication and room authorization.
6. Serialize only declared fields and stable safe errors. Apply no resolver fallback that turns an exception into success.

Anonymous requests receive no room/message/subscription data. A valid login without `use_family_chat` receives the same
safe forbidden/not-found semantics without learning hidden room state. Browser parameters named `userId`, `senderKind`,
`senderId`, `sessionDigest`, or role are ignored as unknown input or rejected by schema validation.

## Socket Handshake and Session

Endpoint socket configuration exposes `/api/graphql/socket` with secure WebSocket, origin checking, and Phoenix
`connect_info` session extraction using the same cookie/session options as HTTP. The connect callback:

1. reads only the server-decoded session from `connect_info`;
2. resolves the active user and session digest;
3. rejects missing, revoked, expired, or malformed identity;
4. injects the authenticated context through `Absinthe.Phoenix.Socket.put_options/2`; and
5. never accepts identity, role, or authorization from socket params.

The browser may send protocol/version metadata required by the supported Absinthe socket client. Those values do not
alter identity. Same-origin cookie delivery plus endpoint origin checking protects the handshake; mutation CSRF tokens
are not reused as socket identity. Logout closes the client socket, disables the session's push binding, clears its
IndexedDB namespace, and revokes the server session.

All slots start `Absinthe.Subscription` with code-owned `pool_size: 8`. Readiness compares the effective value with the
release manifest so a mismatched candidate cannot be promoted. Publication uses Phoenix PubSub already owned by the
endpoint.

Production blue/green slots run with `RELEASE_DISTRIBUTION=none`; their subscription registries and Phoenix PubSub are
not shared. Promotion therefore reloads Caddy without a nonzero `stream_close_delay`, closing old-config WebSockets so
the browser reconnects through the promoted route. A close pauses sends; replacement subscription acknowledgement and
`afterId` catch-up must complete before FIFO draining resumes.

## Shared Scalars and Objects

- `ID` values for messages/cursors parse as positive SQLite integers. The client treats them as opaque strings and does
  not perform arithmetic.
- `DateTime` serializes canonical UTC ISO-8601 and rejects timezone-free input.
- Room slugs are lowercase ASCII kebab-case, 1–64 bytes. V1 authorization recognizes only active `ruang-keluarga`.
- `FamilyChatMessage.body` is the committed normalized plain-text string. Rendering must escape it.
- `senderKind` is `USER` or `SYSTEM`; `senderId` is output-only stable identity.
- Push subscription endpoints/keys are input-only and never returned. Query state exposes enabled/expiration only.

## Queries

### `familyChatRooms`

```graphql
query FamilyChatRooms {
  familyChatRooms {
    id
    slug
    name
    roomKind
    memberPostingEnabled
  }
}
```

For every approved role, v1 returns one active authorized room ordered by server ID. It returns an empty list only when
the authenticated user has no authorized room; seed absence is an operational readiness failure, not a normal v1 state.

### `familyChatRoom(slug)`

```graphql
query FamilyChatRoom($slug: String!) {
  familyChatRoom(slug: $slug) {
    id
    slug
    name
    roomKind
    memberPostingEnabled
  }
}
```

`{"slug":"ruang-keluarga"}` returns the seed. A syntactically invalid slug produces `null` plus
`VALIDATION_FAILED`. Authentication and the top-level `use_family_chat` capability are checked before resolving the
slug; a user lacking that capability receives `FORBIDDEN`. After that capability check, an absent, deleted, or
room-unauthorized slug produces `ROOM_NOT_FOUND`, so callers cannot enumerate hidden rooms.

### `familyChatMessages(roomSlug, beforeId, afterId, limit)`

```graphql
query FamilyChatMessages(
  $roomSlug: String!
  $beforeId: ID
  $afterId: ID
  $limit: Int
) {
  familyChatMessages(
    roomSlug: $roomSlug
    beforeId: $beforeId
    afterId: $afterId
    limit: $limit
  ) {
    nodes {
      id
      roomSlug
      senderKind
      senderId
      senderDisplayName
      body
      committedAt
    }
    hasOlder
    hasNewer
  }
}
```

No cursor means latest. Exactly one of `beforeId` or `afterId` is allowed. Limit defaults to 50, accepts 1–50, and rejects
0, negative, or above-50 values with `VALIDATION_FAILED`. Nodes are ascending. `beforeId` supports upward history;
`afterId` supports reconnect catch-up. Cursors do not reveal whether that ID belongs to another room.

### `webPushConfiguration`

```graphql
query WebPushConfiguration {
  webPushConfiguration {
    available
    applicationServerKey
    unavailableReason
  }
}
```

The public key is returned only when configured and safe. `unavailableReason` is an allowlisted UI category such as
`NOT_CONFIGURED` or `UNSUPPORTED_SERVER`; it contains no path/value. Production readiness normally prevents the enabled
experience from serving an unconfigured state.

### `currentWebPushSubscription`

```graphql
query CurrentWebPushSubscription {
  currentWebPushSubscription {
    enabled
    expirationTime
  }
}
```

The resolver selects by current user and server-derived session digest. It never returns endpoint, digest, or keys.

## Mutations

### `sendFamilyChatMessage`

```graphql
mutation SendFamilyChatMessage(
  $roomSlug: String!
  $clientMessageId: ID!
  $body: String!
) {
  sendFamilyChatMessage(
    roomSlug: $roomSlug
    clientMessageId: $clientMessageId
    body: $body
  ) {
    id
    roomSlug
    senderKind
    senderId
    senderDisplayName
    body
    committedAt
  }
}
```

`clientMessageId` is a canonical UUID string generated once before IndexedDB insertion. Success means the message and
all new push delivery rows committed atomically. Repeating the same room/current-user/UUID returns the original message,
even when the repeated body differs, and creates no delivery. The resolver publishes only after a new commit; returning
an existing row does not emit a second subscription event.

### `upsertWebPushSubscription`

```graphql
mutation UpsertWebPushSubscription($input: WebPushSubscriptionInput!) {
  upsertWebPushSubscription(input: $input) {
    enabled
    expirationTime
  }
}
```

Input accepts exactly `endpoint`, optional `expirationTime`, `p256dh`, and `auth`. Reject unknown nested keys, unsafe URL,
invalid base64url, wrong decoded key lengths, or unapproved provider before database mutation/egress. Ownership is derived
from context. Success returns state only.

### `disableCurrentWebPushSubscription`

```graphql
mutation DisableCurrentWebPushSubscription {
  disableCurrentWebPushSubscription {
    enabled
    expirationTime
  }
}
```

This operation is idempotent and affects only the current server-derived session binding. Success returns
`enabled: false` whether a row was newly disabled or already absent.

## Subscription

```graphql
subscription FamilyChatMessageCommitted($roomSlug: String!) {
  familyChatMessageCommitted(roomSlug: $roomSlug) {
    id
    roomSlug
    senderKind
    senderId
    senderDisplayName
    body
    committedAt
  }
}
```

Configuration resolves and authorizes the room, then uses internal room ID as the topic. The service publishes only a
newly committed public message after transaction success. The browser treats delivery as at-least-once and lossy:
duplicate events dedupe by ID, and missed events come from `afterId` catch-up. A subscription acknowledgement is not a
history checkpoint.

## Error Matrix

| Condition                                         | Transport                           | GraphQL code             | Retry policy                             |
| ------------------------------------------------- | ----------------------------------- | ------------------------ | ---------------------------------------- |
| Missing/expired session after valid transport     | 200 envelope                        | `UNAUTHENTICATED`        | Pause outbox                             |
| Missing/invalid CSRF on cookie-authenticated POST | 403 JSON envelope                   | `CSRF_REJECTED`          | Stop request; refresh shell/session flow |
| Unsupported method                                | 405 JSON envelope                   | safe transport category  | Do not retry unchanged                   |
| Request envelope above 64 KiB                     | 413 JSON envelope                   | safe transport category  | Do not retry unchanged                   |
| Unsupported content type                          | 415 JSON envelope                   | safe transport category  | Do not retry unchanged                   |
| Valid session lacks room capability               | 200 envelope                        | `FORBIDDEN`              | Stop automatic retry                     |
| Missing/inactive room                             | 200 envelope                        | `ROOM_NOT_FOUND`         | Stop automatic retry                     |
| Invalid cursor/limit/body/UUID/input              | 200 envelope                        | `VALIDATION_FAILED`      | Stop automatic retry                     |
| Idempotent duplicate                              | 200 envelope with original data     | none                     | Acknowledge/delete queue                 |
| SQLite busy/transient resolver failure            | 200 envelope                        | `INTERNAL` safe category | Retry with server-failure policy         |
| Malformed JSON/body envelope                      | 400 JSON envelope                   | safe transport category  | Do not retry unchanged                   |
| GraphQL syntax/schema validation                  | 200 envelope                        | GraphQL validation       | Do not retry unchanged                   |
| Provider failure after message commit             | Message mutation remains successful | none on send             | Server push outbox owns retry            |

Reverse-proxy/network 5xx remains automatically retryable. The browser never treats HTTP 200 alone as success; it
classifies transport status and `errors[].extensions.code`, and requires the expected non-null `data` field before
acknowledgement.

## Manual API Proof

Start one isolated exact-origin server with synthetic `test-user-` sessions and a marked SQLite root. For each query and
mutation, use `curl` with the actual content type, cookie jar, CSRF header where applicable, operation name, query, and
variables. Record only redacted command shape and response shape. Prove:

- authorized success and anonymous/forbidden failure;
- default, `beforeId`, `afterId`, both-cursor, and limit boundaries;
- valid send, duplicate UUID, invalid body, missing room, and transaction side effect;
- push configuration, current state, safe/unsafe upsert, and idempotent disable; and
- response status, `data`, `errors`, code, and independently observed SQLite/service effect.

Use a protocol-capable Phoenix/Absinthe client for socket connection, subscription acknowledgement, post-commit event,
duplicate-tolerant merge, disconnect, reconnect, and catch-up. `curl` of a WebSocket upgrade is handshake evidence only
and cannot satisfy the subscription scenario. Release proof additionally holds a socket on the prior routed revision,
reloads Caddy, observes its close, acknowledges a promoted-revision subscription within ten seconds, and recovers a gap
commit exactly once. Cleanup cookies, database, ports, sockets, and processes in `finally` and fail the proof if cleanup
fails.

## Contract Evolution

Additive fields and future room results may be introduced without breaking v1 clients. Removing/renaming operations,
changing nullability, reinterpreting sender identity, increasing authorization scope, or replacing ID ordering is a
breaking change and requires a separate compatibility plan. A future public system-message mutation is explicitly not an
additive implementation detail; it requires a new security/product decision.
