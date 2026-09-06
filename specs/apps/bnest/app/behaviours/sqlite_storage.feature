Feature: Bnest SQLite storage

  Background:
    Given an approved user is logged in

  Scenario: Managed migration uses the private default without storage UI
    Given Bnest has no storage configuration
    And the storage UI has not been visited
    When managed migration starts
    Then Bnest keeps the storage pointer under the configuration home
    And Bnest uses the environment-specific data directory for SQLite
    And migration does not require a browser confirmation

  Scenario: Administrator optionally selects a valid custom database folder
    Given an authenticated user with the admin role opened storage settings
    And migration has not started
    When the administrator enters a writable private server-local folder
    Then Bnest normalizes the folder and appends the fixed database filename
    And Bnest stores only the validated absolute location in private machine state

  Scenario: Private custom storage survives a sticky shared ancestor
    Given an authenticated user with the admin role opened storage settings
    And migration has not started
    When the administrator enters a private folder beneath a sticky shared directory
    Then Bnest normalizes the folder and appends the fixed database filename
    And Bnest stores only the validated absolute location in private machine state

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

  Scenario: Managed migration moves every recognized flat-file record
    Given a flat-primary installation has no custom storage location
    When managed storage migration runs without a UI visit
    Then Bnest inventories records in deterministic path order
    And Bnest writes the database under the resolved storage directory
    And every recognized valid item is accepted without a block
    And each accepted item has immutable source and target checksum evidence
    And normal repository reads return the same validated record

  Scenario: Interrupted migration resumes idempotently
    Given migration stopped after at least one accepted item
    When the administrator retries the same migration identifier
    Then accepted matching items are not rewritten or duplicated
    And remaining items continue from their recorded outcomes

  Scenario: SQLite becomes authoritative only after complete verification
    Given schema, backfill, parity, integrity, and isolated restore checks pass
    When the managed migration commits the storage authority switch without UI confirmation
    Then future reads use SQLite
    And future writes remain compatible with the rollback reader
    And verified flat-file identity sources are retired
    And chat, learning, theme, login, and logout survive an application restart

  Scenario: Invalid or changed source blocks cutover without data loss
    Given a source is malformed, unsupported, or changes after inventory
    When Bnest verifies migration
    Then SQLite does not become authoritative
    And the source and current flat-primary service remain unchanged
    And the administrator sees a value-free retry category

  Scenario: Non-admin cannot configure storage
    Given a non-admin family member is logged in
    When the user opens the storage settings route
    Then Bnest denies the operation
    And Bnest reveals no host path or migration inventory

  # Exemption(integration): client-side LiveView auto-reconnect and DOM draft recovery run in the browser JS client and are not observable from Phoenix.LiveViewTest; alternative-proof: bnest-app-e2e:test:e2e / Routed client reconnects across compatible SQLite rollout
  @integration-exempt
  Scenario: Routed client reconnects across compatible SQLite rollout
    Given the current Caddy route is healthy and a connected user has acknowledged state
    When a revision-compatible candidate is promoted
    Then the routed revision and SQLite readiness are proven
    And the LiveView reconnects without a manual refresh
    And the acknowledged state and unsent draft remain available

  Scenario: Authoritative SQLite relocates out of the configuration directory
    Given authoritative SQLite still uses the legacy configuration directory
    When managed storage relocation runs
    Then the storage pointer resolves the production data directory atomically
    And legacy SQLite files remain until the new database passes routed proof

  Scenario: Verified legacy flat-file storage is retired
    Given routed SQLite proof matches the authoritative database generation
    When managed legacy storage cleanup runs
    Then Bnest removes every verified flat-file source and legacy SQLite sidecar
    And Bnest preserves storage configuration and tracked placeholders
