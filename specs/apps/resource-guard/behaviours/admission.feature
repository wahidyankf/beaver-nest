Feature: Resource-aware admission
  Repository work adapts to the effective capacity exposed by macOS or Linux.

  @e2e-exempt
  Scenario: Healthy consecutive samples admit work
    Given three healthy host samples
    When development admission is assessed
    Then the work is admitted

  @e2e-exempt
  Scenario: Balanced work falls back on a small runner
    Given a healthy 5 GiB runner without swap
    When development admission is assessed
    Then the constrained profile is selected

  @e2e-exempt
  Scenario: Minimal work still runs on a tiny machine
    Given a healthy 1 GiB machine without swap
    When development admission is assessed
    Then the minimal profile is selected with concurrency one

  @e2e-exempt
  Scenario: Exhausted storage requires cleanup
    Given a host sample below the 256 MiB disk floor
    When development admission is assessed
    Then admission is storage blocked with exit 73

  @e2e-exempt
  Scenario: Swap-out growth is normalized to the policy window
    Given swap-outs grow by 128 MiB over 15 seconds
    When development pressure is assessed
    Then the state is warning because of swap pressure

  @e2e-exempt
  Scenario: Compressor growth requires both payload and growth
    Given compressor payload is 12 GiB and grows 1 GiB over 15 seconds
    When development pressure is assessed
    Then the state is warning because of compressor pressure

  @e2e-exempt
  Scenario: A strict transaction does not silently downgrade
    Given a strict transactional task that does not fit its requested profile
    When development admission is assessed
    Then admission requires replanning with exit 78
