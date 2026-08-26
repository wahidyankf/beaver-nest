# Specification Change Record

This record selects the durable product contracts implemented by the plan. It does not copy every PRD acceptance criterion into canonical Gherkin. The C4 and feature changes below passed their unit, integration, behavior, and browser bindings; live setup/import remains a delivery gate.

## PRD Boundary

- **Canonical product behavior:** protected access, one-time setup, persistent independent browser sessions, self-owned multi-role access, user isolation, confirmed browser import, retry safety, accepted-key cleanup, centralized continuation, and failed Codex-resume fallback.
- **Delivery-only proof:** root-level private inventory, immutable legacy-copy rehearsal, read-only production schema audit, marked test-root safety, exact cleanup, and live promotion/rollback. These remain in [delivery](../delivery.md), not product-language scenarios.

## Gherkin Changes

### `[E] specs/apps/bnest/app/behaviours/chat.feature`

```diff
+ Rule: Public application installation
    Scenario: A visitor can install Beaver Nest as an app

+ Rule: Authenticated user-owned chat
+   Background:
+     Given an approved user is logged in

- Scenario: Reload preserves a completed conversation and Codex session
+ Scenario: Reload preserves a completed user-owned conversation and Codex session

- Scenario: A visitor clears the chat and starts a new Codex session
+ Scenario: A user clears normalized chat and starts a new Codex session
```

- Existing chat interactions keep their prior observable outcomes under the authenticated background.
- The public PWA scenario remains outside authentication.
- Bindings: `[E] apps/bnest-app/test/behaviour/driver.ex`, `[E] apps/bnest-app/test/behaviour/support/integration.exs`, and `[E] apps/bnest-app-e2e/tests/steps/browser.steps.ts`; shared login/import behavior comes from the new binding files below.

### `[E] specs/apps/bnest/app/behaviours/sifat_allah.feature`

```diff
+ Background:
+   Given an approved child is logged in
```

- All existing dashboard, learning, quiz, review, swipe, reset, reload, live-update, and browser-Back outcomes remain canonical.
- The changed setup makes their durable state user-owned and centralized; the feature does not duplicate storage mechanics.
- Bindings: `[E] apps/bnest-app/test/behaviour/driver.ex`, `[E] apps/bnest-app/test/behaviour/support/integration.exs`, and `[E] apps/bnest-app-e2e/tests/steps/sifat_allah.steps.ts`.

### `[N] specs/apps/bnest/app/behaviours/authentication.feature`

```diff
+ Scenario: Unauthenticated visitor is redirected before protected Bnest access
+ Scenario: Initial setup warns about unavailable account recovery, creates all initial accounts once, and closes registration
+ Scenario: Approved user logs in and logs out
+ Scenario: Login verifies a salted password hash without retaining plaintext
+ Scenario: Login persists across reload and browser restart until logout or browser data clearing
+ Scenario: One user can use independent simultaneous browser sessions
+ Scenario: A multi-role user receives only approved capabilities
+ Scenario: One authenticated user cannot read or write another user's data
```

- Bindings: `[N] apps/bnest-app/test/behaviour/steps/authentication_steps.exs`, `[N] apps/bnest-app/test/integration/bnest_app/identity_test.exs`, `[N] apps/bnest-app/test/integration/bnest_app_web/authentication_test.exs`, `[N] apps/bnest-app/test/unit/bnest_app/identity_policy_test.exs`, `[N] apps/bnest-app/test/unit/bnest_app_web/user_auth_test.exs`, and `[N] apps/bnest-app-e2e/tests/steps/authentication.steps.ts`.

### `[N] specs/apps/bnest/app/behaviours/centralized_data.feature`

```diff
+ Scenario: Authenticated user imports each recognized browser source
+ Scenario: Absent system theme is recorded without creating a preference
+ Scenario: Unknown, malformed, or oversized browser input is rejected without source deletion
+ Scenario: Retrying an interrupted import does not duplicate accepted data
+ Scenario: A stale browser cannot overwrite a newer centralized record
+ Scenario: Accepted browser import clears only Bnest persisted browser keys after server read-back
+ Scenario: Failed Codex-thread resume preserves transcript and starts a reported fresh conversation
```

- Bindings: `[N] apps/bnest-app/test/behaviour/steps/centralized_data_steps.exs`, `[N] apps/bnest-app/test/unit/bnest_app/data_normalizer_test.exs`, `[N] apps/bnest-app/test/integration/bnest_app/browser_import_test.exs`, `[N] apps/bnest-app/test/integration/bnest_app_web/centralized_persistence_test.exs`, `[E] apps/bnest-app/test/integration/bnest_app_web/chat_live_test.exs`, and `[N] apps/bnest-app-e2e/tests/steps/centralized_data.steps.ts`.

## C4 Change

### `[E] specs/apps/bnest/app/architecture.md`

```diff
- Bnest has no authentication or server-side user-data store
+ Approved users authenticate before protected access
+ Production resolves one server-owned data/prod runtime root
+ Tests substitute one marked data/test/runs/<run-id> mirror
+ Identity owns bootstrap, Argon2id login, persistent session digests, and roles
+ Authorization defaults every cross-user capability to deny
+ The typed repository owns schemas, paths, revisions, locks, atomic writes, and read-back
+ Import owns immutable envelopes, manifests, retry, and recovery candidates
+ Browser keys remain compatibility sources only until accepted server read-back
```

The existing independent Tailscale proxy and local Codex boundaries remain unchanged. The component names and relationships match the modules in [File Impact](file-impact.md).

## Proof

- Behavior coverage: 4 features, 55 scenarios, 434 steps, and 118 bindings in each application adapter, with the browser adapter complete.
- Numeric coverage: unit 99.63% and integration 100%, both above the unchanged 99% threshold.
- Browser coverage: all 163 generated desktop, tablet, and mobile cases passed with isolated scenario identities.
- Manual browser proof: setup, login, import, chat, learning, and theme states exposed named semantics; affected Lighthouse accessibility checks reached 100 after contrast correction.
