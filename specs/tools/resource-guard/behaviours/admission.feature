Feature: Resource-aware admission
  Repository work starts only when macOS exposes safe resource headroom.

  @e2e-exempt
  Scenario: Healthy consecutive samples admit work
    Given three healthy host samples
    When development admission is assessed
    Then the work is admitted

  @e2e-exempt
  Scenario: Storage warning blocks admission without pretending it is transient
    Given a host sample with 29 GiB of free disk
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
