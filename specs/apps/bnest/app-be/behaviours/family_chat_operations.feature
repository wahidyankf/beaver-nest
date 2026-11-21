Feature: Family chat operations

  Rule: Seed and release compatibility

  # Exemption(e2e): a fresh installation is a first migration, which every browser test instance has already run before its scenario starts, so the browser suite never observes it; alternative-proof: bnest-app:test:integration / A fresh installation lists Ruang Keluarga ready for posting
  @e2e-exempt
  Scenario: A fresh installation lists Ruang Keluarga ready for posting
    Given a fresh installation
    When a member lists the rooms and sends a message
    Then room "Ruang Keluarga" is listed and the message is accepted

  Rule: Internal-only system message posting

  Scenario: The public GraphQL schema exposes no system-message mutation
    When the public GraphQL schema is inspected
    Then it declares no field that posts a system message

  Rule: Atomic message and delivery commit

  # Exemption(e2e): push notifications reach a member's device only through a push provider, which the browser suite does not run; alternative-proof: bnest-app:test:integration / Every other member with push enabled is notified of a new message and the sender is not
  @e2e-exempt
  Scenario: Every other member with push enabled is notified of a new message and the sender is not
    Given three other members hold active Web Push subscriptions in "ruang-keluarga"
    When a member sends a durable family chat message
    Then each of the three other subscriptions is sent one push for the message and the sender's own subscription is sent none

  # Exemption(e2e): push content reaches a member's device only through a push provider, which the browser suite does not run; alternative-proof: bnest-app:test:integration / A reply notifies the other member once and the notification shows none of the quoted message
  @e2e-exempt
  Scenario: A reply notifies the other member once and the notification shows none of the quoted message
    Given one other member holds an active Web Push subscription in "ruang-keluarga"
    When a member sends a durable family chat reply to that member's message
    Then exactly one push is sent to that subscription
    And the notification title and body carry no part of the quoted message

  Rule: Push delivery retry, retirement, retention, and purge

  # Exemption(e2e): the push provider's answers are given only by a double at the integration level, since the browser suite runs no push provider; alternative-proof: bnest-app:test:integration / A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
  @e2e-exempt
  Scenario: A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
    Given a delivery row whose provider request will fail with a retryable result
    When the dispatcher attempts the delivery
    Then the push service is asked again after 30 seconds, then 120, 480 and 1920 seconds, with no sixth attempt and no attempt past one hour

  # Exemption(e2e): the push provider's answers are given only by a double at the integration level, since the browser suite runs no push provider; alternative-proof: bnest-app:test:integration / A device the push service reports gone stops receiving notifications and shows as disabled
  @e2e-exempt
  Scenario: A device the push service reports gone stops receiving notifications and shows as disabled
    Given a delivery row targeting a subscription the provider reports as gone
    When the dispatcher attempts the delivery
    Then the member's current Web Push subscription reports disabled and the push service is not asked again

  Rule: One-time backup schedule convergence

  # Exemption(e2e): the release's converge step runs inside the release tooling, which the browser suite never runs; alternative-proof: bnest-app:test:integration / After an upgrade the administrator sees the daily backup at 18:00 UTC
  @e2e-exempt
  Scenario: After an upgrade the administrator sees the daily backup at 18:00 UTC
    Given the existing "prod-sqlite-backup-daily" schedule uses a different daily time
    When the release's converge step has run
    Then the schedules page lists the daily backup at 18:00 UTC
    And running the converge step again leaves it so

  # Exemption(e2e): the release's converge step runs inside the release tooling, which the browser suite never runs; alternative-proof: bnest-app:test:integration / After an upgrade the push retention schedule is listed as enabled
  @e2e-exempt
  Scenario: After an upgrade the push retention schedule is listed as enabled
    Given a release whose retention schedule was listed disabled
    When the release's converge step has run
    Then the schedules page lists it enabled, and a second run changes nothing

  # Exemption(e2e): a restart of Bnest is a process action that the browser suite does not perform; alternative-proof: bnest-app:test:integration / A backup time the administrator chose survives a restart
  @e2e-exempt
  Scenario: A backup time the administrator chose survives a restart
    Given the administrator saved a different daily backup time on the schedules page
    When Bnest restarts
    Then the schedules page still shows that time

  Rule: Capacity, concurrency, and restore

  # Exemption(e2e): the free-space check runs on the backup folder before any snapshot, and the browser suite cannot make that folder run short of space; alternative-proof: bnest-app:test:integration / A backup is refused and retried later when the backup folder lacks free space
  @e2e-exempt
  Scenario: A backup is refused and retried later when the backup folder lacks free space
    Given the backup destination reports insufficient free bytes for the required reserve
    When the scheduled backup runs
    Then no backup file or partial file appears
    And the run shows a retryable "insufficient_capacity" failure

  # Exemption(e2e): sustained concurrent-write load is a load-scale integration boundary, not a discrete browser or HTTP action; alternative-proof: bnest-app:test:integration / Chat reads and sends stay within budget during a backup
  @e2e-exempt
  Scenario: Chat reads and sends stay within budget during a backup
    Given continuous authenticated family chat read and send probes are running
    When a whole-database backup runs for its entire duration
    Then every probe completes with zero failures, p95 at most 500 ms, and every sample at most two seconds
    And every sent message ID exists in the room history afterward

  # Exemption(e2e): the backup snapshot is checked against the artifact on disk, which only the integration boundary reads; alternative-proof: bnest-app:test:integration / A backup taken while the chat is busy restores as a consistent snapshot
  @e2e-exempt
  Scenario: A backup taken while the chat is busy restores as a consistent snapshot
    Given continuous authenticated family chat read and send probes are running
    When a whole-database backup runs for its entire duration
    Then the backup produces a restorable, self-consistent snapshot

  # Exemption(e2e): forcing a backup timeout is a timing boundary inside the backup service that the browser cannot set; alternative-proof: bnest-app:test:integration / A backup that runs too long is cancelled, leaves no file, and is tried again
  @e2e-exempt
  Scenario: A backup that runs too long is cancelled, leaves no file, and is tried again
    Given the configured backup timeout is far shorter than the snapshot needs
    When a scheduled backup exceeds its timeout
    Then no backup or partial file appears, the run shows a retryable "timeout" failure, and the next attempt runs

  Rule: Restore

  # Exemption(e2e): restoring into an isolated marked root and reading through internal services is not a public HTTP/browser boundary; alternative-proof: bnest-app:test:integration / A restored backup contains all family chat state
  @e2e-exempt
  Scenario: A restored backup contains all family chat state
    Given a verified backup artifact containing family chat rooms, messages, subscriptions, and deliveries
    When the artifact is restored into an isolated marked root
    Then the restored room, ordered messages, push subscription structure, and delivery states are all readable
    And no message body or secret value appears in the restore evidence
