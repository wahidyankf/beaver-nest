# Planned Specification Changes

This is the file-by-file checklist for future specification work. The canonical as-built files remain unchanged until implementation passes the listed bindings and tests.

## PRD-to-Specification Boundary

The Gherkin in [the PRD](../prd.md#proposed-acceptance-criteria) accepts this plan; it is not a list to copy into `specs/`.

- **Selected canonical contracts:** one-time account setup, login, browser-local persistent sessions, user isolation, multi-role authorization, confirmed browser import, retry-safe import, removal of accepted Bnest client persistence, and centralized chat/learning continuation.
- **Plan-only acceptance outcomes:** AC-05's interrupted-migration recovery, root-level legacy-file copying, and AC-11's test-root safety are operational guarantees, not standalone product-language scenarios. User-visible browser retry remains in `centralized_data.feature`; [delivery](../delivery.md#phase-3--repository-browser-import-and-legacy-copy) proves legacy copying and recovery-source restoration, while the safety-harness tasks prove test isolation and cleanup.

## Gherkin

### `[E] specs/apps/bnest/app/behaviours/chat.feature`

```diff
- Given a visitor opens "/chat" and browser storage restores the same-tab snapshot
+ Given an authenticated user opens "/chat" and Bnest reads that user's centralized chat
+ And Bnest no longer persistently writes chat state in browser storage after accepted import

- Scenario: Reload preserves a completed conversation and Codex session
+ Scenario: Reload preserves a completed user-owned conversation and Codex session

- Then Clear Chat removes the browser snapshot
+ Then Clear Chat changes only that user's normalized chat and preserves the import envelope
```

<details>
<summary>Scenario scope: 11 chat interactions whose setup changes only</summary>

- **All listed scenarios preserve their interaction after authenticated setup.**
  - **A visitor enters chat from the home page**
  - **A visitor opens a fresh chat**
  - **A visitor cannot send an empty message**
  - **A visitor cannot overlap Codex turns**
  - **A visitor sends a message with Shift+Enter**
  - **A visitor continues one page-scoped conversation**
  - **A visitor changes models within one Codex conversation**
  - **A visitor changes reasoning effort within one Codex conversation**
  - **A model change falls back from an unsupported reasoning effort**
  - **The Codex session cannot accept a message**
  - **Codex reports a failed turn**

</details>

- `= Preserve` **A visitor can install Beaver Nest as an app** remains public PWA behavior. The renamed reload scenario and updated Clear Chat scenario are shown in the diff.
- `→ Bindings` `[E] apps/bnest-app/test/behaviour/steps/home_page_steps.exs`, `[E] apps/bnest-app/test/behaviour/driver.ex`, `[E] apps/bnest-app/test/behaviour/support/unit.exs`, `[E] apps/bnest-app/test/behaviour/support/integration.exs`, and `[E] apps/bnest-app-e2e/tests/steps/browser.steps.ts`; use the new shared login/import steps below.
- `✓ Proof` `bnest-app:test:coverage:behaviour`, then the focused chat E2E scenario.

### `[E] specs/apps/bnest/app/behaviours/sifat_allah.feature`

```diff
- Given a visitor opens "/apps/sifat-allah" and reload reads localStorage
+ Given an authenticated child opens "/apps/sifat-allah" and Bnest reads centralized progress
+ And Bnest no longer persistently writes learning/quiz state in browser storage after accepted import

- Then reset clears the browser's saved progress
+ Then reset changes only the authenticated child's normalized progress and preserves the import envelope
```

<details>
<summary>Scenario scope: 26 Sifat Allah scenarios whose setup changes only</summary>

- **All listed scenarios preserve their learning, quiz, review, swipe, reset, and browser-Back outcome after authenticated setup.**
  - **A child opens the revision dashboard**
  - **A child learns a pair and keeps the progress after a reload**
  - **A child keeps saved progress during a live update**
  - **A child resets saved progress from the mission**
  - **A child learns the earliest pair that is not remembered yet**
  - **A quiz prioritizes individual questions that are not remembered yet**
  - **A quiz continues as reinforcement after every pair is remembered**
  - **A child swipes through a learning session**
  - **A child can return to the mission while learning**
  - **Browser Back returns a child from a quiz to the mission**
  - **A child receives kind feedback for a correct quiz answer**
  - **A quiz skips an individual question that is already learned**
  - **A quiz locks one answer and moves on automatically**
  - **A child sees correct answers in varied positions**
  - **A child keeps the current quiz question after a reload**
  - **A child swipes through quiz questions**
  - **A child practises the opposite attribute too**
  - **A child practises the meaning of an opposite attribute too**
  - **A child practises every relationship from the reverse direction too**
  - **A difficult pair is kept for another try**
  - **A child retests a difficult pair until it is correct**
  - **A child retests a pair that is already remembered**
  - **A child moves through remembered individual questions**
  - **Every answered question moves between the review queues immediately**
  - **A pair moves between remembered and difficult review**
  - **A child gets another difficult pair before repeating one**

</details>

- `= Specific changed scenarios` **A child learns a pair and keeps the progress after a reload**, **A child keeps saved progress during a live update**, and **A child keeps the current quiz question after a reload** prove centralized persistence.
- `→ Bindings` `[E] apps/bnest-app/test/behaviour/steps/home_page_steps.exs`, `[E] apps/bnest-app/test/behaviour/driver.ex`, `[E] apps/bnest-app/test/behaviour/support/unit.exs`, `[E] apps/bnest-app/test/behaviour/support/integration.exs`, and `[E] apps/bnest-app-e2e/tests/steps/sifat_allah.steps.ts`.
- `✓ Proof` `bnest-app:test:coverage:behaviour`, then the focused Sifat Allah E2E scenario.

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

- `= Scenario contract` names the actor, browser-session state, protected route or operation, action, and observable allow/deny result. Setup warns that later account management and password reset are unavailable in this plan. Logout ends only that browser session; clearing its cookie also requires that browser to log in again, while another browser session for the same user remains usable.
- `→ Bindings` `[N] apps/bnest-app/test/behaviour/steps/authentication_steps.exs`, `[N] apps/bnest-app/test/unit/bnest_app/identity_test.exs`, `[N] apps/bnest-app/test/integration/bnest_app_web/authentication_test.exs`, and `[N] apps/bnest-app-e2e/tests/steps/authentication.steps.ts`.
- `✓ Proof` behavior coverage, unit/integration targets, and the named E2E scenario.

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

- `= Scenario contract` names source key, confirmation, result, source-preservation expectation, and recovery outcome.
- `→ Bindings` `[N] apps/bnest-app/test/behaviour/steps/centralized_data_steps.exs`, `[N] apps/bnest-app/test/unit/bnest_app/data_repository_test.exs`, `[N] apps/bnest-app/test/integration/bnest_app/centralized_data_test.exs`, and `[N] apps/bnest-app-e2e/tests/steps/centralized_data.steps.ts`.
- `✓ Proof` behavior coverage, unit/integration targets, then the named browser-import E2E scenario.

## C4

### `[E] specs/apps/bnest/app/architecture.md`

```diff
- Family member uses Bnest without authentication or server-side data
+ Approved authenticated user reaches Bnest through login/session and local runtime-data boundaries
+ Component view owns identity, per-browser session, authorization, import, repository, manifest, and recovery-source responsibilities
+ Runtime repository resolves `data/prod/` once at production startup; tests substitute an isolated mirrored root
+ Session boundary uses a token digest as its record ID and leaves a sibling browser session independent
+ Browser boundary clears accepted Bnest persisted values only after server data is re-read; username/password bootstrap stays server-owned
```

- `= Preserve` independent Tailscale and Codex boundaries.
- `→ Implementation binding` the component names and relationships must match the final modules in [File Impact](file-impact.md#application-runtime-and-interface).
- `✓ Proof` compare the rendered as-built diagram with the implemented runtime root, session, import, and repository boundaries after all affected behavior tests pass.
