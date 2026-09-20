# Web Push, GraphQL, and Privacy

## Platform Boundary

Web Push uses the Push API, Notifications API, service worker, RFC 8291 encryption, and RFC 8292 VAPID. Browser push
providers transport encrypted payloads but never store authoritative chat history. Feature detection, not browser-name
checks, controls UI. iOS/iPadOS requires an installed Home Screen web app and a user-triggered permission request.

Primary references:

- [Web Push for Web Apps on iOS and iPadOS](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
- [W3C Push API](https://www.w3.org/TR/push-api/)
- [RFC 8291](https://www.rfc-editor.org/rfc/rfc8291)
- [RFC 8292](https://www.rfc-editor.org/rfc/rfc8292)

## GraphQL Ownership

All UI-facing push operations use GraphQL:

- `webPushConfiguration` returns only the public application key and supported/unavailable state;
- `currentWebPushSubscription` describes whether this authenticated server-side session has a binding;
- `upsertWebPushSubscription(input)` validates and binds one browser subscription to the current user/session; and
- `disableCurrentWebPushSubscription` disables only the current session binding.

No LiveView push event or REST alternative exists. HTTP mutations require session cookie and CSRF. Resolvers ignore
browser ownership fields and derive user ID and session digest from server context. GraphQL responses, variables, and
errors are excluded from value-bearing logs.

## Permission UX

Page load never calls `Notification.requestPermission()` or `pushManager.subscribe()`. The room shows:

- **Enable notifications** when APIs are available and permission is not denied;
- **Notifications on** plus **Turn off** when the current session binding exists;
- **Notifications blocked** after denial, without repeated prompt;
- **Install Beaver Nest first** when platform installation is required; or
- **Notifications unavailable in this browser** after feature detection fails.

An unsupported or denied device still has complete chat behavior.

## Endpoint Egress Policy

A subscription endpoint is untrusted. Before storage and again before egress, require HTTPS, no user information, no
fragment, no IP literal, no non-443 port, bounded lengths, exact Web Push key shapes, and a code-owned browser-provider
allowlist. Reject unknown input keys. The HTTP sender disables redirects; any `3xx` is terminal and its location is never
requested. A rejected endpoint stores nothing and causes no network access.

Delivery revalidates current Apple, Mozilla, and Chromium endpoint guidance before manifest changes. Adding a provider
requires reviewed code/spec/tests; no unrestricted environment host override is permitted.

Validation order is pure parse/shape/allowlist first, database mutation second, egress only in the dispatcher. The
allowlist compares normalized lower-case ASCII hostnames by exact match or explicitly approved suffix with a dot boundary;
`evilpush.apple.com.example` and Unicode lookalikes do not match. DNS resolution is never used to expand authorization.
The Req call sets a bounded connect/request timeout, sends one POST, and disables automatic redirects.

## Payload

```json
{
  "type": "family-chat-message",
  "messageId": 123,
  "title": "Aisha",
  "body": "Dinner is ready. Please come downstairs…",
  "tag": "family-chat-message-123",
  "url": "/family-chat/ruang-keluarga"
}
```

Title is the committed display snapshot. Body collapses whitespace and truncates to 120 graphemes with one ellipsis.
The deterministic tag makes ambiguous provider retries replace the same visible notification where supported. The
payload contains no user ID, room database ID, endpoint, session digest, key, private origin, or VAPID value.

## Delivery and Retention

The message transaction creates one delivery row per active subscription belonging to another user. A system message
targets all active user subscriptions. The sender dispatches encrypted requests under bounded leased work:

| Result                          | State             | Action                          |
| ------------------------------- | ----------------- | ------------------------------- |
| `2xx`                           | delivered         | Stop and record acceptance time |
| `404/410`                       | terminal/gone     | Disable subscription; no retry  |
| `3xx`                           | terminal/redirect | Never follow                    |
| other `4xx`                     | terminal/provider | No retry                        |
| `429`, `5xx`, timeout, DNS, TLS | retryable         | Fixed server-side push waits    |

Push uses five attempts: immediate, then 30 seconds, 2 minutes, 8 minutes, and 32 minutes after retryable failures, with
an absolute one-hour ceiling. This is independent from the browser outbox's faster reconnect backoff.

The `family-chat-push-retention-daily` handler calls `PushNotifications.retain_deliveries/1`. Final rows are active seven
days, soft-deleted seven more days, and then purged. Unfinished rows are never age-purged. Scheduler and handler expose
aggregate counts only and contain no store alias or SQL.

## VAPID and Dependencies

The implementation adds a maintained Web Push protocol library rather than handwritten cryptography. Delivery repeats
the dependency-selection review against the locked Elixir/OTP stack, checks checksum/license/advisories/RFC vectors, and
records the chosen exact version before editing `mix.exs`. A failed requirement returns the plan for amendment; it does
not authorize an improvised substitute.

The private key and subject stay in machine-local protected configuration. Production readiness fails closed for missing
or malformed values. Tests use deterministic synthetic keys and a loopback sender; evidence records only configured
state. Key rotation remains out of scope because it invalidates subscriptions and needs its own user journey.

## Logout, IndexedDB, and Cache Boundaries

Logout ordering is fail-closed:

1. identify the current server-side session and browser user namespace;
2. disable that session's push binding through GraphQL/service code;
3. clear that user's family-chat IndexedDB outbox records;
4. revoke identity and clear cookies; and
5. navigate to logged-out UI.

If server deactivation fails, the authenticated session remains and the UI asks for retry. If local deletion fails, the
browser blocks account switching in that tab until cleanup succeeds or the user explicitly clears site data; queued
intent must not become available to another account.

The service worker cache is an explicit static allowlist for built CSS/JS, manifest, and owned icons. It excludes every
navigation response, `/api/graphql`, `/api/graphql/socket`, authenticated HTML, messages, IndexedDB contents, health,
and push payloads. Activate deletes only superseded Bnest cache names.

The fetch handler does not use a catch-all cache-first or stale-while-revalidate branch. Navigation and GraphQL requests
always go to network and receive the normal offline failure. Static cache keys are same-origin build artifacts with a
versioned cache name. `push` parses a bounded JSON object and ignores unknown keys; invalid data displays a generic
**New family message** linking to `/family-chat/ruang-keluarga`. `notificationclick` accepts only that same-origin fixed
path, closes the notification, focuses/navigates an existing Bnest client when possible, or opens a new one.

## Threat Model

| Threat                                | Boundary                      | Required control                                       | Proof                                 |
| ------------------------------------- | ----------------------------- | ------------------------------------------------------ | ------------------------------------- |
| Browser claims another sender         | GraphQL mutation              | Context-derived current user; no sender input          | Schema and resolver tests             |
| Browser claims another session        | Push mutation/socket          | Server session digest from HTTP/socket                 | Two-session integration/E2E           |
| CSRF sends a message/subscription     | Cookie-authenticated HTTP     | Same-origin CSRF validation on mutations               | Missing/invalid token API proof       |
| Cross-site socket uses ambient cookie | WebSocket handshake           | Endpoint origin check and session connect info         | Rejected-origin handshake test        |
| Push endpoint performs SSRF           | Subscription input/dispatcher | Strict provider allowlist twice; redirects off         | No-egress fixtures and loopback proof |
| Queue crosses logout/login            | IndexedDB                     | Stable user namespace, fail-closed cleanup, auth pause | Two-user reload journey               |
| Service worker leaks transcript       | Cache/fetch                   | Static allowlist; no navigation/GraphQL caching        | Cache Storage inspection              |
| Logs leak body/keys/path              | Error/telemetry               | Allowlisted structured fields and redaction            | Captured-log negative assertions      |
| Stale tab overwrites delivery state   | IndexedDB/network             | Server idempotency and connection generation           | Two-tab/reconnect tests               |
| Old release claims unknown job        | Scheduler overlap             | Disabled seed until drain; public activation           | Release overlap tests                 |

## Data Classification and Lifetime

| Data                   | Location                 | Lifetime                                      | Output policy                            |
| ---------------------- | ------------------------ | --------------------------------------------- | ---------------------------------------- |
| Committed message      | SQLite only              | Permanent in v1                               | Authenticated room response/push preview |
| Pending send           | IndexedDB only           | Ack/logout deletion; manual-only after 7 days | Current user's room UI only              |
| Push endpoint/keys     | SQLite                   | Until disable/provider retirement             | Never returned/logged after input        |
| VAPID private key      | Protected machine config | Until separately planned rotation             | Never in repository/evidence             |
| Delivery row           | SQLite                   | 7 active + 7 soft-deleted days if final       | Aggregate operational evidence only      |
| Static shell asset     | Cache Storage            | Until cache version retirement                | Public build content only                |
| GraphQL/socket session | Cookie/server context    | Existing session lifetime                     | Never persisted in browser outbox        |

## Safe Evidence

Allowed telemetry fields are operation, stable safe error code, attempt number, duration bucket, queue counts, and
configured/readiness booleans. Never record body or preview, GraphQL variables, endpoint or hash, browser keys, session
digest, VAPID values, cookie, private origin, user value, provider response body, or absolute runtime path.

Unit proof covers policy, payload, retry, redaction, GraphQL resolver authorization, and logout ordering. Integration
uses real isolated SQLite and loopback HTTP/WebSocket. Backend E2E uses the routed GraphQL origin. Frontend E2E proves
permission UX, service-worker push/click handling, and cache/outbox isolation. OS-owned background display on a physical
device is outside plan completion; delivery ends at provider-boundary and service-worker evidence.
