Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

  # Exemption(e2e): destination resolution and public receipt redaction have no public command or browser action; alternative-proof: bnest-app:test:integration / Use the Dropbox-synced default
  @e2e-exempt
  Scenario: Use the Dropbox-synced default
    Given no backup override exists
    When the daily backup destination resolves
    Then Bnest uses the ignored repository backup folder
    And the verified result exposes no private path

  Scenario: Save a safe override
    Given an administrator opened schedules and backups
    When the administrator saves a safe backup override
    Then Bnest stores the private backup configuration atomically
    And Bnest creates one idempotent setup claim for that destination

  # Exemption(e2e): durable restart state is an internal same-machine scheduler boundary; alternative-proof: bnest-app:test:integration / Persist a daily schedule across restart
  @e2e-exempt
  Scenario: Persist a daily schedule across restart
    Given the administrator saved an enabled daily WIB schedule
    When the scheduler restarts before the schedule is due
    Then the schedule remains enabled in SQLite
    And the same future UTC slot remains due

  # Exemption(e2e): missed-slot reconciliation is an internal same-machine scheduler boundary; alternative-proof: bnest-app:test:integration / Catch up only the latest missed slot
  @e2e-exempt
  Scenario: Catch up only the latest missed slot
    Given the scheduler missed more than one daily slot
    When startup reconciliation runs
    Then only the latest eligible slot is claimed
    And the next run advances to the next future day

  # Exemption(e2e): VACUUM and logical proof operate below every public application boundary; alternative-proof: bnest-app:test:integration / Back up authoritative SQLite
  @e2e-exempt
  Scenario: Back up authoritative SQLite
    Given a production backup claim is accepted
    When the backup handler runs
    Then only configured authoritative SQLite is snapshotted with VACUUM INTO
    And the candidate passes independent integrity and logical proof

  # Exemption(e2e): claim fencing and retry leases are internal same-machine coordination boundaries; alternative-proof: bnest-app:test:integration / Claim a slot once and recover
  @e2e-exempt
  Scenario: Claim a slot once and recover
    Given two coordinators observe the same slot and an attempt may lose its lease
    When both coordinators reconcile
    Then SQLite accepts one claim and backup tasks do not overlap
    And transient failure receives at most three persisted attempts

  Scenario: Show contextual daily schedules
    Given family and admin-system daily schedules are persisted
    When an administrator follows schedules and backups from home
    Then both contexts appear in separate groups with safe status
    And the backup row links to its typed settings

  Scenario: Deny schedule and configuration access
    Given an unauthenticated revoked or non-admin visitor
    When the visitor opens an admin settings route
    Then Bnest returns not found before protected reads
    And home exposes no admin settings entry

  # Exemption(e2e): receipt ownership and retention operate on private server files without a public trigger; alternative-proof: bnest-app:test:integration / Retain only owned verified artifacts
  @e2e-exempt
  Scenario: Retain only owned verified artifacts
    Given verified owned pairs span more than seven WIB dates beside unknown files
    When a new backup becomes verified
    Then Bnest keeps one newest owned pair for each retained WIB date
    And Bnest preserves unknown files and every previous destination

  # Exemption(e2e): coordinator dispatch and ledger updates are internal same-machine boundaries; alternative-proof: bnest-app:test:integration / Reuse one scheduler across contexts
  @e2e-exempt
  Scenario: Reuse one scheduler across contexts
    Given a second allowlisted family handler is persisted
    When its daily slot becomes due
    Then the shared coordinator and supervisor execute it
    And the shared ledger and contextual inventory record it

  Scenario: Discover typed admin configuration
    Given multiple domains declare typed admin settings panels
    When an administrator opens admin settings from home
    Then every declared panel is discoverable
    And each owner validates and saves only its allowlisted fields

  # Exemption(e2e): expiration and retry occurrence accounting are internal scheduler policy boundaries; alternative-proof: bnest-app:test:integration / Expire schedules deterministically
  @e2e-exempt
  Scenario: Expire schedules deterministically
    Given schedules use never absolute and occurrence expiration policies
    When the coordinator reconciles claims and retries
    Then expiry blocks only ineligible future claims
    And retries do not consume occurrences or suppress the final occurrence
