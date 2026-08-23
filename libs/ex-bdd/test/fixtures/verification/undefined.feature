Feature: Undefined binding

  Scenario: One step has no implementation
    Given a valid precondition
    When an undefined action occurs
    Then a valid outcome is observed
