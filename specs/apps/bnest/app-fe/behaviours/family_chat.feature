Feature: Family chat room

  Background:
    Given an approved user is logged in

  Rule: Canonical route

  Scenario: A visitor is redirected from the family chat root to Ruang Keluarga
    When a visitor opens "/family-chat"
    Then the current route is "/family-chat/ruang-keluarga"
    And the page displays the heading "Ruang Keluarga"

  Scenario: A visitor opens Ruang Keluarga directly
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the page displays the heading "Ruang Keluarga"

  Rule: Online send status

  @fe-vitest-unit
  # Exemption(e2e): queue/status-transition logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A member sends a message online and sees it reach Sent
  @e2e-exempt
  Scenario: A member sends a message online and sees it reach Sent
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends the family chat message "On my way"
    Then the message shows status "Sending"
    And the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(e2e): retry/backoff transition logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A network failure shows Retrying then automatic recovery
  @e2e-exempt
  Scenario: A network failure shows Retrying then automatic recovery
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message during a retryable network failure
    Then the message shows status "Retrying in …"
    When the network recovers
    Then the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(e2e): terminal-failure classification logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A non-retryable rejection shows Couldn't send
  @e2e-exempt
  Scenario: A non-retryable rejection shows Couldn't send
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message the server rejects as invalid
    Then the message shows status "Couldn't send"
    And no automatic retry is attempted

  Rule: Bounded per-room outbox

  @fe-vitest-unit
  # Exemption(e2e): the bounded-queue cap is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / The 101st queued message for one room is rejected
  @e2e-exempt
  Scenario: The 101st queued message for one room is rejected
    Given a visitor opens "/family-chat/ruang-keluarga"
    And the visitor's outbox for this room already holds 100 queued messages
    When the visitor attempts to queue one more message
    Then the new message is not queued
    And the composer explains the retry-or-discard remediation

  Rule: Resume, online reaction, backoff, and seven-day expiry

  @fe-vitest-unit
  # Exemption(e2e): resume-on-open queue draining is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Reopening the app resumes queued sends
  @e2e-exempt
  Scenario: Reopening the app resumes queued sends
    Given the visitor has a queued message left over from a closed session
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the queued message resumes toward Sent without visitor action

  @fe-vitest-unit
  # Exemption(e2e): online-event backoff-eligibility logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / An online event makes a retry immediately eligible
  @e2e-exempt
  Scenario: An online event makes a retry immediately eligible
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a queued message is waiting on its backoff timer
    When the browser reports the "online" event
    Then the queued message becomes immediately eligible for retry

  @fe-vitest-unit
  # Exemption(e2e): the exact backoff/jitter timing formula is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Automatic retry waits follow the bounded jittered backoff sequence
  @e2e-exempt
  Scenario: Automatic retry waits follow the bounded jittered backoff sequence
    Given a visitor opens "/family-chat/ruang-keluarga"
    When a queued message fails five times with a retryable result
    Then each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds

  @fe-vitest-unit
  # Exemption(e2e): the seven-day auto-retry cutoff is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A message queued more than seven days becomes manual-only
  @e2e-exempt
  Scenario: A message queued more than seven days becomes manual-only
    Given the visitor has a queued message created more than seven days ago
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the message is not automatically retried
    And the visitor can still manually retry or discard it

  Rule: Auth expiry pause and logout isolation

  @fe-vitest-unit
  # Exemption(e2e): per-namespace pause-on-expiry isolation is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Authentication expiry pauses the queue without cross-user drain
  @e2e-exempt
  Scenario: Authentication expiry pauses the queue without cross-user drain
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a message is queued
    When the visitor's authentication expires
    Then queue draining pauses for that namespace
    And no other user's session drains that queued message

  @fe-vitest-unit
  # Exemption(e2e): logout namespace-clearing and subscription disabling are already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Logout clears the current user's queue
  @e2e-exempt
  Scenario: Logout clears the current user's queue
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a message is queued
    When the visitor logs out
    Then the visitor's local outbox namespace is cleared
    And the current session's Web Push subscription is disabled

  Rule: Reconnect across Caddy promotion

  @fe-vitest-unit
  # Exemption(integration): holding a socket across a live Caddy config reload crosses browser and release-infrastructure boundaries that Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / A connected client reconnects to the promoted slot without a page refresh
  @integration-exempt
  Scenario: A connected client reconnects to the promoted slot without a page refresh
    Given a visitor opens "/family-chat/ruang-keluarga" with the socket connected to the current slot
    When Caddy promotes a replacement slot
    Then the prior-slot socket closes
    And the browser subscribes on the promoted slot and completes catch-up within ten seconds
    And any queued send drains only after catch-up completes
    And the page does not reload

  Rule: Experience release candidate proof

  # This scenario's two near-simultaneous authenticated first requests
  # against a freshly promoted candidate independently reproduced a real
  # production race in `StorageCoordinator.ensure_started!/1`: an unlocked
  # check-and-maybe-restart let one request tear down the Ecto repo pid a
  # concurrent request was already mid-query against. Fixed with
  # `:global.trans/2` serialization (storage_coordinator.ex); see
  # learnings.md for the reproduction evidence.
  @fe-vitest-unit
  # Exemption(integration): promoting Caddy to a flag-transitioned release candidate and driving two independent browser contexts against it crosses browser and release-infrastructure boundaries that Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate
  @integration-exempt
  Scenario: Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate
    Given Caddy has promoted the flag-enabled experience candidate
    And two members each open "/family-chat/ruang-keluarga"
    And one member queues a message while offline
    When the offline member's connection is restored
    Then the offline member's queued message drains exactly once after reconnect
    And neither member sees a duplicate or lost message

  Rule: Scroll anchor and live-region announcements

  @fe-vitest-unit
  # Exemption(integration): measured scroll position and focus retention require a real browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / Loading older history preserves the visitor's scroll anchor
  @integration-exempt
  Scenario: Loading older history preserves the visitor's scroll anchor
    Given a visitor opens "/family-chat/ruang-keluarga" scrolled to a known older message
    When the visitor loads an older history page
    Then the previously visible message remains at the same visual position

  @fe-vitest-unit
  # Exemption(integration): live-region announcement and focus retention require a real browser accessibility tree; alternative-proof: bnest-app-fe-e2e:test:e2e / A new message announces without moving focus from the composer
  @integration-exempt
  Scenario: A new message announces without moving focus from the composer
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When another member's message arrives away from the bottom of the scroll position
    Then a live-region announcement names the new message
    And focus remains in the composer
    And "New messages below" is shown instead of auto-scrolling

  Rule: Push permission UX and no authenticated caching

  @fe-vitest-unit
  # Exemption(e2e): the device-state-to-control-text mapping is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / The room shows the correct push permission state
  @e2e-exempt
  Scenario Outline: The room shows the correct push permission state
    Given the visitor's device reports push state "<device state>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the room shows the control "<control text>"

    Examples:
      | device state                | control text                              |
      | available, not yet decided  | Enable notifications                      |
      | subscription active         | Notifications on                          |
      | permission denied           | Notifications blocked                     |
      | requires installation       | Install Beaver Nest first                 |
      | unsupported                 | Notifications unavailable in this browser |

  @fe-vitest-unit
  # Exemption(e2e): the disable-subscription control-text transition is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A member disables notifications from the room
  @e2e-exempt
  Scenario: A member disables notifications from the room
    Given a visitor opens "/family-chat/ruang-keluarga" with an active push subscription
    When the visitor selects "Turn off"
    Then the room shows the control "Enable notifications"

  @fe-vitest-unit
  # Exemption(integration): inspecting the service worker's Cache Storage contents requires a real browser cache implementation; alternative-proof: bnest-app-fe-e2e:test:e2e / The service worker cache stores no authenticated content
  @integration-exempt
  Scenario: The service worker cache stores no authenticated content
    Given a visitor opens "/family-chat/ruang-keluarga" and exchanges messages
    When the service worker's Cache Storage is inspected
    Then it contains only static build assets
    And it contains no navigation response, message, or GraphQL response

  Rule: Responsive and accessible presentation

  @fe-vitest-unit
  # Exemption(integration): rendered viewport geometry and zoom layout require a real browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / The room remains keyboard operable and free of horizontal scroll
  @integration-exempt
  Scenario Outline: The room remains keyboard operable and free of horizontal scroll
    Given the viewport is set to "<viewport>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then every control is reachable by keyboard with a visible focus indicator
    And no horizontal page scroll is present

    Examples:
      | viewport             |
      | desktop 1280x800     |
      | tablet 768x1024      |
      | mobile 393x852       |
      | desktop 1280x800 200%|
