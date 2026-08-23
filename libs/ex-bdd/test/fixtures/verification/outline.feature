Feature: Expanded scenarios

  Scenario Outline: Every row is executable
    Given a valid precondition
    When a valid action occurs
    Then a valid outcome is observed

    Examples:
      | value |
      | one   |
      | two   |
