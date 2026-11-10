Feature: Beaver Nest chat

  Rule: Public application installation

  # Exemption(integration): browser installability is not observable without a browser; alternative-proof: bnest-app-fe-e2e:test:e2e / A visitor can install Beaver Nest as an app
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

  # Exemption(integration): rendered geometry is not observable without a browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / Home controls and content remain visually separated
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

  # Exemption(integration): physical keyboard chord handling belongs to the browser boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / A visitor sends a message with Shift+Enter
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

  # Exemption(integration): automatic socket recovery crosses the browser and routed server boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / An automatic LiveView reconnect preserves a completed user-owned conversation and Codex session
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

  # Exemption(integration): automatic socket recovery crosses the browser and routed server boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / An automatic LiveView reconnect safely restores a persisted in-progress user-owned turn
  @integration-exempt
  Scenario: An automatic LiveView reconnect safely restores a persisted in-progress user-owned turn
    Given a visitor opens "/chat"
    When the visitor sends "Resume after deployment"
    And the visitor reconnects after a deployment
    Then the current route is "/chat"
    And the conversation displays the visitor message "Resume after deployment"
    And the in-progress turn resumes once or fails safely without duplication
    Then the message composer is available

  # Exemption(integration): concurrent browser isolation and recovery require real browser contexts; alternative-proof: bnest-app-fe-e2e:test:e2e / Ten synthetic visitors preserve recoverable state across three groups
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

  Rule: Formatted Codex replies

    Background:
      Given an approved admin is logged in

  Scenario: Codex replies are formatted as Markdown
    Given a visitor opens "/chat"
    When the visitor sends "Format a sample reply"
    Then a Codex response appears incrementally
    And the latest Codex reply contains a "h2" element with the text "Formatted heading"
    And the latest Codex reply contains a "strong" element with the text "bold"
    And the latest Codex reply contains a "em" element with the text "italic"
    And the latest Codex reply contains a "code" element with the text "inline code"
    And the latest Codex reply contains a "li" element with the text "First item"
    And the latest Codex reply shows two checked and two unchecked task checkboxes
    And the latest Codex reply contains a "li" element with the text "Done task"
    And the latest Codex reply contains a "table" element with the text "Cell"
    And the latest Codex reply contains a "blockquote" element with the text "A quoted note"
    And the latest Codex reply contains a "pre" element with the text "IO.puts"
    And the latest Codex reply contains a "del" element with the text "Old"

  Scenario: A Codex reply stays readable while its Markdown is unfinished
    Given a visitor opens "/chat"
    When the visitor sends "Stream unfinished Markdown"
    And Codex streams the first part of the reply
    Then the latest Codex reply is still streaming
    And the latest Codex reply contains a "strong" element with the text "bol"
    And the latest Codex reply does not contain the text "**"
    When Codex streams the rest of the reply
    Then the latest Codex reply is complete
    And the latest Codex reply contains a "strong" element with the text "bold text"

  Scenario: Raw HTML in a Codex reply is shown as text and never runs
    Given a visitor opens "/chat"
    When the visitor sends "Reply with raw HTML"
    And a Codex response appears incrementally
    Then the latest Codex reply contains a "strong" element with the text "Safe bold"
    And the latest Codex reply shows the text "<script>alert(1)</script>"
    And the latest Codex reply contains no "script" element
    And the latest Codex reply contains no "img" element

  Scenario: Unsafe links in a Codex reply are not clickable
    Given a visitor opens "/chat"
    When the visitor sends "Reply with unsafe links"
    And a Codex response appears incrementally
    Then the latest Codex reply contains a "strong" element with the text "Still bold"
    And the latest Codex reply shows the text "Unsafe link" without a link
    And the latest Codex reply has no link whose address starts with "javascript:"

  Scenario: Links in a Codex reply open in a new tab without sharing the page
    Given a visitor opens "/chat"
    When the visitor sends "Reply with a safe link"
    And a Codex response appears incrementally
    Then the latest Codex reply links "Beaver Nest docs" to "https://example.com/docs"
    And the link "Beaver Nest docs" in the latest Codex reply opens in a new tab without sharing the page

  Scenario: A visitor message is shown as typed and is not formatted
    Given a visitor opens "/chat"
    When the visitor sends the two-line message "Keep **these** stars" and "and this line"
    Then the conversation displays the two-line visitor message "Keep **these** stars" and "and this line"
    And the visitor message "Keep **these** stars" shows no formatting
    And the visitor message keeps its line break between "Keep **these** stars" and "and this line"

  # Exemption(integration): rendered layout is not observable without a browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / Codex reply tables, task lists, links and images keep their layout
  @integration-exempt
  Scenario: Codex reply tables, task lists, links and images keep their layout
    Given a visitor opens "/chat"
    When the visitor sends "Format a sample reply"
    Then a Codex response appears incrementally
    And the latest Codex reply lays out its table, task list, link and image inside the bubble

  Rule: Codex reply images

  Scenario: A Codex reply shows an image from the repository
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show the repository logo"
    And a Codex response appears incrementally
    Then the latest Codex reply shows the repository image "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  Scenario: External and inline images in a Codex reply are not loaded
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show external and inline images"
    And a Codex response appears incrementally
    Then the latest Codex reply contains no "img" element
    And the latest Codex reply links "Remote logo (image not shown)" to "https://example.com/remote-logo.png"
    And the latest Codex reply shows the text "[image not shown: Inline dot]"

  Scenario: A signed-in visitor can fetch a repository image
    Given an approved admin is logged in
    When the visitor requests the repository image "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
    Then the image response has status 200
    And the image response has content type "image/png"

  Scenario: A signed-out visitor cannot fetch a repository image
    Given a visitor has no authenticated Bnest session
    When the visitor requests the repository image "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
    Then the image response redirects to "/login"

  # Exemption(e2e): the browser suite serves the real checkout and must not place files beside it or outside it; alternative-proof: bnest-app:test:integration / A repository image path that leaves the repository is refused
  @e2e-exempt
  Scenario: A repository image path that leaves the repository is refused
    Given an approved admin is logged in
    And the repository holds an image at "../secret.png"
    And the repository holds an image at "/etc/hosts.png"
    And the repository holds an image at "apps/bnest-app/../../../secret.png"
    When the visitor requests the repository image "../secret.png"
    Then the image response is an empty not found response
    When the visitor requests the repository image "/etc/hosts.png"
    Then the image response is an empty not found response
    When the visitor requests the repository image "apps/bnest-app/../../../secret.png"
    Then the image response is an empty not found response

  # Exemption(e2e): the browser suite serves the real checkout and must not place files in it; alternative-proof: bnest-app:test:integration / Hidden and runtime-data locations are refused
  @e2e-exempt
  Scenario: Hidden and runtime-data locations are refused
    Given an approved admin is logged in
    And the repository holds an image at ".env/beaver-nest-logo.png"
    And the repository holds an image at ".git/config.png"
    And the repository holds an image at "data/test-user-probe/beaver-nest-logo.png"
    And the repository holds an image at "Data/prod/beaver-nest-logo.png"
    When the visitor requests the repository image ".env/beaver-nest-logo.png"
    Then the image response is an empty not found response
    When the visitor requests the repository image ".git/config.png"
    Then the image response is an empty not found response
    When the visitor requests the repository image "data/test-user-probe/beaver-nest-logo.png"
    Then the image response is an empty not found response
    When the visitor requests the repository image "Data/prod/beaver-nest-logo.png"
    Then the image response is an empty not found response

  # Exemption(e2e): the browser suite serves the real checkout and must not place a non-image file in it; alternative-proof: bnest-app:test:integration / A file that is not a raster image is refused
  @e2e-exempt
  Scenario: A file that is not a raster image is refused
    Given an approved admin is logged in
    And the repository holds a file "docs/not-an-image.png" with the content "<html><script>alert(1)</script></html>"
    When the visitor requests the repository image "docs/not-an-image.png"
    Then the image response is an empty not found response

  # Exemption(e2e): the browser suite serves the real checkout and must not place a symbolic link in it; alternative-proof: bnest-app:test:integration / A repository image behind a symbolic link is refused
  @e2e-exempt
  Scenario: A repository image behind a symbolic link is refused
    Given an approved admin is logged in
    And the repository holds a symbolic link "docs/linked-logo.png" to "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
    When the visitor requests the repository image "docs/linked-logo.png"
    Then the image response is an empty not found response

  # Exemption(e2e): the browser suite serves the real checkout and must not write a file larger than the limit into it; alternative-proof: bnest-app:test:integration / A repository image over the size limit is refused
  @e2e-exempt
  Scenario: A repository image over the size limit is refused
    Given an approved admin is logged in
    And the repository holds a file "docs/too-large.png" of 5242881 bytes
    When the visitor requests the repository image "docs/too-large.png"
    Then the image response is an empty not found response
