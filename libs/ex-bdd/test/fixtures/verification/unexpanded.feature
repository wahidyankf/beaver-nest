Feature: Unexpanded scenario outline

  Scenario Outline: No example rows
    Given a valid precondition
    When a valid action occurs
    Then a valid outcome is observed

    Examples:
      | value |
