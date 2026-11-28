Feature: Bnest operator commands

  # Exemption(e2e): an operator Mix task on the host database, below every public application boundary; alternative-proof: bnest-app:test:integration / mix bnest.storage.purge_test_data verifies or purges verified legacy test data
  @e2e-exempt
  Scenario Outline: mix bnest.storage.purge_test_data verifies or purges verified legacy test data
    Given a generation holding verified legacy test data
    When the operator runs purge_test_data with "<arguments>"
    Then the task reports "<report>"
    And the legacy test data is "<state>"

    Examples:
      | arguments                  | report                                                                       | state   |
      | --generation gen --dry-run | legacy test data verified records=2 recovery_sources=1                       | kept    |
      | --generation gen           | legacy test data purged records=2 recovery_sources=1                         | removed |
      | --generation other         | legacy test data cleanup refused: generation_mismatch                        | kept    |
      | --dry-run                  | usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run] | kept    |

  # Exemption(e2e): the audit's report is printed by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / mix bnest.schema.audit prints one pass or fail line per record type
  @e2e-exempt
  Scenario Outline: mix bnest.schema.audit prints one pass or fail line per record type
    Given an auditable default root and an auditable other root
    When the operator runs schema_audit with "<arguments>"
    Then the task reports "<report>"
    And the audit "<outcome>"

    Examples:
      | arguments      | report                               | outcome                                       |
      | (default root) | chat:v1 pass                         | exits 0                                       |
      | (other root)   | chat:v1 fail                         | raises schema audit failed                    |
      | (refused root) | schema audit refused: unsupported_root | raises schema audit refused: unsupported_root |

  # Exemption(e2e): an operator Mix task below every public boundary; alternative-proof: bnest-app:test:integration / mix bnest.identity.benchmark prints the Argon2id cost and a timing class, never a secret
  @e2e-exempt
  Scenario Outline: mix bnest.identity.benchmark prints the Argon2id cost and a timing class, never a secret
    Given a hasher timing of "<timing>"
    When the operator runs identity_benchmark
    Then the task reports "<report>"

    Examples:
      | timing           | report                                                                          |
      | 999 ms Argon2id  | argon2id memory_kib=32768 iterations=2 parallelism=1 timing_class=under-one-second |
      | 1000 ms Argon2id | argon2id memory_kib=32768 iterations=2 parallelism=1 timing_class=one-second-or-more |
      | not Argon2id     | configured password hasher did not produce Argon2id                            |

  # Exemption(e2e): Mix tasks below every public boundary; alternative-proof: bnest-app:test:integration / The storage tasks refuse unknown options with their usage line
  @e2e-exempt
  Scenario Outline: The storage tasks refuse unknown options with their usage line
    Given an isolated storage root
    When the operator runs "<task>" with "<arguments>"
    Then it refuses with "<usage>" and changes nothing

    Examples:
      | task                  | arguments         | usage                                                                                  |
      | bnest.storage.migrate | --unknown         | usage: mix bnest.storage.migrate [--root <flat-root>] [--activate]                     |
      | bnest.storage.migrate | stray             | usage: mix bnest.storage.migrate [--root <flat-root>] [--activate]                     |
      | bnest.storage.relocate | --unknown        | usage: mix bnest.storage.relocate [--destination <directory>]                           |
      | bnest.storage.relocate | stray            | usage: mix bnest.storage.relocate [--destination <directory>]                           |
      | bnest.storage.retire  | --generation gen  | usage: mix bnest.storage.retire --root <flat-root> --generation <generation> [--dry-run] |
      | bnest.storage.retire  | --root root       | usage: mix bnest.storage.retire --root <flat-root> --generation <generation> [--dry-run] |
      | purge_test_data       | --dry-run         | usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run]          |
      | bnest.schema.audit    | stray             | usage: mix bnest.schema.audit [--root <runtime-root>]                                   |

  # Exemption(e2e): a host-tree maintenance tool below every public application boundary; alternative-proof: bnest-app:test:integration / node tools/test-data-cleanup.mjs removes only stale marked test runs and reports the counts
  @e2e-exempt
  Scenario Outline: node tools/test-data-cleanup.mjs removes only stale marked test runs and reports the counts
    Given a test home holding "<setup>"
    When the operator runs the test-data cleanup
    Then it prints "<line>"

    Examples:
      | setup                                | line                                   |
      | a stale marked run with a dead owner | test data cleanup: removed=1 retained=0 |
      | a young marked run                   | test data cleanup: removed=0 retained=1 |
      | an unmarked directory                | test data cleanup: removed=0 retained=1 |
      | a stale marked run with a live owner | test data cleanup: removed=0 retained=1 |
      | a stale legacy run                   | test data cleanup: removed=1 retained=0 |
      | a symlinked run                      | test data cleanup: removed=0 retained=0 |

  # Exemption(e2e): a host maintenance tool below every public boundary; alternative-proof: bnest-app:test:integration / Test-data cleanup refuses bad arguments and negative hours
  @e2e-exempt
  Scenario Outline: Test-data cleanup refuses bad arguments and negative hours
    Given a test home holding a stale marked run with a dead owner
    When the operator runs the test-data cleanup with "<arguments>"
    Then it refuses with "<refusal>", exits non-zero and removes nothing

    Examples:
      | arguments              | refusal                                                                    |
      | --unknown              | usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]       |
      | --older-than-hours     | usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]       |
      | extra                  | usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]       |
      | --older-than-hours -1  | hours must be non-negative                                                 |
      | --older-than-hours lot | hours must be non-negative                                                 |
