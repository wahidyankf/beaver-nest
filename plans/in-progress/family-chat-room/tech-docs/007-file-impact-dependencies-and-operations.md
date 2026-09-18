# File Impact, Dependencies, and Operations

## Dependency Decision

### Requirement

Web Push requires RFC 8291 `aes128gcm` payload encryption and RFC 8292 VAPID signing. Implementing those cryptographic
protocols inside Bnest would create disproportionate correctness, interoperability, and security ownership. Existing Req
already owns HTTP transport but does not construct Web Push payloads.

### Selection

Add `{:web_push_ex, "~> 0.2.0"}` to `apps/bnest-app/mix.exs` and lock its resolved version/checksum in
`apps/bnest-app/mix.lock`. It builds standards-shaped requests, uses OTP-native JSON and JOSE for signing, leaves HTTP to
the host, and was current for the supported OTP generation when this plan was authored.

Rejected:

- hand-written ECDH/HKDF/AES-GCM/VAPID: too much security-critical custom code;
- `web_push_encryption` 0.3.1: older and not actively maintained for the current stack;
- libraries centered on legacy `aesgcm`: wrong content-encoding baseline;
- the very new `web_push` 0.1.0: attractive smaller dependency graph but insufficient adoption history for this plan.

Before manifest edit, re-open the package and source, verify checksum, MIT license, OTP 27/Elixir 1.18 compatibility,
RFC vector tests, maintenance/security state, and transitive JOSE footprint. A failed requirement blocks and amends the
plan; the executor does not silently switch packages.

## File Impact

Every label is relative to the repository root: `[N]` new, `[E]` edited. No production deletion or move is planned.

### Application domain and runtime

```text
[N] apps/bnest-app/lib/bnest_app/family_chat.ex
[N] apps/bnest-app/lib/bnest_app/family_chat/message.ex
[N] apps/bnest-app/lib/bnest_app/family_chat/store.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/dispatcher.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/policy.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/sender.ex
[E] apps/bnest-app/lib/bnest_app/application.ex
[E] apps/bnest-app/lib/bnest_app/identity.ex
[E] apps/bnest-app/lib/bnest_app/identity/session.ex
[E] apps/bnest-app/lib/bnest_app/identity/authorization.ex
```

The application adds a dedicated push task supervisor and dispatcher after the repository is available. Identity exposes
the current session digest safely to server code and coordinates per-session subscription retirement on logout. The new
`use_family_chat` shared capability accepts `owner_id = nil` for approved roles and remains separate from self-owned
capabilities.

### SQLite and release migration

```text
[N] apps/bnest-app/priv/sqlite_repo/migrations/20260918000000_add_family_chat.exs
[N] apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex
[N] apps/bnest-app/lib/bnest_app/release/migrations.ex
[E] apps/bnest-app/lib/bnest_app/release/migrations/persistent_schedules.ex
[E] apps/bnest-app/lib/bnest_app_web/controllers/health_controller.ex
[E] apps/bnest-app/tools/deployment.mjs
[E] apps/bnest-app/tools/release.mjs
[E] apps/bnest-app/tools/release.test.mjs
[E] apps/bnest-app/tools/continuity-contract.test.mjs
```

The general migration coordinator runs all DDL once under the existing exclusive lock, reconciles feature seeds, and
verifies schedules plus family chat. Release manifests declare the new migration path and checksum. Health adds only a
boolean readiness field.

### Web and PWA

```text
[N] apps/bnest-app/lib/bnest_app_web/live/family_chat_live.ex
[N] apps/bnest-app/assets/js/family_chat.js
[E] apps/bnest-app/lib/bnest_app_web/endpoint.ex
[E] apps/bnest-app/lib/bnest_app_web/router.ex
[E] apps/bnest-app/lib/bnest_app_web/user_auth.ex
[E] apps/bnest-app/lib/bnest_app_web/controllers/session_controller.ex
[E] apps/bnest-app/lib/bnest_app_web/controllers/page_html/home.html.heex
[E] apps/bnest-app/assets/js/app.js
[E] apps/bnest-app/assets/css/app.css
[E] apps/bnest-app/priv/static/service-worker.js
[E] apps/bnest-app/priv/static/manifest.webmanifest
```

No public REST or GraphQL operation is added. LiveView events own subscription exchange. The manifest receives stable
`id: "/"`; the service worker moves to static-only caching before family content is exposed.

### Configuration and dependencies

```text
[E] apps/bnest-app/config/config.exs
[E] apps/bnest-app/config/runtime.exs
[E] apps/bnest-app/config/test.exs
[E] apps/bnest-app/mix.exs
[E] apps/bnest-app/mix.lock
```

Configuration defines injected sender/clock/tick defaults, validated production VAPID values, and test doubles. No key,
endpoint, or real subject value enters Git.

### Canonical specifications

```text
[E] specs/apps/bnest/app/architecture.md
[N] specs/apps/bnest/app/behaviours/family_chat.feature
[E] specs/apps/bnest/app/behaviours/authentication.feature
[E] specs/apps/bnest/app/behaviours/scheduled_backups.feature
[E] specs/apps/bnest/app/behaviours/README.md
```

The exact deltas and adapter mapping live in
[Specification Delta and Adapter Map](006-specification-delta-and-adapter-map.md).

### Unit and integration tests

```text
[N] apps/bnest-app/test/unit/bnest_app/family_chat_test.exs
[N] apps/bnest-app/test/unit/bnest_app/push_notifications/policy_test.exs
[N] apps/bnest-app/test/unit/bnest_app/push_notifications/sender_test.exs
[N] apps/bnest-app/test/unit/support/family_chat_driver.ex
[N] apps/bnest-app/test/integration/bnest_app/family_chat_test.exs
[N] apps/bnest-app/test/integration/bnest_app/push_notifications_test.exs
[N] apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs
[N] apps/bnest-app/test/integration/bnest_app_web/family_chat_live_test.exs
[E] apps/bnest-app/test/integration/bnest_app/identity_test.exs
[E] apps/bnest-app/test/integration/bnest_app_web/authentication_test.exs
[N] apps/bnest-app/test/integration/support/family_chat_driver.ex
[N] apps/bnest-app/test/behaviour/steps/family_chat_steps.exs
[E] apps/bnest-app/test/behaviour/driver.ex
[E] apps/bnest-app/test/behaviour/support/unit.exs
[E] apps/bnest-app/test/behaviour/support/integration.exs
[E] apps/bnest-app/test/support/test_identity.ex
[E] apps/bnest-app/test/support/test_runtime_root.ex
[E] apps/bnest-app/test/unit/bnest_app/identity_policy_test.exs
```

Integration tests use isolated marked SQLite roots and a loopback push stub. Unit tests touch no filesystem, database,
process, or network. Coverage exclusions are not widened merely to accommodate new domain code.

### Browser tests

```text
[N] apps/bnest-app-e2e/tests/steps/family-chat.steps.ts
[N] apps/bnest-app-e2e/tests/support/family-chat.ts
[E] apps/bnest-app-e2e/tests/support/authentication.ts
[E] apps/bnest-app-e2e/tests/support/test-runtime.mts
[E] apps/bnest-app-e2e/playwright.config.mts
```

Browser fixtures use independent `test-user-` accounts and contexts. The focused family-chat scenarios run at the exact
leased origin on desktop, tablet, and mobile except a narrowly documented physical-OS boundary exemption.

### Documentation and plans

```text
[E] README.md
[E] apps/bnest-app/README.md
[E] apps/bnest-app-e2e/README.md
[E] specs/apps/bnest/app/README.md
[E] plans/in-progress/family-chat-room/README.md
[E] plans/in-progress/family-chat-room/delivery.md
[E] plans/in-progress/family-chat-room/learnings.md
[E] plans/in-progress/README.md
```

Final as-built paths may add a narrowly necessary test helper discovered during RED. Any such addition is recorded in
`learnings.md` before creation and reconciled into this inventory; it is not hidden under a directory glob.

## Configuration and Secret Handling

Machine-local inputs:

| Variable                                 | Meaning                                 | Secret                        |
| ---------------------------------------- | --------------------------------------- | ----------------------------- |
| `BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE`  | mode-restricted file read by deployment | No, but private configuration |
| `BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE` | VAPID private key file                  | Yes                           |
| `BNEST_WEB_PUSH_SUBJECT`                 | validated `mailto:` or `https:` contact | Private configuration         |

Runtime-only values passed into slots are `BNEST_WEB_PUSH_PUBLIC_KEY`, `BNEST_WEB_PUSH_PRIVATE_KEY`, and
`BNEST_WEB_PUSH_SUBJECT`. Release evidence records only `configured: true`, never value, path, length, or digest.

Development without configuration renders push unavailable. Production candidate preparation and readiness fail closed.
Tests use deterministic synthetic keys and a local sender boundary. `.env.prod` and other real environment files are
never read or edited by delivery.

## Active-Service Rollout

1. Record active slot/revision, Caddy status, storage generation, 12 exact-origin samples, and the representative logged-in
   journey before mutation.
2. Install machine-local VAPID files and subject without changing the active slot; validate modes and shape without
   printing values.
3. Build the clean authorized revision through the managed release path. The migration manifest includes the additive
   family-chat migration.
4. Run migration proof under the transactional release boundary while the prior application remains compatible.
5. Prepare the inactive candidate and require direct liveness/readiness, exact revision, schema/seed, dispatcher, and
   connected LiveView proof.
6. Promote through Caddy. Prove local Caddy and routed Tailscale revision, login, existing Codex/learning journeys,
   family-chat two-user send, LiveView/WebSocket reconnect, and push readiness without exposing values.
7. Maintain zero routed failures, p95 at or below 500 ms, and every sample at or below 2 seconds from preflight through
   the five-minute drain.
8. Retire the drained incompatible slot and remove temporary worktrees, servers, watchers, loopback push stubs, and test
   roots. Retain only the active route and intended previous artifact capacity.

## Recovery and Rollback

- **Before migration:** any health or capacity failure stops delivery; restore the healthy route and diagnose.
- **Migration failure:** keep the prior route, preserve SQLite and migration evidence, release locks, and retry only after
  root-cause correction. Do not drop or edit partially created production tables manually.
- **Candidate failure:** never promote. Retire the candidate after safe evidence capture.
- **Post-promotion route/reconnect failure:** use managed Caddy rollback to the compatible prior release, prove routed
  health/revision, and retire the failed slot.
- **Push-only provider failure:** do not roll back a healthy chat release solely because an external provider is
  temporarily unavailable; bounded outbox retry owns it. Roll back if configuration, dispatcher, secret exposure, or
  application responsiveness is defective.
- **Schema rollback:** application rollback is allowed; destructive down migration is forbidden once feature data exists.

## Operational Verification

- No REST/GraphQL operation changes, so manual product-API `curl` is not applicable. Health endpoints remain HTTP and are
  manually curled for status, schema readiness, and intended revision without private values.
- Physical phone proof uses a synthetic account and synthetic message, enables one installed PWA, backgrounds/closes it,
  receives sender-plus-preview, activates the notification, and confirms `/family-chat` at the exact routed origin.
- Inspect Cache Storage after chat and logout; only explicit static assets may remain.
- Inspect sanitized logs and release evidence for message, endpoint, key, cookie, user, origin, and path leakage.
- Verify the next independent SQLite backup and isolated restore contains schema and synthetic structural state, then clean
  only marked test data.
