# Every scenario starts from a flat-file source, so each runs on a flat-primary test instance (ADR 001, section 2).
# A scenario tagged @storage-unconfigured starts before any database location is chosen, as a fresh installation
# does: its instance has no storage pointer and no database yet (ADR 001, section 1, "Phase").
@flat-primary
Feature: Bnest SQLite storage

  Background:
    Given an approved user is logged in

  Scenario: The storage migration task uses the default private data folder with no browser visit
    Given Bnest has no storage configuration
    And the storage UI has not been visited
    When the operator runs `mix bnest.storage.migrate`
    Then it exits 0 and the database file is in the default data folder

  @storage-unconfigured
  Scenario Outline: Administrator optionally selects a valid custom database folder
    Given an authenticated user with the admin role opened storage settings
    And migration has not started
    When <folder entry>
    Then Bnest normalizes the folder and appends the fixed database filename
    And Bnest stores only the validated absolute location in private machine state

    Examples:
      | folder entry                                                                  |
      | the administrator enters a writable private server-local folder               |
      | the administrator enters a private folder beneath a sticky shared directory   |

  Scenario: Unsafe database folder is rejected without mutation
    Given an authenticated user with the admin role opened storage settings
    When the folder is relative, symlinked, world-writable, inside the repository, or overlaps a migration source
    Then Bnest explains the safe correction
    And Bnest creates no database or storage configuration

  Scenario: Versioned SQLite migration creates the expected schema once
    Given an empty isolated database
    When the committed migration set is applied twice
    Then the schema version and indexes match the declared checksum
    And the second run makes no duplicate table, index, or migration record

  Scenario: The storage migration task moves every recognized record and reports none blocked
    Given a flat-primary installation has no custom storage location
    When managed storage migration runs without a UI visit
    Then the task reports accepted records with blocked=0 and exits 0, and every record reads back unchanged through the app

  Scenario: Running the storage migration task again after an interruption finishes it without duplicates
    Given migration stopped after at least one accepted item
    When the operator runs the same task again
    Then it exits 0, the counts show the remaining items accepted, and no record appears twice

  Scenario: The task switches storage to SQLite only when every check passes and the app then reads from it
    Given schema, backfill, parity, integrity, and isolated restore checks pass
    When the managed migration commits the storage authority switch without UI confirmation
    Then future reads use SQLite

  Scenario: Chat, learning, theme, login and logout survive a restart after the switch
    Given schema, backfill, parity, integrity, and isolated restore checks pass
    When the managed migration commits the storage authority switch without UI confirmation
    And verified flat-file identity sources are retired
    Then chat, learning, theme, login, and logout survive an application restart

  Scenario: Invalid or changed source blocks cutover without data loss
    Given a source is malformed, unsupported, or changes after inventory
    When Bnest verifies migration
    Then SQLite does not become authoritative
    And the source and current flat-primary service remain unchanged
    And the administrator sees a value-free retry category

  Scenario: The relocate task moves SQLite to the production data folder and keeps the old files until proof
    Given authoritative SQLite still uses the legacy configuration directory
    When the operator runs `mix bnest.storage.relocate`
    Then it exits 0 printing "relocation verified", the database is in the production data folder, and the legacy SQLite files are still present

  Scenario: Verified legacy flat-file storage is retired
    Given routed SQLite proof matches the authoritative database generation
    When managed legacy storage cleanup runs
    Then Bnest removes every verified flat-file source and legacy SQLite sidecar
    And Bnest preserves storage configuration and tracked placeholders
