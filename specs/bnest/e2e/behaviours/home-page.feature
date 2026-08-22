Feature: Beaver Nest home page

  Scenario: A visitor opens Beaver Nest
    When a visitor opens "/"
    Then the page displays the heading "Hello, WW!"
    And the page displays the text "Welcome to Beaver Nest."
