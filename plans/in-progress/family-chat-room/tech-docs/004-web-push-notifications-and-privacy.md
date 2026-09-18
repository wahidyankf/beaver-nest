# Web Push Notifications and Privacy

## Feasibility and Platform Boundary

Standards-based Web Push uses the Push API, Notifications API, and a service worker. A subscription supplies a unique
capability endpoint plus `p256dh` and `auth` key material. The server sends an encrypted payload to the browser-selected
push service, which wakes the service worker when permitted.

iOS and iPadOS support Web Push for apps added to the Home Screen from version 16.4. Permission must follow direct user
interaction, and an Apple Developer membership is not required. The implementation uses feature detection rather than
browser-name checks. Sources:

- [Web Push for Web Apps on iOS and iPadOS](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
- [W3C Push API](https://www.w3.org/TR/push-api/)
- [Web Push protocol encryption, RFC 8291](https://www.rfc-editor.org/rfc/rfc8291)
- [VAPID, RFC 8292](https://www.rfc-editor.org/rfc/rfc8292)

Tailscale HTTPS provides the secure origin for Bnest, but the host also needs outbound HTTPS to endpoints selected by
Safari, Chrome, Firefox, or another supporting browser. Provider metadata leaves the home network; the message title and
preview are encrypted for the subscription.

## Permission and Subscription UX

Page load never calls `Notification.requestPermission()` or `pushManager.subscribe()`. The selected UI shows a device
status control:

- **Enable notifications** when service worker, PushManager, and Notifications API are available and permission is not
  denied.
- **Notifications on** with a **Turn off** action when the current endpoint is bound to the current session.
- **Notifications blocked** with browser/OS settings guidance after denial; no repeated prompt.
- **Install Beaver Nest first** for iOS/iPadOS when the page is not running as a Home Screen web app.
- **Notifications unavailable in this browser** when feature detection fails.

The browser sends `subscription.toJSON()` only through the authenticated LiveView. The server validates an HTTPS
endpoint, URL-safe base64 keys within bounded lengths, nullable expiration, and exact accepted keys. It derives user ID,
session digest, endpoint SHA-256, and audit actors itself.

### Endpoint egress policy

A PushSubscription endpoint is untrusted request input and could otherwise become server-side request forgery. Before
storage, policy parses the URL and requires all of the following:

- scheme `https`, no user information, no fragment, no IP literal, and no explicit port other than `443`;
- a lower-case ASCII hostname matching exactly `fcm.googleapis.com`, exactly
  `updates.push.services.mozilla.com`, or a proper subdomain of `push.apple.com` such as `web.push.apple.com`;
- a total URL length at most 2,048 bytes and decoded `p256dh`/`auth` values of exactly 65/16 bytes; and
- no unknown subscription JSON keys outside `endpoint`, `expirationTime`, and `keys.p256dh`/`keys.auth`.

The sender repeats the URL policy immediately before egress, issues one HTTPS `POST`, disables Req redirects, and treats
every `3xx` as terminal `provider_redirect`; it never follows a provider-supplied location. Rejection stores nothing and
makes no network request. Phase 0 revalidates the three code-owned provider patterns against current Apple, Mozilla, and
Chromium primary documentation. Adding another provider requires a reviewed code/spec/test change, never a browser-
supplied hostname or unrestricted environment override.

The same browser PushSubscription may be rebound after logout/login. Logout computes the current opaque-session digest,
soft-deactivates only rows carrying that digest, and only then revokes identity and clears cookies. If subscription
storage fails, the response keeps the browser authenticated and asks the user to retry instead of claiming a partial
logout. Other browser sessions and devices remain enabled.

## Payload Contract

```json
{
  "type": "family-chat-message",
  "messageId": 123,
  "title": "Aisha",
  "body": "Dinner is ready. Please come downstairs…",
  "tag": "family-chat-message-123",
  "url": "/family-chat"
}
```

- `title` is the immutable author display snapshot.
- `body` collapses all whitespace runs to one space and truncates to at most 120 graphemes, adding one ellipsis only when
  truncated.
- The payload contains no user ID, channel database ID, endpoint, session digest, auth key, private origin, or VAPID
  value.
- `tag` is deterministic so an ambiguous retry replaces the same visible notification where the platform supports tags.
- TTL is the remaining number of seconds before the one-hour absolute delivery deadline; it never extends on retry.
- Urgency is `normal`. No collapse topic combines different messages.

## Transactional Fan-Out

The message transaction selects active, unexpired subscriptions where `user_id != author_user_id`. Each target receives
one `family_chat_push_deliveries` row protected by the unique message/subscription pair. Subscriptions created after the
message commit do not receive historical notifications. Soft-deleted or expired subscriptions are not targeted.

The sender's other devices are excluded because exclusion is by authenticated user ID, not current session or endpoint.
This prevents self-notification while allowing every enabled recipient device.

## Leased Dispatcher

`BnestApp.PushNotifications.Dispatcher` ticks every five seconds and also reconciles immediately on startup. It claims at
most the configured small batch, default 10, and starts each send under `BnestApp.PushNotifications.Tasks`. Claim and
transition SQL is described in the data contract.

The lease is two minutes. A healthy task completes well before expiry; a killed task or slot becomes eligible only after
expiry. A stale task cannot update a row whose attempt number or state has changed. This provides at-least-once provider
requests with deterministic on-device tags, not an impossible exactly-once network claim.

## Retry Matrix

| Outcome                   | Transition                       | Next action                                       |
| ------------------------- | -------------------------------- | ------------------------------------------------- |
| Provider `2xx`            | `delivered`                      | Set accepted time; no retry                       |
| Provider `404/410`        | `terminal` / `gone`              | Soft-deactivate subscription; no retry            |
| Provider `3xx`            | `terminal` / `provider_redirect` | Never follow the redirect                         |
| Other provider `4xx`      | `terminal` / `provider_4xx`      | No retry; never store response body               |
| Provider `429`            | `retryable` / `rate_limited`     | Use fixed plan wait, not unbounded provider input |
| Provider `5xx`            | `retryable` / `provider_5xx`     | Use fixed plan wait                               |
| Timeout/DNS/TLS/transport | `retryable` / `network`          | Use fixed plan wait                               |
| Attempt or age ceiling    | `terminal` / ceiling category    | No retry                                          |

The five attempts are fixed:

1. immediately after commit;
2. 30 seconds after the first retryable failure;
3. 2 minutes after the second;
4. 8 minutes after the third; and
5. 32 minutes after the fourth.

No sixth attempt occurs. Before each claim, the dispatcher also checks `created_at + 1 hour`; an overdue row becomes
terminal without network access. Retry scheduling uses the server clock injected for tests.

## Sender and Dependency Boundary

`web_push_ex` 0.2.x is selected for RFC 8291 `aes128gcm` request construction and VAPID signing. It is preferable to
hand-written cryptography and to older libraries centered on the obsolete `aesgcm` encoding. The host uses the existing
Req dependency for HTTP and owns timeouts, redaction, response classification, and supervision.

Before changing `mix.exs`, delivery rechecks the Hex checksum, MIT license, release activity, OTP 27/Elixir 1.18
compatibility, RFC test coverage, and open security issues. A materially failed check blocks implementation and returns
the plan for amendment; it does not authorize a substitute dependency by improvisation.

## VAPID Configuration

- Generate one P-256 keypair once through the selected library's supported task or verified equivalent.
- Store public and private values in separate mode-`0600` files outside Git, runtime data, Dropbox evidence, and plan
  artifacts.
- Configure `BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE`, `BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE`, and
  `BNEST_WEB_PUSH_SUBJECT` in the machine-local release environment.
- `deployment.mjs` reads, validates, and passes runtime values to both slots without printing them.
- Production startup/readiness requires valid values. Test uses deterministic fake values and a sender double; local dev
  without values renders notifications unavailable.
- Rotation is out of scope because changing the application server key invalidates existing subscriptions and needs a
  user-visible re-subscription plan.

## Service Worker Contract

Move from broad runtime caching to an explicit static allowlist. The new cache version contains only compiled CSS/JS,
manifest, and owned icons. It excludes `/`, `/login`, `/family-chat`, every navigation response, LiveView traffic, health,
and any request/response containing account or chat state.

On `push`, parse only the exact bounded payload contract and call `showNotification`. Invalid or absent data shows a
generic **New family message** notification pointing to `/family-chat`; it never displays attacker-controlled HTML. On
`notificationclick`, close the notification, focus/navigate an existing same-origin client when possible, otherwise
open `/family-chat`.

On activate, delete only superseded Beaver Nest cache names. No service-worker log includes payload data. A controlled
test proves authenticated routes are absent from Cache Storage after chat, logout, and offline navigation attempts.

## Observability and Health

Allowlisted telemetry/log fields are operation (`subscribe`, `claim`, `send`), generic outcome, attempt, duration bucket,
and queue state counts. Never record message or preview, endpoint or hash, browser keys, session digest, VAPID values,
provider response body, private origin, or full user agent.

Readiness proves configuration shape, dispatcher process, task supervisor, and exact SQLite objects. It does not call a
real push provider. Health output adds only a boolean `webPushReady`; any value-level diagnosis stays local and private.

## Verification Boundary

Unit tests cover payload shaping, response classification, retry times, ceilings, and redaction. Integration uses a
loopback HTTP push stub and real isolated SQLite to prove encrypted request construction, state transitions, restart,
lease recovery, and two-dispatcher contention. Browser E2E proves notification UI and subscription lifecycle with the
browser APIs available in its boundary.

OS background delivery and notification activation require a physical installed PWA and receive a scenario-level E2E
exemption with integration alternative proof plus a mandatory manual iOS or Android exact-origin pass. No production
family account or message is used.
