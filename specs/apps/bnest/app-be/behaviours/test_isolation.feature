Feature: Bnest test isolation

  Rule: Every test starts from its own empty migrated database

  # The empty-database scenario needs a flat-primary instance with no seeded account, so /setup stays open.
  @flat-primary @open-setup
  Scenario: A spawned instance with no seeded accounts starts empty with initial setup open
    Given no test instance is current
    When a test spawns an instance with no seeded accounts
    Then no account can log in, the chat has no messages, and the initial setup page is open
    And the instance database holds no browser session or user record

  Scenario: Consecutive tests never share a database
    Given a test spawned an instance and created an account in it
    When the next test spawns its own instance
    Then the next instance has a different instance ID and generation
    And the account created by the previous test cannot be found in the next instance
    And the readiness check reports the generation of the next instance

  Rule: Each test uses its instance only after its spawn has migrated and seeded it

  Scenario: The spawn returns after its migrations and seed, and the instance stays current until deletion
    Given no test instance is current
    When a test spawns an instance with one seeded account
    Then the spawn returns only after its migrations and its seed have finished
    And the seeded account can log in as soon as the spawn returns
    And the instance stays current until the test deletes it

  Scenario: A seed is applied once per key
    Given a test instance is current
    When a test seeds the current instance under a new seed key
    Then the seed answers applied true and the seeded account can log in
    When the test repeats that seed key with the same body
    Then the repeat answers applied false and writes no new account

  # Carries BN-TEST-03.
  Scenario: POST /instances/:id/seed applies a seed once per key
    Given a test instance is current
    When a test seeds the current instance under a new seed key
    Then the seed answers applied true and the seeded account can log in
    When the test repeats that seed key with the same body
    Then the repeat answers applied false and writes no new account

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

  Scenario Outline: A request that is not the test runner's gets the stock not-found response
    Given no test instance is current
    When a client creates a test instance <request>
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

    Examples:
      | request                                                  |
      | without the testing header                               |
      | with a testing header that is not the run secret         |
      | with the run secret and an x-forwarded-for header        |

  # Exemption(e2e): the browser and HTTP client always connects over loopback, so it cannot present a non-loopback peer address; alternative-proof: bnest-app:test:integration / A request from a non-loopback peer gets the stock not-found response
  @e2e-exempt
  Scenario: A request from a non-loopback peer gets the stock not-found response
    When a client on a non-loopback address creates a test instance with the run secret
    Then the response is the stock "Not Found" response that a missing route gets
    And no test instance is created

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

  # Exemption(e2e): the testing endpoints cannot place a fault inside a spawn, neither a write fault after the first seeded account, because seed validation runs before any write, nor a failing migration; alternative-proof: bnest-app:test:integration / A failed spawn leaves nothing behind
  @e2e-exempt
  Scenario Outline: A failed spawn leaves nothing behind
    Given no test instance is current
    And <fault>
    When a test spawns an instance with two seeded accounts
    Then the spawn fails at the <step> step
    And no test instance is current
    And no instance directory, storage pointer, or backup configuration file remains

    Examples:
      | fault                                                       | step    |
      | seeding will fail after the first seeded account is created | seed    |
      | the migration will fail on its first migration              | migrate |

  Rule: A conflicting testing-control request answers 409 with its code

  Scenario Outline: A conflicting testing-control request answers 409 with its code
    Given <setup>
    When <conflict>
    Then the response is a 409 answer with the code "<code>"
    And the answer echoes none of the request's input

    Examples:
      | setup                                                  | conflict                                                       | code            |
      | no test instance is current                            | a test asks the server to spawn an instance under another run id | run_mismatch    |
      | a test instance is current                             | a test asks the server to spawn an instance                    | instance_active |
      | no test instance is current                            | a test seeds an instance that is not current                   | not_current     |
      | a test seeded a current instance under a seed key      | a test seeds the current instance with another body under it  | seed_conflict   |

  # Exemption(e2e): a scheduler task cannot be held running from the exact origin, because the e2e server runs with the automatic scheduler off and exposes no way to start one; alternative-proof: bnest-app:test:integration / A spawn while a scheduler task runs answers 409 instance_busy
  @e2e-exempt
  Scenario: A spawn while a scheduler task runs answers 409 instance_busy
    Given no test instance is current
    And a scheduler task is running
    When a test asks the server to spawn an instance
    Then the response is a 409 answer with the code "instance_busy"

  # Carries BN-TEST-10.
  Scenario Outline: Conflicts answer 409: run mismatch, active, busy, seed key
    Given <setup>
    When <conflict>
    Then the response is a 409 answer with the code "<code>"
    And the answer echoes none of the request's input

    Examples:
      | setup                                                 | conflict                                                       | code            |
      | no test instance is current                           | a test asks the server to spawn an instance under another run id | run_mismatch    |
      | a test instance is current                            | a test asks the server to spawn an instance                    | instance_active |
      | a test seeded a current instance under a seed key     | a test seeds the current instance with another body under it   | seed_conflict   |

  # Carries BN-TEST-10.
  # Exemption(e2e): a scheduler task cannot be held running from the exact origin, because the e2e server runs with the automatic scheduler off and exposes no way to start one; alternative-proof: bnest-app:test:integration / A spawn refused by a running scheduler task answers 409 instance_busy
  @e2e-exempt
  Scenario: A spawn refused by a running scheduler task answers 409 instance_busy
    Given no test instance is current
    And a scheduler task is running
    When a test asks the server to spawn an instance
    Then the response is a 409 answer with the code "instance_busy"
