Feature: Family chat operations

  Rule: Seed and release compatibility

  # Exemption(e2e): fresh-database migration state is an internal same-machine boundary; alternative-proof: bnest-app:test:integration / A fresh migration seeds Ruang Keluarga ready for posting
  @e2e-exempt
  Scenario: A fresh migration seeds Ruang Keluarga ready for posting
    Given a freshly migrated database with no prior family chat data
    When the family chat migration runs
    Then room ID 1 exists with slug "ruang-keluarga", name "Ruang Keluarga", and posting enabled
    And repeating the migration changes nothing about that seeded room

  # Exemption(e2e): pre-upgrade reader compatibility is a same-machine schema-overlap boundary; alternative-proof: bnest-app:test:integration / An old release ignores the additive family chat schema
  @e2e-exempt
  Scenario: An old release ignores the additive family chat schema
    Given the additive family chat migration has applied
    When code built before this migration opens the same database
    Then the prior release's existing behavior is unaffected
    And no prior-release code path touches the new family chat tables

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

  # Exemption(e2e): the public GraphQL schema is inspected as a typed contract, not through a browser or HTTP client; alternative-proof: bnest-app:test:unit / The public GraphQL schema exposes no system-message mutation
  @e2e-exempt
  Scenario: The public GraphQL schema exposes no system-message mutation
    When the public GraphQL schema is inspected
    Then it declares no field that posts a system message

  Rule: Atomic message and delivery commit

  # Exemption(e2e): one-transaction commit of a message and its delivery rows is an internal SQLite boundary; alternative-proof: bnest-app:test:integration / Sending a message commits the message and every delivery row atomically
  @e2e-exempt
  Scenario: Sending a message commits the message and every delivery row atomically
    Given three other members hold active Web Push subscriptions in "ruang-keluarga"
    When a member sends a durable family chat message
    Then the message and one pending delivery row per other active subscription commit in one transaction
    And the sender receives no delivery row for their own message

  Rule: Push delivery retry, retirement, retention, and purge

  # Exemption(e2e): delivery lease claiming and retry scheduling are internal scheduler/service boundaries; alternative-proof: bnest-app:test:integration / A retryable delivery failure is retried on the fixed backoff schedule
  @e2e-exempt
  Scenario: A retryable delivery failure is retried on the fixed backoff schedule
    Given a delivery row whose provider request will fail with a retryable result
    When the dispatcher attempts the delivery
    Then the delivery state becomes "retryable" with the next fixed push wait
    And a sixth attempt or an attempt past the one-hour ceiling does not occur

  # Exemption(e2e): terminal delivery classification is an internal service boundary; alternative-proof: bnest-app:test:integration / A terminal provider failure retires the delivery without retry
  @e2e-exempt
  Scenario: A terminal provider failure retires the delivery without retry
    Given a delivery row targeting a subscription the provider reports as gone
    When the dispatcher attempts the delivery
    Then the delivery state becomes "terminal" and the subscription is disabled
    And no further delivery attempt is scheduled

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

  Rule: Scheduler routes only through registered handlers and public services

  # Exemption(e2e): scheduler claim dispatch is an internal same-machine coordination boundary; alternative-proof: bnest-app:test:integration / The Scheduler claims backup work only through the registered Backup.Run handler
  @e2e-exempt
  Scenario: The Scheduler claims backup work only through the registered Backup.Run handler
    Given the "prod-sqlite-backup-daily" schedule is due
    When the Scheduler claims and dispatches it
    Then only the registered "Backup.Run" handler is invoked
    And the handler delegates to the public "BnestApp.Backup" service without direct SQL

  # Exemption(e2e): scheduler claim dispatch is an internal same-machine coordination boundary; alternative-proof: bnest-app:test:integration / The Scheduler claims push retention work only through the registered handler
  @e2e-exempt
  Scenario: The Scheduler claims push retention work only through the registered handler
    Given the "family-chat-push-retention-daily" schedule is due and enabled
    When the Scheduler claims and dispatches it
    Then only the registered retention handler is invoked
    And the handler delegates to the public "BnestApp.PushNotifications" service without direct SQL

  Rule: One-time backup schedule convergence

  # Exemption(e2e): release-time schedule convergence is an internal Scheduler service call with no public boundary; alternative-proof: bnest-app:test:integration / Compatible activation converges the backup schedule to 18:00 UTC once
  @e2e-exempt
  Scenario: Compatible activation converges the backup schedule to 18:00 UTC once
    Given the existing "prod-sqlite-backup-daily" schedule uses a different daily time
    When the compatibility release calls the public Scheduler convergence operation
    Then "prod-sqlite-backup-daily" is updated to "daily_at_utc" "18:00"
    And repeating the convergence call afterward changes nothing

  # Exemption(e2e): release-time schedule activation is an internal Scheduler service call with no public boundary; alternative-proof: bnest-app:test:integration / Compatible activation enables push retention once after old-slot drain
  @e2e-exempt
  Scenario: Compatible activation enables push retention once after old-slot drain
    Given the "family-chat-push-retention-daily" schedule ships as a disabled seed
    When the compatibility release calls the public Scheduler activation operation
    Then "family-chat-push-retention-daily" becomes enabled
    And repeating the activation call afterward changes nothing

  # Exemption(e2e): operator schedule edits are an internal Scheduler service call with no public boundary; alternative-proof: bnest-app:test:integration / A later operator-edited backup time is not overwritten
  @e2e-exempt
  Scenario: A later operator-edited backup time is not overwritten
    Given the one-time convergence already ran
    And an operator later changed "prod-sqlite-backup-daily" to a different daily time
    When Bnest starts again
    Then the operator's chosen time remains unchanged

  Rule: Capacity, concurrency, and restore

  # Exemption(e2e): capacity preflight measurement is an internal filesystem/service boundary; alternative-proof: bnest-app:test:integration / A low-capacity destination refuses the backup before VACUUM INTO
  @e2e-exempt
  Scenario: A low-capacity destination refuses the backup before VACUUM INTO
    Given the backup destination reports insufficient free bytes for the required reserve
    When the backup handler runs
    Then the service returns a retryable "insufficient_capacity" failure
    And no partial or final backup artifact is created

  # Exemption(e2e): sustained concurrent-write load and routed timing proof are load-scale integration boundaries, not discrete browser or HTTP actions; alternative-proof: bnest-app:test:integration / Routed reads and writes continue within budget during a full backup
  @e2e-exempt
  Scenario: Routed reads and writes continue within budget during a full backup
    Given continuous authenticated family chat read and send probes are running
    When a whole-database backup runs for its entire duration
    Then every probe completes with zero failures, p95 at most 500 ms, and every sample at most two seconds
    And every sent message ID exists in the live database afterward
    And the backup produces a restorable, self-consistent snapshot

  # Exemption(e2e): forcing a deterministic backup timeout and inspecting Scheduler retry state is an internal service/timing boundary, not a discrete browser or HTTP action; alternative-proof: bnest-app:test:integration / A backup that exceeds its timeout cancels cleanly and stays retryable
  @e2e-exempt
  Scenario: A backup that exceeds its timeout cancels cleanly and stays retryable
    Given continuous authenticated family chat read and send probes are running
    And the configured backup timeout is far shorter than the snapshot needs
    When the timed-out backup handler runs directly
    Then the service returns a retryable "timeout" failure
    And no partial or final backup artifact is created
    And every probe completes with zero failures
    When the same timed-out backup is claimed and run through the Scheduler
    Then the schedule remains claimable for another attempt

  # Exemption(e2e): restoring into an isolated marked root and reading through internal services is not a public HTTP/browser boundary; alternative-proof: bnest-app:test:integration / A restored backup contains all family chat state
  @e2e-exempt
  Scenario: A restored backup contains all family chat state
    Given a verified backup artifact containing family chat rooms, messages, subscriptions, and deliveries
    When the artifact is restored into an isolated marked root
    Then the restored room, ordered messages, push subscription structure, and delivery states are all readable
    And no message body or secret value appears in the restore evidence

  Rule: Independent slot-local PubSub and Caddy stream policy

  # Exemption(e2e): independent-slot process topology is an internal deployment-process boundary, not a single-origin browser/HTTP action; alternative-proof: bnest-app:test:integration / Two independent slots do not exchange family chat PubSub events
  @e2e-exempt
  Scenario: Two independent slots do not exchange family chat PubSub events
    Given two application slots are started independently with no shared distribution
    When a message commits on one slot
    Then only sockets connected to that same slot receive the subscription event
    And the other slot publishes no corresponding event

  # Exemption(e2e): generated deployment configuration is inspected as a build artifact, not exercised through a browser/HTTP boundary; alternative-proof: bnest-app:test:integration / The generated Caddy configuration rejects a nonzero stream-close delay
  @e2e-exempt
  Scenario: The generated Caddy configuration rejects a nonzero stream-close delay
    When the deployment tool generates the reverse-proxy configuration for a release
    Then the generated configuration omits "stream_close_delay" and any other nonzero stream-close delay
    And the existing global five-minute grace period remains present

  Rule: Promoted-slot-only handshake routing

  # Exemption(e2e): holding a routed socket across a live Caddy config reload is a release-time infrastructure action outside application-level E2E; alternative-proof: bnest-app:test:integration / A replacement handshake routes only to the promoted slot while the prior slot stays warm
  @e2e-exempt
  Scenario: A replacement handshake routes only to the promoted slot while the prior slot stays warm
    Given a routed socket is held open on the prior slot before promotion
    When Caddy reloads to route the promoted slot
    Then the prior-slot socket closes
    And every replacement handshake reaches only the promoted slot
    And the prior slot remains process-warm and receives no new routed handshake during the observation window
