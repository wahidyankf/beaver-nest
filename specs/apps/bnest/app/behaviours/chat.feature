Feature: Beaver Nest chat

  Rule: Public application installation

  # Exemption(integration): browser installability is not observable without a browser; alternative-proof: bnest-app-e2e:test:e2e / A visitor can install Beaver Nest as an app
  @integration-exempt
  Scenario: A visitor can install Beaver Nest as an app
    When a visitor opens "/"
    Then the page displays the Beaver Nest logo
    And Beaver Nest is ready to install as an app

  Rule: Authenticated user-owned chat

    Background:
      Given an approved admin is logged in

  Scenario: A visitor enters chat from the home page
    When a visitor opens "/"
    Then the page displays the heading "Beaver Nest"
    And the page offers the "Start chatting" link to "/chat"

  # Exemption(integration): rendered geometry is not observable without a browser layout engine; alternative-proof: bnest-app-e2e:test:e2e / Home controls and content remain visually separated
  @integration-exempt
  Scenario: Home controls and content remain visually separated
    When a visitor opens "/"
    Then the home header and hero do not overlap

  Scenario: A visitor returns home through the Beaver Nest brand
    Given a visitor opens "/chat"
    When the visitor follows the Beaver Nest home link
    Then the page displays the heading "Beaver Nest"
    And the page offers the "Start chatting" link to "/chat"

  Scenario: Completed browser migration is not offered from the home page
    When a visitor opens "/"
    Then the page does not offer browser-data migration

  Scenario: A visitor opens a fresh chat
    When a visitor opens "/chat"
    Then the page displays the heading "Beaver Nest"
    And the page displays the text "Terra · medium"
    And repository access is shown as read-only
    And the repository write control is available
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

  # Exemption(integration): physical keyboard chord handling belongs to the browser boundary; alternative-proof: bnest-app-e2e:test:e2e / A visitor sends a message with Shift+Enter
  @integration-exempt
  Scenario: A visitor sends a message with Shift+Enter
    Given a visitor opens "/chat"
    When the visitor submits "Keyboard message" with Shift+Enter
    Then the conversation displays the visitor message "Keyboard message"
    And the message composer is unavailable
    And a Codex response appears incrementally
    And the message composer is available

  Scenario: A visitor retains public Codex progress beside the final answer
    Given a visitor opens "/chat"
    When the visitor sends "Show progress"
    And Codex reports public progress
    Then the conversation shows the public Codex reasoning summary
    And the conversation preserves the Codex progress beside the final answer
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

  # Exemption(integration): automatic socket recovery crosses the browser and routed server boundary; alternative-proof: bnest-app-e2e:test:e2e / An automatic LiveView reconnect preserves a completed user-owned conversation and Codex session
  @integration-exempt
  Scenario: An automatic LiveView reconnect preserves a completed user-owned conversation and Codex session
    Given a visitor opens "/chat"
    When the visitor selects the model "GPT-5.6-Luna"
    And the visitor selects the reasoning effort "High"
    And the visitor sends "Temporary message"
    And a Codex response appears incrementally
    And the visitor types "Unsent draft" without sending
    When the visitor reconnects after a deployment
    Then the current route is "/chat"
    And the message composer contains "Unsent draft"
    Then the selected model is "GPT-5.6-Luna"
    And the selected reasoning effort is "High"
    And the conversation displays the visitor message "Temporary message"
    And the conversation displays one completed Codex response
    When the visitor sends "After reconnect"
    Then the conversation displays the visitor message "After reconnect"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

  # Exemption(integration): automatic socket recovery crosses the browser and routed server boundary; alternative-proof: bnest-app-e2e:test:e2e / An automatic LiveView reconnect safely restores a persisted in-progress user-owned turn
  @integration-exempt
  Scenario: An automatic LiveView reconnect safely restores a persisted in-progress user-owned turn
    Given a visitor opens "/chat"
    When the visitor sends "Resume after deployment"
    And the visitor reconnects after a deployment
    Then the current route is "/chat"
    And the conversation displays the visitor message "Resume after deployment"
    And the in-progress turn resumes once or fails safely without duplication
    Then the message composer is available

  # Exemption(integration): concurrent browser isolation and recovery require real browser contexts; alternative-proof: bnest-app-e2e:test:e2e / Ten synthetic visitors preserve recoverable state across three groups
  @integration-exempt
  Scenario: Ten synthetic visitors preserve recoverable state across three groups
    Given 10 synthetic visitors across 3 recovery groups have distinct drafts on "/chat"
    When every recovery-group visitor reconnects after a deployment
    Then every recovery-group visitor keeps its route and draft

  Scenario: A user clears normalized chat and starts a new Codex session
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

  Rule: Role-scoped Codex access

  Scenario: A child is limited to Luna at medium effort
    Given an approved child is logged in
    When a visitor opens "/chat"
    Then the page displays the text "Luna · medium"
    And repository access is shown as read-only
    And the repository write control is not shown
    And the selected model is "GPT-5.6-Luna"
    And the selected reasoning effort is "Medium"
    And the model selector is not shown
    And the reasoning effort selector is not shown
    And the chat controls do not overlap

  Scenario: A parent is limited to Terra at medium effort
    Given an approved parent is logged in
    When a visitor opens "/chat"
    Then the page displays the text "Terra · medium"
    And repository access is shown as read-only
    And the repository write control is not shown
    And the selected model is "GPT-5.6-Terra"
    And the selected reasoning effort is "Medium"
    And the model selector is not shown
    And the reasoning effort selector is not shown

  Scenario: An administrator explicitly enables repository writes
    Given an approved admin is logged in
    When a visitor opens "/chat"
    Then repository access is shown as read-only
    And the repository write control is available
    When the visitor enables repository writes
    Then repository access is shown as write enabled
    When the visitor disables repository writes
    Then repository access is shown as read-only
    When the visitor enables repository writes
    And the visitor reloads the page
    Then repository access is shown as read-only
    When the visitor enables repository writes
    And the visitor clears the chat
    Then repository access is shown as read-only

  Scenario: A child administrator remains read-only
    Given an approved child administrator is logged in
    When a visitor opens "/chat"
    Then repository access is shown as read-only
    And the repository write control is not shown
