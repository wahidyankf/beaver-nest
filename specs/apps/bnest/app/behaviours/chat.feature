Feature: Beaver Nest chat

  Scenario: A visitor can install Beaver Nest as an app
    When a visitor opens "/"
    Then the page displays the Beaver Nest logo
    And Beaver Nest is ready to install as an app

  Scenario: A visitor enters chat from the home page
    When a visitor opens "/"
    Then the page displays the heading "Beaver Nest"
    And the page offers the "Start chatting" link to "/chat"

  Scenario: A visitor opens a fresh chat
    When a visitor opens "/chat"
    Then the page displays the heading "Beaver Nest"
    And the page displays the text "Terra · medium"
    And the model selector lists every available Codex model
    And the selected model is "GPT-5.6-Terra"
    And the reasoning effort selector lists every effort supported by the selected model
    And the selected reasoning effort is "Medium"
    And the conversation is empty
    And the message composer is available
    And the model selector is available
    And the reasoning effort selector is available
    And the clear chat control is available

  Scenario: A visitor cannot send an empty message
    Given a visitor opens "/chat"
    When the visitor attempts to send an empty message
    Then the conversation is empty
    And the message composer is available

  Scenario: A visitor cannot overlap Codex turns
    Given a visitor opens "/chat"
    When the visitor sends "First message"
    Then the conversation displays the visitor message "First message"
    And the message composer is unavailable
    And the model selector is unavailable
    And the reasoning effort selector is unavailable
    When the visitor attempts to send "Too soon" before Codex finishes
    Then the conversation does not display the visitor message "Too soon"
    And a Codex response appears incrementally
    And the message composer is available
    And the model selector is available
    And the reasoning effort selector is available

  Scenario: A visitor sends a message with Shift+Enter
    Given a visitor opens "/chat"
    When the visitor submits "Keyboard message" with Shift+Enter
    Then the conversation displays the visitor message "Keyboard message"
    And the message composer is unavailable
    And a Codex response appears incrementally
    And the message composer is available

  Scenario: A visitor continues one page-scoped conversation
    Given a visitor opens "/chat"
    When the visitor sends "Hello, Beaver Nest"
    And a Codex response appears incrementally
    When the visitor sends "Remember me"
    Then the conversation displays the visitor message "Remember me"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  Scenario: A visitor changes models within one Codex conversation
    Given a visitor opens "/chat"
    When the visitor sends "Before model switch"
    And a Codex response appears incrementally
    When the visitor selects the reasoning effort "High"
    And the visitor selects the model "GPT-5.6-Luna"
    Then the selected model is "GPT-5.6-Luna"
    And the reasoning effort selector lists every effort supported by the selected model
    And the selected reasoning effort is "High"
    And the conversation displays the visitor message "Before model switch"
    When the visitor sends "After model switch"
    Then the conversation displays the visitor message "After model switch"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  Scenario: A visitor changes reasoning effort within one Codex conversation
    Given a visitor opens "/chat"
    When the visitor sends "Before effort switch"
    And a Codex response appears incrementally
    When the visitor selects the reasoning effort "High"
    Then the selected reasoning effort is "High"
    And the conversation displays the visitor message "Before effort switch"
    When the visitor sends "After effort switch"
    Then the conversation displays the visitor message "After effort switch"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  Scenario: A model change falls back from an unsupported reasoning effort
    Given a visitor opens "/chat"
    When the visitor selects the reasoning effort "Ultra"
    And the visitor selects the model "GPT-5.6-Luna"
    Then the selected model is "GPT-5.6-Luna"
    And the reasoning effort selector lists every effort supported by the selected model
    And the selected reasoning effort is "Medium"

  Scenario: The Codex session cannot accept a message
    Given a visitor opens "/chat"
    When Codex rejects the visitor message "Are you there?"
    Then the page displays the alert "Codex is not available."
    And the message composer is available

  Scenario: Codex reports a failed turn
    Given a visitor opens "/chat"
    When the visitor sends "Please fail this turn"
    And Codex reports the error "Turn failed."
    Then the page displays the alert "Turn failed."
    And the message composer is available

  Scenario: Reload preserves a completed conversation and Codex session
    Given a visitor opens "/chat"
    When the visitor selects the model "GPT-5.6-Luna"
    And the visitor selects the reasoning effort "High"
    And the visitor sends "Temporary message"
    And a Codex response appears incrementally
    When the visitor reloads the page
    Then the selected model is "GPT-5.6-Luna"
    And the selected reasoning effort is "High"
    And the conversation displays the visitor message "Temporary message"
    And the conversation displays one completed Codex response
    When the visitor sends "After reload"
    Then the conversation displays the visitor message "After reload"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  Scenario: A visitor clears the chat and starts a new Codex session
    Given a visitor opens "/chat"
    When the visitor selects the model "GPT-5.6-Luna"
    And the visitor selects the reasoning effort "High"
    And the visitor sends "Old session marker"
    And a Codex response appears incrementally
    When the visitor clears the chat
    Then the conversation is empty
    And the selected model is "GPT-5.6-Luna"
    And the selected reasoning effort is "High"
    And the message composer is available
    When the visitor sends "Fresh start"
    Then the conversation displays the visitor message "Fresh start"
    And a Codex response appears incrementally
    And the conversation does not display the visitor message "Old session marker"
