Feature: Beaver Nest chat

  Scenario: A visitor opens a fresh chat
    When a visitor opens "/"
    Then the page displays the heading "Beaver Nest"
    And the page displays the text "Terra · medium"
    And the conversation is empty
    And the message composer is available

  Scenario: A visitor cannot send an empty message
    Given a visitor opens "/"
    When the visitor attempts to send an empty message
    Then the conversation is empty
    And the message composer is available

  Scenario: A visitor cannot overlap Codex turns
    Given a visitor opens "/"
    When the visitor sends "First message"
    Then the conversation displays the visitor message "First message"
    And the message composer is unavailable
    When the visitor attempts to send "Too soon" before Codex finishes
    Then the conversation does not display the visitor message "Too soon"
    And a Codex response appears incrementally
    And the message composer is available

  Scenario: A visitor continues one page-scoped conversation
    Given a visitor opens "/"
    When the visitor sends "Hello, Beaver Nest"
    And a Codex response appears incrementally
    When the visitor sends "Remember me"
    Then the conversation displays the visitor message "Remember me"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  Scenario: The Codex session cannot accept a message
    Given a visitor opens "/"
    When Codex rejects the visitor message "Are you there?"
    Then the page displays the alert "Codex is not available."
    And the message composer is available

  Scenario: Codex reports a failed turn
    Given a visitor opens "/"
    When the visitor sends "Please fail this turn"
    And Codex reports the error "Turn failed."
    Then the page displays the alert "Turn failed."
    And the message composer is available

  Scenario: Refresh clears a completed conversation
    Given a visitor opens "/"
    When the visitor sends "Temporary message"
    And a Codex response appears incrementally
    When the visitor reloads the page
    Then the conversation is empty
    And the message composer is available
