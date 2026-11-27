Feature: Family chat operations

  Rule: Seed and release compatibility

  # Exemption(e2e): a fresh installation is a first migration, which every browser test instance has already run before its scenario starts, so the browser suite never observes it; alternative-proof: bnest-app:test:integration / A fresh installation lists Ruang Keluarga ready for posting
  @e2e-exempt
  Scenario: A fresh installation lists Ruang Keluarga ready for posting
    Given a fresh installation
    When a member lists the rooms and sends a message
    Then room "Ruang Keluarga" is listed and the message is accepted
    And room ID 1 exists with slug "ruang-keluarga", name "Ruang Keluarga", and posting enabled
    And repeating the migration changes nothing about that seeded room

  # Exemption(e2e): pre-upgrade reader compatibility is a same-machine schema-overlap boundary; alternative-proof: bnest-app:test:integration / An old release ignores the additive family chat schema
  @e2e-exempt
  Scenario: An old release ignores the additive family chat schema
    Given the additive family chat migration has applied
    When code built before this migration opens the same database
    Then the prior release's existing behavior is unaffected
    And no prior-release code path touches the new family chat tables

  # Exemption(e2e): pre-upgrade reader compatibility is a same-machine schema-overlap boundary; alternative-proof: bnest-app:test:integration / An old release ignores the additive reply column
  @e2e-exempt
  Scenario: An old release ignores the additive reply column
    Given the additive family chat reply migration has applied
    When code built before that migration opens the same database
    Then it reads and writes every other family chat message column unchanged
    And messages it commits carry no reply target

  Rule: Internal-only system message posting

  # Exemption(e2e): the internal system-message producer is a typed service call with no GraphQL or browser boundary; alternative-proof: bnest-app:test:integration / A trusted producer posts an idempotent system message
  @e2e-exempt
  Scenario: A trusted producer posts an idempotent system message
    Given a trusted internal producer with a stable idempotency key
    When the producer posts a system message to "ruang-keluarga"
    Then the message is committed with sender kind "system" and the producer's stable sender ID
    When the same producer retries with the same idempotency key
    Then the original committed system message is returned unchanged
    And exactly one system message exists for that idempotency key

  Scenario: The public GraphQL schema exposes no system-message mutation
    When the public GraphQL schema is inspected
    Then it declares no field that posts a system message

  Rule: Atomic message and delivery commit

  # Exemption(e2e): push notifications reach a member's device only through a push provider, which the browser suite does not run; alternative-proof: bnest-app:test:integration / Every other member with push enabled is notified of a new message and the sender is not
  @e2e-exempt
  Scenario: Every other member with push enabled is notified of a new message and the sender is not
    Given three other members hold active Web Push subscriptions in "ruang-keluarga"
    When a member sends a durable family chat message
    Then the message and one pending delivery row per other active subscription commit in one transaction
    And each of the three other subscriptions is sent one push for the message and the sender's own subscription is sent none

  # Exemption(e2e): push content reaches a member's device only through a push provider, which the browser suite does not run; alternative-proof: bnest-app:test:integration / A reply notifies the other member once and the notification shows none of the quoted message
  @e2e-exempt
  Scenario: A reply notifies the other member once and the notification shows none of the quoted message
    Given one other member holds an active Web Push subscription in "ruang-keluarga"
    When a member sends a durable family chat reply to that member's message
    Then exactly one pending delivery row exists for that subscription
    And exactly one push is sent to that subscription
    And the notification title and body carry no part of the quoted message

  Rule: Push delivery retry, retirement, retention, and purge

  # Exemption(e2e): the push provider's answers are given only by a double at the integration level, since the browser suite runs no push provider; alternative-proof: bnest-app:test:integration / A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
  @e2e-exempt
  Scenario: A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
    Given a delivery row whose provider request will fail with a retryable result
    When the dispatcher attempts the delivery
    Then the delivery state becomes "retryable"
    And the push service is asked again after 30 seconds, then 120, 480 and 1920 seconds, with no sixth attempt and no attempt past one hour

  # Exemption(e2e): the push provider's answers are given only by a double at the integration level, since the browser suite runs no push provider; alternative-proof: bnest-app:test:integration / A device the push service reports gone stops receiving notifications and shows as disabled
  @e2e-exempt
  Scenario: A device the push service reports gone stops receiving notifications and shows as disabled
    Given a delivery row targeting a subscription the provider reports as gone
    When the dispatcher attempts the delivery
    Then the member's current Web Push subscription reports disabled and the push service is not asked again
    And the delivery state becomes "terminal"

  # Exemption(e2e): retention batching is an internal scheduler-triggered SQLite boundary; alternative-proof: bnest-app:test:integration / Final delivery rows are soft-deleted after seven active days
  @e2e-exempt
  Scenario: Final delivery rows are soft-deleted after seven active days
    Given delivered and terminal delivery rows completed more than seven days ago
    And pending, claimed, and retryable delivery rows of the same age
    When the retention job runs
    Then the completed rows more than seven days old are soft-deleted
    And the pending, claimed, and retryable rows remain active regardless of age

  # Exemption(e2e): purge batching is an internal scheduler-triggered SQLite boundary; alternative-proof: bnest-app:test:integration / Soft-deleted delivery rows are purged after the grace period
  @e2e-exempt
  Scenario: Soft-deleted delivery rows are purged after the grace period
    Given delivery rows soft-deleted more than seven days ago
    When the retention job runs again
    Then those rows are purged from SQLite
    And the run is idempotent when repeated with no newly eligible rows

  # Exemption(e2e): the push payload is built and sent inside the server process, and the e2e server pushes through the recording sender, so the exact origin has no view of the payload; alternative-proof: bnest-app:test:integration / A push notification body is collapsed and capped at 120 characters
  @e2e-exempt
  Scenario: A push notification body is collapsed and capped at 120 characters
    Given one other member holds an active Web Push subscription in "ruang-keluarga"
    When a member sends a family chat message of 300 characters with runs of spaces and line breaks
    And a member sends a family chat message of exactly 120 characters
    Then the push payload of the 300 character message has a body of single spaces, 119 characters and one ellipsis
    And the push payload of the 120 character message has its body unchanged
    And every push payload's title is the sender's display name at commit

  Rule: Independent slot-local PubSub

  # Exemption(e2e): independent-slot process topology is an internal deployment-process boundary, not a single-origin browser/HTTP action; alternative-proof: bnest-app:test:integration / Two independent slots do not exchange family chat PubSub events
  @e2e-exempt
  Scenario: Two independent slots do not exchange family chat PubSub events
    Given two application slots are started independently with no shared distribution
    When a message commits on one slot
    Then only sockets connected to that same slot receive the subscription event
    And the other slot publishes no corresponding event

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
    Given the one-time convergence already ran
    And the administrator saved a different daily backup time on the schedules page
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
    Given continuous authenticated family chat read and send probes are running
    And the configured backup timeout is far shorter than the snapshot needs
    When a scheduled backup exceeds its timeout
    Then no backup or partial file appears, the run shows a retryable "timeout" failure, and the next attempt runs
    And every probe completes with zero failures

  # Exemption(e2e): generated deployment configuration is inspected as a build artifact, not exercised through a browser/HTTP boundary; alternative-proof: bnest-app:test:integration / The generated Caddy configuration rejects a nonzero stream-close delay
  @e2e-exempt @vitest-unit
  Scenario: The generated Caddy configuration rejects a nonzero stream-close delay
    When the deployment tool generates the reverse-proxy configuration for a release
    Then the generated configuration omits "stream_close_delay" and any other nonzero stream-close delay
    And the existing global five-minute grace period remains present

  Rule: Promoted-slot-only handshake routing

  # Exemption(e2e): a live Caddy reload is release-time infrastructure, and the BE E2E project runs with no Caddy; alternative-proof: bnest-app-fe-e2e:test:e2e / A connected client reconnects to the promoted slot without a page refresh
  @e2e-exempt @vitest-unit
  Scenario: A replacement handshake routes only to the promoted slot while the prior slot stays warm
    When the deployment tool generates the reverse-proxy configuration that promotes the replacement slot
    Then every replacement handshake is routed only to the promoted slot
    And no routed handshake reaches the prior slot
