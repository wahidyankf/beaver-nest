Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

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

  Scenario: Persist a daily schedule across restart
    Given the administrator saved an enabled daily WIB schedule
    When the scheduler restarts before the schedule is due
    Then the schedule remains enabled in SQLite
    And the same future UTC slot remains due

  Scenario: Catch up only the latest missed slot
    Given the scheduler missed more than one daily slot
    When startup reconciliation runs
    Then only the latest eligible slot is claimed
    And the next run advances to the next future day

  Scenario: Back up authoritative SQLite
    Given a production backup claim is accepted
    When the backup handler runs
    Then only configured authoritative SQLite is snapshotted with VACUUM INTO
    And the candidate passes independent integrity and logical proof

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

  Scenario: Retain only owned verified artifacts
    Given verified owned pairs span more than seven WIB dates beside unknown files
    When a new backup becomes verified
    Then Bnest keeps one newest owned pair for each retained WIB date
    And Bnest preserves unknown files and every previous destination

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

  Scenario: Expire schedules deterministically
    Given schedules use never absolute and occurrence expiration policies
    When the coordinator reconciles claims and retries
    Then expiry blocks only ineligible future claims
    And retries do not consume occurrences or suppress the final occurrence
