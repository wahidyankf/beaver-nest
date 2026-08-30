Feature: Resource guard build artifacts
  Compiled development artifacts stay bounded and outside repository history.

  @unit-exempt @e2e-exempt
  Scenario: Nx does not retain compiled build snapshots
    Given the resource guard Nx build configuration
    When build artifact caching is inspected
    Then compiled binaries are excluded from the Nx cache

  @unit-exempt @e2e-exempt
  Scenario: End-to-end binaries are temporary
    Given the resource guard end-to-end harness
    When its compiled binary lifecycle is inspected
    Then the end-to-end binary is removed after the run

  @unit-exempt @e2e-exempt
  Scenario: Bootstrap cache retention is bounded
    Given four historical bootstrap generations
    When the current bootstrap generation runs
    Then only the current and two recent generations remain
