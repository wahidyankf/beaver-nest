Feature: Bnest test isolation

  Rule: Every test starts from its own empty migrated database

  # Exemption(e2e): the schema is a database-internal fact, and the browser and HTTP boundary exposes no view of the SQLite catalog; alternative-proof: bnest-app:test:integration / The migrated test schema equals the release schema
  @e2e-exempt
  Scenario: The migrated test schema equals the release schema
    Given a test instance was spawned and migrated
    When its schema is compared with a database built by the release migration entry points
    Then the schema objects and the applied migration versions are identical
    And the applied migration versions match the committed migration files exactly

  Rule: Teardown leaves nothing behind

  # Exemption(e2e): the instance directories, the storage pointer and the backup configuration are host filesystem state that the browser and HTTP boundary cannot observe; alternative-proof: bnest-app:test:integration / Teardown removes every directory, pointer, and backup configuration the instance made
  @e2e-exempt
  Scenario: Teardown removes every directory, pointer, and backup configuration the instance made
    Given a test instance is current
    When the test deletes the instance
    Then no instance directory, storage pointer, or backup configuration file for that instance remains
    And the run root holds no database file

  Rule: Testing endpoints stay closed to every caller but the test runner

  # Exemption(e2e): the browser and HTTP client always connects over loopback, so it cannot present a non-loopback peer address; alternative-proof: bnest-app:test:integration / A request from a non-loopback peer gets the stock not-found response
  @e2e-exempt
  Scenario: A request from a non-loopback peer gets the stock not-found response
    When a client on a non-loopback address creates a test instance with the run secret
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

  Rule: Production builds mount no testing endpoint

  # Exemption(integration): the integration suite runs only the test build, so a production build is outside its boundary; alternative-proof: bnest-app:test:unit / A production build mounts no testing endpoint
  @integration-exempt
  # Exemption(e2e): the browser suite runs against the test build, so a production build is outside its boundary; alternative-proof: bnest-app:test:unit / A production build mounts no testing endpoint
  @e2e-exempt
  Scenario: A production build mounts no testing endpoint
    Given the build environment is production
    When the build is assembled with the testing control flag on
    Then the build exposes no testing endpoint

  Rule: A failed spawn leaves nothing behind

  # Exemption(e2e): a fault cannot be placed in the middle of a spawn through the testing endpoints, so the browser and HTTP boundary cannot force it; alternative-proof: bnest-app:test:integration / A failed seed step rolls the spawn back
  @e2e-exempt
  Scenario: A failed seed step rolls the spawn back
    Given no test instance is current
    And seeding will fail after the first seeded account is created
    When a test spawns an instance with two seeded accounts
    Then the spawn fails at the seed step
    And no test instance is current
    And no instance directory, storage pointer, or backup configuration file remains

  # Exemption(e2e): a fault cannot be placed in the middle of a spawn through the testing endpoints, so the browser and HTTP boundary cannot force it; alternative-proof: bnest-app:test:integration / A failed migration rolls the spawn back
  @e2e-exempt
  Scenario: A failed migration rolls the spawn back
    Given no test instance is current
    And the migration will fail on its first migration
    When a test spawns an instance
    Then the spawn fails at the migrate step
    And no test instance is current
    And no instance directory, storage pointer, or backup configuration file remains
