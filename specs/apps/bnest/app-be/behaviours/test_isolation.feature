Feature: Bnest test isolation

  Rule: Every test starts from its own empty migrated database

  # The empty-database scenario needs a flat-primary instance with no seeded account, so /setup stays open.
  @flat-primary @open-setup
  Scenario: A test starts from an empty migrated database
    Given no test instance is current
    When a test spawns an instance with no seeded accounts
    Then the instance database holds no account, browser session, chat message, or user record
    And the initial setup stays open for that instance

  Scenario: Consecutive tests never share a database
    Given a test spawned an instance and created an account in it
    When the next test spawns its own instance
    Then the next instance has a different instance ID and generation
    And the account created by the previous test cannot be found in the next instance
    And the readiness check reports the generation of the next instance

  # Exemption(e2e): the comparison builds a second database with the release migration entry points, which run only inside the Elixir test build; the browser and HTTP boundary has no view of the SQLite catalog, and the e2e layer reads a catalog only through a second Mix process over a CLI-built database, never over a spawned test instance; alternative-proof: bnest-app:test:integration / The migrated test schema equals the release schema
  @e2e-exempt
  Scenario: The migrated test schema equals the release schema
    Given a test instance was spawned and migrated
    When its schema is compared with a database built by the release migration entry points
    Then the schema objects and the applied migration versions are identical
    And the applied migration versions match the committed migration files exactly

  Rule: Each test runs spawn, migrate, seed, test, and teardown in order

  Scenario: Spawn, migrate, seed, test, and teardown run in that order
    Given no test instance is current
    When a test spawns an instance with one seeded account
    Then the spawn returns only after its migrations and its seed have finished
    And the seeded account can log in as soon as the spawn returns
    And the instance stays current until the test deletes it

  Rule: Teardown leaves nothing behind

  Scenario: Teardown removes the instance from the running server
    Given a test instance is current
    When the test deletes the instance
    Then the server reports no current instance
    And a second delete of that instance is refused

  Scenario: Teardown removes every directory, pointer, and backup configuration the instance made
    Given a test instance is current
    When the test deletes the instance
    Then no instance directory, storage pointer, or backup configuration file for that instance remains
    And the run root holds no database file

  Rule: Testing endpoints stay closed to every caller but the test runner

  Scenario: A request without the testing header gets the stock not-found response
    Given no test instance is current
    When a client creates a test instance without the testing header
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

  Scenario: A request with a wrong testing header gets the stock not-found response
    Given no test instance is current
    When a client creates a test instance with a testing header that is not the run secret
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

  Scenario: A request with a forwarded header gets the stock not-found response
    Given no test instance is current
    When a client creates a test instance with the run secret and an x-forwarded-for header
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

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

  Rule: Seeded accounts are test identities only

  Scenario: Every seeded account uses the test-user prefix and the instance short ID
    Given no test instance is current
    When a test spawns an instance with two seeded accounts
    Then the spawn response lists exactly those two accounts
    And each listed username starts with "test-user-"
    And each listed username carries the first eight characters of the instance ID

  Scenario: A seeded username outside the test-user prefix is refused
    Given no test instance is current
    When a test spawns an instance with a seeded account named "family-admin"
    Then the spawn is refused with an invalid username error that names the username field
    And no test instance is current
    And no instance directory remains for that spawn

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
