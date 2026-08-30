Feature: Guarded process execution
  The guard serializes heavy work and owns only the process it launches.

  @e2e-exempt
  Scenario: A live heavy lease defers a second owner
    Given another live process owns the heavy lease
    When a second owner waits for the lease
    Then the second owner is deferred with exit 75

  Scenario: An inherited session runs without reacquiring the lease
    Given a valid inherited resource session
    When a guarded child exits successfully
    Then the child exit code is preserved

  Scenario: A failed child keeps its own exit code
    Given an admitted guarded command
    When the guarded child exits with code 17
    Then the guard exits with code 17

  @e2e-exempt
  Scenario: Critical pressure sheds eligible work
    Given an admitted ephemeral child encounters critical pressure
    When the guard observes the critical sample
    Then only the guarded child group is terminated with exit 75
