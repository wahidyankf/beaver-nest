# Specification Delta and Adapter Map

## Contract Selection

The authenticated room, durable text, idempotency, ordered pagination, realtime delivery, channel seed, subscription
lifecycle, outbox retry, logout/cache privacy, accessibility, and continuity outcomes become durable canonical behavior.

Plan-only outcomes:

- The exact visual choice among three plan alternatives remains design evidence; canonical behavior records observable
  layout/accessibility, not the planning comparison. Delivery Phase 5 proves the selected assets manually.
- Hex package-selection evidence remains in this plan and dependency manifest; it is not product behavior. Delivery
  Phase 0 verifies it before manifest change.
- The physical phone make/model and OS version are execution evidence, not a permanent scenario value. The durable
  scenario specifies a supported installed PWA; Delivery Phase 8 records the safe test matrix.

## `[N] specs/apps/bnest/app/behaviours/family_chat.feature`

```diff
+ Feature: Beaver Nest family chat
+
+ Rule: Authenticated shared room
+ Scenario: Each approved family role enters the main channel
+ Scenario: Logged-out access reveals no family message
+
+ Rule: Durable plain-text conversation
+ Scenario: Two family members exchange one committed message
+ Scenario: A retried client identity creates one message
+ Scenario Outline: Invalid message text is rejected
+ Scenario: Markup-like text remains literal text
+ Scenario: Committed history survives a fresh process
+
+ Rule: Bounded chronological history
+ Scenario: Opening a long room loads the latest 50 messages
+ Scenario: Upward history loading prepends the previous 50
+ Scenario: The beginning of history produces no duplicates
+ Scenario: A live message does not move an older reading position
+
+ Rule: One channel with a future-safe identity
+ Scenario: A fresh migration seeds exactly one main channel
+ Scenario: Prior application behavior survives the additive schema
+
+ Rule: Voluntary device notifications
+ Scenario: An explicit action enables one supported device
+ Scenario: Disabling one device preserves another device
+ Scenario Outline: An unsafe push endpoint is rejected without egress
+ Scenario Outline: Unsupported or blocked notification states keep chat usable
+ Scenario: Another member's message produces a bounded sender preview
+ Scenario: A sender's devices receive no delivery job
+ Scenario: Notification activation opens family chat
+
+ Rule: Bounded notification recovery
+ Scenario: Retryable delivery stops after five fixed attempts
+ Scenario: A dead subscription is retired without retry
+ Scenario: A push-provider redirect is not followed
+ Scenario: An expired claim is recovered without exceeding the ceiling
+
+ Rule: Session and browser privacy
+ Scenario: Logout disables only the current session's subscription
+ Scenario: Subscription-store failure does not claim logout succeeded
+ Scenario: The service worker never caches authenticated chat
+ Scenario: Push diagnostics contain no secret or message values
+
+ Rule: Accessible responsive operation
+ Scenario Outline: Family chat is operable at each supported viewport
+ Scenario: Dynamic updates are announced without moving focus
+
+ Rule: Active-service continuity
+ Scenario: Compatible promotion preserves a family draft and committed messages
```

- **Users/preconditions/actions/outcomes:** the scenario names map one-for-one to PRD AC-FC-01 through AC-FC-10. The
  feature uses concrete `test-user-` accounts, authenticated/anonymous state, isolated message counts, one send/load/
  enable/disable/logout/promotion action, and observable rendered, repository, notification, or continuity evidence.
- **Exemptions:** the OS-level background push-arrival and notification-click scenario receives
  `@e2e-exempt` only if Playwright cannot address the installed-PWA/OS notification boundary. The immediately preceding
  exemption comment names `bnest-app:test:integration / Another member's message produces a bounded sender preview` plus
  Delivery Phase 8 physical-device proof. Unit remains mandatory. No other blanket exemption is allowed.
- **Bindings:**
  - `[N] apps/bnest-app/test/behaviour/steps/family_chat_steps.exs`
  - `[E] apps/bnest-app/test/behaviour/driver.ex`
  - `[E] apps/bnest-app/test/behaviour/support/unit.exs`
  - `[E] apps/bnest-app/test/behaviour/support/integration.exs`
  - `[N] apps/bnest-app/test/unit/support/family_chat_driver.ex`
  - `[N] apps/bnest-app/test/integration/support/family_chat_driver.ex`
  - `[N] apps/bnest-app-e2e/tests/steps/family-chat.steps.ts`
  - `[N] apps/bnest-app-e2e/tests/support/family-chat.ts`
- **Proof:** `bnest-app:test:coverage:behaviour`, `bnest-app:test:unit`, `bnest-app:test:integration`,
  `bnest-app-e2e:test:coverage:behaviour`, focused `bnest-app-e2e:test:e2e`, and the manual Gherkin implementation review.

## `[E] specs/apps/bnest/app/behaviours/authentication.feature`

```diff
  = Preserve one-time setup, login, independent browser sessions, logout, roles, and cross-user data isolation.
+ Scenario: Logging out deactivates only that browser session's push subscription
```

- Add one logout consequence because subscription ownership is session-scoped; do not merge it into the broader family
  chat feature in a way that hides the identity lifecycle.
- Bind through existing authentication steps plus the new family-chat support operation for subscription inspection.
- Proof uses all three adapters; E2E uses two independent browser contexts and asserts the other session remains enabled.

## `[E] specs/apps/bnest/app/behaviours/scheduled_backups.feature`

```diff
  = Preserve schedule, backup, restore, retention, and settings behavior.
+ Scenario: A verified backup restores family chat and notification delivery state
```

- The restored data assertion uses synthetic message/subscription/delivery structure without sending a real push or
  recording secret values.
- Bind through existing backup steps and new family-chat fixture/read operations.
- Proof uses unit policy where applicable, integration backup/restore, and the existing browser backup journey only where
  its public boundary can express the state.

## `[E] specs/apps/bnest/app/architecture.md`

```diff
- Browser / installed PWA provides current authenticated experiences and generic shell caching.
+ Browser / installed PWA adds family-chat hooks, static-only shell caching, Push subscription, and notification handling.

- Phoenix owns identity, user-owned records, schedules, backups, Codex chat, and Sifat Allah.
+ Phoenix also owns a Family Chat component, relational message store, and leased Web Push dispatcher.

- Local SQLite stores records, schedules, claims, and safe results.
+ Local SQLite also stores channels, immutable messages, session-bound subscriptions, and delivery outbox state.

+ Browser push services are an external encrypted transport; they are never authoritative storage.
+ Family-chat messages commit before PubSub broadcast and outbox delivery.
+ Additive tables remain compatible across blue/green overlap.
```

- Update the System Context with browser push service relationship.
- Update the Container View with service-worker push and new SQLite record classes.
- Add Family Chat and Push Notification components and their relationships in the Component View.
- Add constraints for message ordering/idempotency, immutable permanent history, static-only cache, session-scoped
  subscriptions, retry ceiling, secret redaction, and one-channel v1.
- Preserve all Codex, learning, identity, schedule, backup, storage, and release constraints.
- Proof: Mermaid validation, architecture review, and synchronized final as-built update during the relevant delivery
  phase rather than deferred documentation cleanup.

## `[E] specs/apps/bnest/app/behaviours/README.md`

```diff
+ Family chat specifies the authenticated shared room, durable text, pagination, Web Push, privacy, and continuity.
```

Preserve the recursive-corpus and adapter requirements. Add the entry in alphabetically sensible product order without
renaming existing feature files.

## Adapter Boundaries

| Concern                              | Unit                            | Integration                   | Browser E2E                      | Manual                             |
| ------------------------------------ | ------------------------------- | ----------------------------- | -------------------------------- | ---------------------------------- |
| Text validation/payload/retry policy | Pure domain and clock doubles   | Real boundary also exercises  | UI outcomes                      | Not needed                         |
| SQLite transaction/pagination/lease  | Repository double contract only | Real isolated SQLite required | Normal LiveView journey          | Read-only structure check          |
| Realtime two-user broadcast          | Domain event semantics          | Two LiveViews and real PubSub | Two browser contexts             | Exact-origin exploratory pass      |
| Scroll anchor/responsive UI          | Hook state helpers              | Not layout-capable            | Chromium desktop/tablet/mobile   | Three viewport classes, 200% zoom  |
| Subscription lifecycle               | Pure validation/state policy    | Real SQLite plus sender stub  | Browser feature-detection/toggle | Supported phone permission         |
| Encrypted provider request           | RFC-shaped unit fixture         | Loopback push stub            | Boundary mismatch allowed        | Physical installed-PWA arrival     |
| Service-worker cache privacy         | Static allowlist unit check     | Static endpoint checks        | Cache Storage inspection         | Logout/offline spot check          |
| Release reconnect                    | State/retry policy              | Release harness fixtures      | Existing routed recovery adapter | Exact routed origin during cutover |

## Manual Gherkin Review

After every new/changed feature and adapter is green, run the repository's one-by-one semantic review. For each scenario,
confirm Given establishes only its stated state, When crosses the intended production boundary, Then inspects independent
evidence, and no driver uses expected-result lookups, success literals, no-ops, or manufactured asserted values. Record
scenario names and pass/fail in `delivery.md`; static coverage alone is insufficient.
