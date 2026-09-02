Feature: Guarded process execution
  The guard serializes heavy work, keeps long-lived services outside that lease, and owns only the process it launches.

  @e2e-exempt
  Scenario: A live heavy lease defers a second owner
    Given another live process owns the heavy lease
    When a second owner waits for the lease
    Then the second owner is deferred with exit 75
    And the deferral names the process holding the lease

  @e2e-exempt
  Scenario: A long-lived service never holds the heavy-work lease
    Given a live service session owns its resource lease
    When heavy work requests the lease
    Then the heavy owner acquires the lease immediately

  @e2e-exempt
  Scenario: Concurrent services keep their own inheritable sessions
    Given two live service sessions on separate ports
    When each service child validates its inherited session
    Then both inherited sessions remain valid

  Scenario: An inherited session runs without reacquiring the lease
    Given a valid inherited resource session
    When a guarded child exits successfully
    Then the child exit code is preserved

  Scenario: A failed child keeps its own exit code
    Given an admitted guarded command
    When the guarded child exits with code 17
    Then the guard exits with code 17

  @e2e-exempt
  Scenario: An interrupted guard signals once and then force-stops the child
    Given an admitted child that ignores termination
    When the guard is interrupted
    Then the child is signalled once and force-stopped within the grace

  @e2e-exempt
  Scenario: Critical pressure sheds eligible work
    Given an admitted ephemeral child encounters critical pressure
    When the guard observes the critical sample
    Then only the guarded child group is terminated with exit 75
