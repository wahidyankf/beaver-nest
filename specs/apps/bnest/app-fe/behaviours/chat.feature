Feature: Beaver Nest chat

  Rule: Public application installation

  Scenario: A visitor can install Beaver Nest as an app
    When a visitor opens "/"
    Then the page displays the Beaver Nest logo
    And Beaver Nest is ready to install as an app

  Rule: Authenticated user-owned chat

    Background:
      Given an approved admin is logged in

  Scenario: The home page offers a Start chatting link
    When a visitor opens "/"
    Then the page displays the heading "Beaver Nest"
    And the page offers the "Start chatting" link to "/chat"

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
    And the model selector lists only "GPT-6.1-Sol, GPT-6.1 Terra, GPT-6-Luna"
    And the selected model is "GPT-6.1 Terra"
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
    And the visitor's pointer is a touch pointer
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

  Scenario Outline: A visitor changes the model or the reasoning effort within one Codex conversation
    Given a visitor opens "/chat"
    When the visitor sends "Before <setting> switch"
    And a Codex response appears incrementally
    When the visitor selects the reasoning effort "High"
    And the visitor selects the model "<model>"
    Then the selected model is "<model>"
    And the reasoning effort selector lists every effort supported by the selected model
    And the selected reasoning effort is "High"
    And the conversation displays the visitor message "Before <setting> switch"
    When the visitor sends "After <setting> switch"
    Then the conversation displays the visitor message "After <setting> switch"
    And a Codex response appears incrementally
    And the conversation displays a second Codex response

    Examples:
      | setting | model         |
      | model   | GPT-6-Luna    |
      | effort  | GPT-6.1 Terra |

  Scenario: A model change falls back to Max from an unsupported reasoning effort
    Given a visitor opens "/chat"
    When the visitor selects the reasoning effort "Ultra"
    And the visitor selects the model "GPT-6-Luna"
    Then the selected model is "GPT-6-Luna"
    And the reasoning effort selector lists every effort supported by the selected model
    And the selected reasoning effort is "Max"

  Scenario Outline: A visitor sees an alert when Codex cannot take or finish a message
    Given a visitor opens "/chat"
    When <cause>
    Then the page displays the alert "<alert>"
    And the message composer is available

    Examples:
      | cause                                                                                | alert                   |
      | Codex rejects the visitor message "Are you there?"                                   | Codex is not available. |
      | Codex fails the visitor message "Please fail this turn" with the error "Turn failed." | Turn failed.            |

  # Exemption(integration): automatic socket recovery crosses the browser and routed server boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / An automatic LiveView reconnect preserves a completed user-owned conversation and Codex session
  @integration-exempt
  Scenario: An automatic LiveView reconnect preserves a completed user-owned conversation and Codex session
    Given a visitor opens "/chat"
    When the visitor selects the model "GPT-6-Luna"
    And the visitor selects the reasoning effort "High"
    And the visitor sends "Temporary message"
    And a Codex response appears incrementally
    And the visitor types "Unsent draft" without sending
    When the visitor reconnects after a deployment
    Then the current route is "/chat"
    And the message composer contains "Unsent draft"
    Then the selected model is "GPT-6-Luna"
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

  @live-socket-drop
  Scenario Outline: After a dropped connection, a resumed reply shows its later text and diagram without a reload
    Given a visitor opens "/chat"
    When the visitor sends "<message>"
    And Codex streams the first part of the reply
    And the visitor's live connection drops and returns
    Then the current route is "/chat"
    And the latest Codex reply is still streaming
    When Codex streams the rest of the reply
    Then the latest Codex reply is complete
    And <late>
    And the message composer is available

    Examples:
      | message                          | late                                                               |
      | Resume after reconnect           | the latest Codex reply shows the text "Fixture response complete." |
      | Resume a diagram after reconnect | the latest Codex reply marks the diagram for drawing               |

  # Exemption(integration): concurrent browser isolation and recovery require real browser contexts; alternative-proof: bnest-app-fe-e2e:test:e2e / Ten synthetic visitors preserve recoverable state across three groups
  @integration-exempt
  Scenario: Ten synthetic visitors preserve recoverable state across three groups
    Given 10 synthetic visitors across 3 recovery groups have distinct drafts on "/chat"
    When every recovery-group visitor reconnects after a deployment
    Then every recovery-group visitor keeps its route and draft

  Scenario: A visitor clears the chat and starts a new conversation
    Given a visitor opens "/chat"
    When the visitor selects the model "GPT-6-Luna"
    And the visitor selects the reasoning effort "High"
    And the visitor sends "Old session marker"
    And a Codex response appears incrementally
    When the visitor clears the chat
    Then the conversation is empty
    And the selected model is "GPT-6-Luna"
    And the selected reasoning effort is "High"
    And the message composer is available
    When the visitor sends "Fresh start"
    Then the conversation displays the visitor message "Fresh start"
    And a Codex response appears incrementally
    And the conversation does not display the visitor message "Old session marker"

  Rule: Role-scoped Codex access

  Scenario Outline: A child, or a child administrator, is limited to read-only Luna at medium effort
    Given an approved <role> is logged in
    When a visitor opens "/chat"
    Then the page displays the text "Luna · medium"
    And repository access is shown as read-only
    And the repository write control is not shown
    And the selected model is "GPT-6-Luna"
    And the selected reasoning effort is "Medium"
    And the model selector is not shown
    And the reasoning effort selector is not shown
    And the chat controls do not overlap
    And the message composer is available

    Examples:
      | role                |
      | child               |
      | child administrator |

  Scenario: A parent chooses Luna or Terra at medium effort
    Given an approved parent is logged in
    When a visitor opens "/chat"
    Then the page displays the text "Terra · medium"
    And repository access is shown as read-only
    And the repository write control is not shown
    And the selected model is "GPT-6.1 Terra"
    And the selected reasoning effort is "Medium"
    And the model selector lists only "GPT-6.1 Terra, GPT-6-Luna"
    And the model selector is available
    And the reasoning effort selector is not shown
    When the visitor selects the model "GPT-6-Luna"
    Then the page displays the text "Luna · medium"
    And the selected model is "GPT-6-Luna"
    And the selected reasoning effort is "Medium"
    And the reasoning effort selector is not shown

  Scenario: An administrator turns repository writes on and off
    Given an approved admin is logged in
    When a visitor opens "/chat"
    Then repository access is shown as read-only
    And the repository write control is available
    When the visitor enables repository writes
    Then repository access is shown as write enabled
    When the visitor disables repository writes
    Then repository access is shown as read-only

  Scenario Outline: Repository access returns to read-only after a reload or after clearing the chat
    Given an approved admin is logged in
    When a visitor opens "/chat"
    And the visitor enables repository writes
    And the visitor <reset>
    Then repository access is shown as read-only

    Examples:
      | reset            |
      | reloads the page |
      | clears the chat  |

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

  @remote-image
  Scenario: Codex reply tables, task lists, links and images keep their layout
    Given a visitor opens "/chat"
    When the visitor sends "Lay out a sample reply with a remote image"
    Then a Codex response appears incrementally
    And the latest Codex reply lays out its table, task list, link and image inside the bubble
    And the latest Codex reply loads the inline image "Remote logo" from "https://images.example.test/remote-logo.png"
    And the latest Codex reply holds a wide table and an image

  Rule: Codex reply diagrams

  Scenario: A streaming Codex reply shows the diagram source until the reply is complete
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Stream a diagram"
    And Codex streams the first part of the reply
    Then the latest Codex reply is still streaming
    And the latest Codex reply keeps the diagram as a plain code block
    And the latest Codex reply does not mark a diagram for drawing
    When Codex streams the rest of the reply
    Then the latest Codex reply is complete
    And the latest Codex reply marks the diagram for drawing

  Scenario: An oversized diagram stays as source with a note
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show oversized, unsupported and surplus diagrams"
    And a Codex response appears incrementally
    Then the latest Codex reply shows the text "Diagram not drawn: it is too large."

  Scenario: An unsupported diagram type stays as source with a note
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show oversized, unsupported and surplus diagrams"
    And a Codex response appears incrementally
    Then the latest Codex reply shows the text "Diagram not drawn: this diagram type is not supported."

  Scenario: Diagrams beyond the first four in a message stay as source with a note
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show oversized, unsupported and surplus diagrams"
    And a Codex response appears incrementally
    Then the latest Codex reply shows the text "Diagram not drawn: only the first 4 diagrams in a message are drawn."
    And the latest Codex reply keeps 3 diagrams as plain code blocks
    And the latest Codex reply marks 4 diagrams for drawing

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex flowchart is drawn as a picture
    Given a completed Codex reply marks a flowchart for drawing
    When the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"
    And the diagram source "A --> B" is kept as text
    And the picture loads nothing from another origin

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex diagram with a syntax error stays visible as source with a note
    Given a completed Codex reply marks a flowchart with a syntax error for drawing
    When the browser draws the marked diagrams
    Then the diagram shows the note "Diagram not drawn: it has a syntax error."
    And the diagram source "A -->" is kept as text

  @fe-vitest-unit @codex-diagram
  Scenario: Hostile Codex diagram text is inert
    Given a completed Codex reply holds hostile diagram text
    When the browser draws the marked diagrams
    Then no script or event handler from the diagram text runs
    And the picture loads nothing from another origin
    And the diagram text shows as text only

  @fe-vitest-unit @codex-diagram
  Scenario: A diagram that carries settings is not drawn and shows a note
    Given a completed Codex reply holds hostile diagram text
    When the browser draws the marked diagrams
    Then the diagram with shape data is not drawn and shows the note that settings are not allowed

  @fe-vitest-unit @codex-diagram
  Scenario: A drawn diagram stays drawn and keeps its source open when the conversation grows
    Given a completed Codex reply shows a drawn flowchart with its source open
    When a later reply changes the conversation
    Then the picture is still shown and not redrawn
    And the diagram source is still open
    And the conversation holds 1 flowchart picture

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex diagram stays as source when the diagram engine cannot load
    Given the diagram engine cannot be loaded
    And a completed Codex reply marks a flowchart for drawing
    When the browser draws the marked diagrams
    Then the diagram shows the note "Diagram not drawn: the diagram tool did not load."
    And the diagram source "A --> B" is kept as text

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex diagram draws after the diagram engine starts on a later try
    Given the first start of the diagram engine fails
    And a completed Codex reply marks a flowchart for drawing
    When the browser draws the marked diagrams
    Then the diagram shows the note "Diagram not drawn: the diagram tool did not load."
    When the diagram engine retry window has passed
    And a later reply marks a flowchart for drawing
    And the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"

  @fe-vitest-unit @codex-diagram
  Scenario: Clearing the Codex chat removes its diagrams and the next reply draws again
    Given a completed Codex reply shows a drawn flowchart
    When the visitor clears the chat in the browser
    Then no diagram picture remains
    When a later reply marks a flowchart for drawing
    And the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"

  @fe-vitest-unit @codex-diagram
  Scenario: A narrow Codex diagram fits a 320 pixel bubble
    Given a completed Codex reply marks a flowchart for drawing
    When the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"
    And the picture fits its own box at 320 pixels

  @fe-vitest-unit @codex-diagram
  Scenario: A wide Codex diagram keeps a readable size and scrolls inside its own box
    Given a completed Codex reply marks a wide flowchart for drawing
    When the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"
    And the picture keeps a readable size at 320 pixels
    And the picture scrolls inside its own box at 320 pixels

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex diagram draws again offline after it was drawn once
    Given a completed Codex reply marks a flowchart for drawing
    When the browser draws the marked diagrams
    And the network is cut
    And the browser draws the same flowchart again
    Then the diagram engine stays available
    And the picture is labelled "Flowchart"

  @fe-vitest-unit @codex-diagram
  Scenario: A Codex chat without a diagram does not load the diagram engine
    Given a completed Codex reply has no diagram
    When the chat page loads
    Then the diagram engine was not requested

  @fe-vitest-unit @codex-diagram
  Scenario: The largest allowed Codex flowchart is drawn within the time budget
    Given a completed Codex reply marks the largest allowed flowchart for drawing
    When the browser draws the marked diagrams
    Then the picture is labelled "Flowchart"
    And the largest allowed flowchart is drawn within the draw time limit

  Rule: Codex message box keys follow the visitor's pointer, never the screen size

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: Enter and Shift+Enter follow the visitor's pointer, not the screen size
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a <pointer> pointer
    And the Codex message box holds "Keyboard send"
    When the visitor presses "<key>" in the Codex message box
    Then Codex receives <sends> message sends
    And the message box shows "<box>"

    Examples:
      | pointer | viewport         | key         | sends | box                        |
      | fine    | desktop 1440x900 | Enter       | 1     | an empty box               |
      | fine    | desktop 1440x900 | Shift+Enter | 0     | a new line after its draft |
      | fine    | narrow 320x568   | Enter       | 1     | an empty box               |
      | fine    | narrow 320x568   | Shift+Enter | 0     | a new line after its draft |
      | touch   | mobile 390x844   | Enter       | 0     | a new line after its draft |
      | touch   | mobile 390x844   | Shift+Enter | 1     | an empty box               |
      | touch   | tablet 1024x768  | Enter       | 0     | a new line after its draft |
      | touch   | tablet 1024x768  | Shift+Enter | 1     | an empty box               |

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: A filled draft is sent once, and a blank, whitespace or busy draft is never sent
    Given the Codex message box has keyboard focus
    And the visitor's pointer is a <pointer> pointer
    And the Codex message box holds <draft>
    And Codex is "<state>"
    When the visitor presses "<key>" in the Codex message box
    Then Codex receives <sends> message sends

    Examples:
      | pointer | draft           | state    | key         | sends |
      | fine    | "Keyboard send" | idle     | Enter       | 1     |
      | fine    | ""              | idle     | Enter       | 0     |
      | fine    | "   "           | idle     | Enter       | 0     |
      | fine    | "Keyboard send" | replying | Enter       | 0     |
      | touch   | "Keyboard send" | idle     | Shift+Enter | 1     |
      | touch   | ""              | idle     | Shift+Enter | 0     |
      | touch   | "Keyboard send" | replying | Shift+Enter | 0     |

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: Keyboard focus stays in the Codex message box after a reply
    Given the Codex message box has keyboard focus
    And the visitor's pointer is a <pointer> pointer
    And the Codex message box holds "Keyboard send"
    When the visitor <send>
    Then Codex receives 1 message sends
    And Codex finishes the reply
    And keyboard focus is in the Codex message box

    Examples:
      | pointer | send                                     |
      | fine    | presses "Enter" in the Codex message box |
      | touch   | presses Send with a pointer              |
      | fine    | presses Send with a pointer              |

  @fe-vitest-unit
  # Exemption(e2e): the box is read-only before a browser test can type into it, so the moments between Send and the read-only state cannot be held open deterministically; alternative-proof: bnest-app:test:unit:fe / Text typed straight after Send stays in the Codex message box
  @e2e-exempt
  # Exemption(integration): the text a visitor types while a send is still on its way is browser input state the server never renders; alternative-proof: bnest-app:test:unit:fe / Text typed straight after Send stays in the Codex message box
  @integration-exempt
  Scenario: Text typed straight after Send stays in the Codex message box
    Given the Codex message box has keyboard focus
    And the visitor's pointer is a touch pointer
    And the Codex message box holds "Keyboard send"
    When the visitor presses Send with a pointer
    And the visitor types " and more" in the Codex message box before the reply lands
    And Codex finishes the reply
    Then the Codex message box keeps " and more"

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: A confirmed composition never sends in the Codex message box
    Given the Codex message box has keyboard focus
    And the visitor's pointer is a <pointer> pointer
    And the Codex message box holds "Compose"
    When the visitor confirms a composition with "<key>" in the Codex message box
    Then nothing is sent to Codex

    Examples:
      | pointer | key         |
      | fine    | Enter       |
      | fine    | Shift+Enter |
      | touch   | Enter       |
      | touch   | Shift+Enter |

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: The Codex send shortcut hint follows the visitor's pointer
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a <pointer> pointer
    When the page is laid out
    Then the send shortcut hint reads "<hint>"
    And the send shortcut hint <check>

    Examples:
      | pointer | viewport         | hint                                      | check                                            |
      | fine    | desktop 1440x900 | Enter to send, Shift+Enter for a new line | has at least 4.5 to 1 contrast with the composer |
      | fine    | narrow 320x568   | Enter to send, Shift+Enter for a new line | has at least 4.5 to 1 contrast with the composer |
      | touch   | mobile 390x844   | Shift+Enter to send                       | takes no row                                     |
      | touch   | tablet 1024x768  | Shift+Enter to send                       | takes no row                                     |

  @fe-vitest-unit
  @fine-pointer
  Scenario: The Codex message box follows a pointer change while the page is open
    Given the Codex chat page is open at "tablet 1024x768"
    And the visitor's pointer is a fine pointer
    And the Codex message box holds "Keyboard send"
    When the visitor connects a touch pointer
    And the visitor presses "Shift+Enter" in the Codex message box
    Then Codex receives 1 message sends
    And the send shortcut hint reads "Shift+Enter to send"

  Rule: Codex message box and Send button look and line up as one composer

  @fe-vitest-unit
  Scenario Outline: The Send button lines up with the message box
    Given the Codex chat page is open at "<viewport>"
    When the page is laid out
    Then the Send button's top and bottom edges are within 1 pixel of the message box's

    Examples:
      | viewport          |
      | narrow 320x568    |
      | mobile 390x844    |
      | landscape 844x390 |
      | desktop 1440x900  |

  @fe-vitest-unit
  Scenario: The Codex message box has no resize handle
    Given the Codex chat page is open at "mobile 390x844"
    When the page is laid out
    Then the Codex message box has no resize handle

  @fe-vitest-unit
  Scenario: The Codex message box placeholder meets the contrast target
    Given the Codex chat page is open at "mobile 390x844"
    When the page is laid out
    Then the Codex message box placeholder has at least 4.5 to 1 contrast with the box

  @fe-vitest-unit
  Scenario: The Codex Send button and the Family Chat Send button share one colour
    Given the Codex chat page is open at "mobile 390x844"
    When the page is laid out
    Then the Codex Send button has the same background as the Family Chat Send button
    And the Codex Send button text meets the contrast target

  @fe-vitest-unit
  Scenario: The Codex Send button has four equal round corners that match the Family Chat Send button
    Given the Codex chat page is open at "mobile 390x844"
    When the page is laid out
    Then the Codex Send button has four equal corner radii
    And the Codex Send button has the same corner radius as the Family Chat Send button

  Rule: Clear chat asks before it deletes

  @fe-vitest-unit
  Scenario: Clear chat asks for confirmation before it deletes the conversation
    Given the Codex conversation holds "First message"
    When the visitor chooses Clear chat
    Then the confirmation asks "Delete all messages?"
    And the confirmation offers "Yes, delete" and "Cancel"
    And the conversation still shows "First message"
    And nothing is cleared yet

  @fe-vitest-unit
  Scenario Outline: Cancel, Escape and tabbing away keep the conversation
    Given the Codex conversation holds "First message"
    And the visitor has chosen Clear chat
    When the visitor <action>
    Then the confirmation is closed
    And the conversation still shows "First message"
    And nothing is cleared yet

    Examples:
      | action                       |
      | chooses Cancel               |
      | presses Escape               |
      | tabs out of the confirmation |

  @fe-vitest-unit
  Scenario: The confirmation takes focus and cancel returns focus to Clear chat
    Given the Codex conversation holds "First message"
    When the visitor chooses Clear chat
    Then keyboard focus is on the confirmation's Cancel button
    When the visitor chooses Cancel
    Then keyboard focus is on the Clear chat button

  @fe-vitest-unit
  Scenario: Confirming clears the conversation
    Given the Codex conversation holds "First message"
    When the visitor chooses Clear chat
    And the visitor chooses Yes, delete
    Then the conversation shows no messages
    And keyboard focus is on the Clear chat button

  @fe-vitest-unit
  Scenario: Escape with focus outside the confirmation closes it and leaves focus where it is
    Given the Codex conversation holds "First message"
    And the visitor has chosen Clear chat
    When the visitor moves focus to the message box
    And the visitor presses Escape
    Then the confirmation is closed
    And keyboard focus is on the message box

  @fe-vitest-unit
  Scenario: Reopening the options panel shows no stale Clear chat question
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    And the Codex conversation holds "First message"
    When the visitor opens the Codex options panel
    And the visitor chooses Clear chat
    And the visitor taps the message box
    Then the Codex options panel is closed
    And the confirmation is closed
    When the visitor opens the Codex options panel
    Then the confirmation is closed

  @fe-vitest-unit
  Scenario Outline: The Clear chat confirmation fits a narrow screen with 44 pixel targets
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    And the Codex conversation holds "First message"
    When the visitor chooses Clear chat
    And the page is laid out
    Then the confirmation is on screen without scrolling the page
    And each confirmation button is at least 44 pixels tall and across
    And the confirmation is no wider than the screen
    And the confirmation stays inside the Codex card

    Examples:
      | viewport          |
      | narrow 320x568    |
      | mobile 390x844    |
      | landscape 844x240 |

  Rule: Own messages in the Codex chat

  @fe-vitest-unit
  Scenario: A visitor's message renders Markdown and can show its raw text
    Given a visitor's message with Markdown is in the Codex conversation
    When the page is laid out
    Then the visitor's message shows its Markdown rendered
    And the visitor's message has a "Show raw" control of at least 44 pixels
    When the visitor chooses "Show raw" on the visitor's message
    Then the visitor's message shows the exact typed text
    And the control reads "Show rendered"
    When the visitor chooses "Show rendered" on the visitor's message
    Then the visitor's message shows its Markdown rendered

  @fe-vitest-unit
  Scenario: The Show raw control reads on the dark visitor bubble
    Given a visitor's message with Markdown is in the Codex conversation
    When the page is laid out
    Then the Show raw label is at least 4.5 to 1 against the visitor's bubble
    And the Show raw focus ring is at least 3 to 1 against the visitor's bubble

  @fe-vitest-unit
  Scenario: The raw view of a hostile visitor's message shows text, not HTML
    Given a visitor's message with script and javascript link text is in the Codex conversation
    When the page is laid out
    And the visitor chooses "Show raw" on the visitor's message
    Then the visitor's message shows the exact typed text
    And the visitor's message contains no script element
    And the visitor's message contains no javascript link

  @fe-vitest-unit
  Scenario: The raw view keeps the typed line breaks and spaces
    Given a visitor's message with line breaks and indentation is in the Codex conversation
    When the page is laid out
    And the visitor chooses "Show raw" on the visitor's message
    Then the visitor's message keeps the typed line breaks and spaces

  Rule: Single light appearance

  @fe-vitest-unit
  Scenario Outline: The home page and Codex chat keep one light appearance and have no theme control
    Given the visitor's system prefers a dark color scheme
    When an approved admin opens "<path>"
    Then the page has no color theme control
    And the page background is light

    Examples:
      | path  |
      | /     |
      | /chat |

  Rule: Codex chat conversation has most of a phone screen

  @fe-vitest-unit
  Scenario Outline: The Codex conversation has most of the screen with an empty draft
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the page is laid out
    Then the conversation takes at least <share> percent of the screen with an empty draft

    Examples:
      | viewport          | share |
      | narrow 320x568    | 60    |
      | phone 360x640     | 64    |
      | mobile 390x844    | 72    |
      | landscape 844x390 | 52    |

  @fe-vitest-unit
  Scenario: A typical Codex phone view shows the newest message above the composer
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    And a Codex conversation holds three short messages
    When the page is laid out
    Then the newest message is fully above the composer
    And the header and the composer take at most 220 pixels outside the conversation

  Rule: Codex chat on touch and short screens

  @fe-vitest-unit
  Scenario: The Codex header controls are at least 44 pixels tall on a touch screen
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    When the page is laid out
    Then the header controls are at least 44 pixels tall
    And the options button is at least 44 pixels across and tall

  @fe-vitest-unit
  Scenario: The Codex composer text is 16 pixels on a touch screen
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    When the page is laid out
    Then the message composer text is 16 pixels

  @fe-vitest-unit
  Scenario: Codex tables and code blocks show that they scroll
    Given the Codex chat page is open at "mobile 390x844"
    And a Codex reply answers "Show a wide table, a long code block and the logo"
    When the page is laid out
    Then the wide table and the code block show a scroll cue

  @fe-vitest-unit
  Scenario: A long Codex code block scrolls inside a height limit
    Given the Codex chat page is open at "landscape 844x390"
    And a Codex reply answers "Show a wide table, a long code block and the logo"
    When the page is laid out
    Then the code block is no taller than 384 pixels and scrolls

  @fe-vitest-unit
  Scenario: A Codex picture fits a short screen
    Given the Codex chat page is open at "landscape 844x390"
    And a Codex reply answers "Show a wide table, a long code block and the logo"
    When the page is laid out
    Then the logo is no taller than 70 percent of the screen height

  @fe-vitest-unit
  Scenario: The Codex diagram source is at least 44 pixels tall on a touch screen
    Given the visitor's pointer is a touch pointer
    And a completed Codex reply shows a drawn flowchart
    When the page is laid out
    Then the diagram source summary is at least 44 pixels tall

  @fe-vitest-unit
  Scenario Outline: Codex links, tables, code blocks and diagram sources show the room's coral focus ring
    Given the Codex chat page is open at "mobile 390x844"
    And <reply>
    When the page is laid out
    Then <focus>

    Examples:
      | reply                                                                      | focus                                                                 |
      | a Codex reply answers "Show a wide table, a long code block and the logo"  | a focused link shows the coral focus ring                             |
      | a Codex reply answers "Show a wide table, a long code block and the logo"  | a focused table and a focused code block show the coral focus ring    |
      | a completed Codex reply shows a drawn flowchart                            | a focused diagram source shows the coral focus ring                   |

  @fe-vitest-unit @remote-image
  Scenario: A Codex reply does not overflow the phone width
    Given the Codex chat page is open at "mobile 390x844"
    And a Codex reply answers "Lay out a sample reply with a remote image"
    When the page is laid out
    Then the page does not overflow horizontally at 390 pixels

  @fe-vitest-unit
  Scenario Outline: The Codex header is compact on a phone
    Given the Codex chat page is open at "<viewport>"
    When the page is laid out
    Then the Codex header has at most two rows
    And the Codex header is at most 110 pixels tall
    And the header holds the brand, the repository access state and the options button
    And the brand link is not covered by any header control
    And the repository access state and the model badge are visible without opening Options

    Examples:
      | viewport          |
      | narrow 320x568    |
      | phone 360x640     |
      | mobile 390x844    |
      | landscape 844x390 |

  @fe-vitest-unit
  Scenario Outline: The Codex header's tab order follows the screen
    Given the Codex chat page is open at "<viewport>"
    When the page is laid out
    Then the header's tab order follows the screen: brand, Options, access state, model badge

    Examples:
      | viewport          |
      | narrow 320x568    |
      | phone 360x640     |
      | mobile 390x844    |
      | landscape 844x390 |

  @fe-vitest-unit
  @fine-pointer
  Scenario Outline: The Clear chat button fills on hover only for a fine pointer
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a <pointer> pointer
    When the page is laid out
    Then the Clear chat button <hover>

    Examples:
      | pointer | hover                  |
      | touch   | does not fill on hover |
      | fine    | fills on hover         |

  @fe-vitest-unit
  Scenario Outline: The Codex options panel holds the model, the effort and Clear chat
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the visitor opens the Codex options panel
    And the page is laid out
    Then the model selector is on screen in the options panel
    And the reasoning effort selector is on screen in the options panel
    And the Clear chat control is on screen in the options panel
    And the options panel is no wider than the screen
    And every options panel control is at least 44 pixels tall
    And the options panel has no fade over its controls
    And the options panel does not cover the repository access state

    Examples:
      | viewport          |
      | narrow 320x568    |
      | mobile 390x844    |
      | landscape 844x390 |

  @fe-vitest-unit
  Scenario Outline: The Codex options panel keeps 12 pixels from the screen edge on a phone
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the visitor opens the Codex options panel
    And the page is laid out
    Then the options panel keeps 12 pixels from the right edge of the screen

    Examples:
      | viewport       |
      | narrow 320x568 |
      | mobile 390x844 |

  @fe-vitest-unit
  Scenario Outline: The home page keeps a gap between the header and the hero card
    When the home page is open at "<viewport>"
    Then the header keeps a gap above the hero card

    Examples:
      | viewport       |
      | narrow 320x568 |
      | mobile 390x844 |

  @fe-vitest-unit
  Scenario Outline: The Codex options panel closes on Escape and on a tap outside it
    Given the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    When the visitor opens the Codex options panel
    And the visitor <action>
    Then the Codex options panel is closed
    And the Options button reports it is closed

    Examples:
      | action               |
      | presses Escape       |
      | taps the message box |

  @fe-vitest-unit
  Scenario Outline: The Codex repository access state is visible without scrolling the header
    Given the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    And repository writes are "<writes>"
    When the page is laid out
    Then the repository access state is visible without scrolling the header
    And the repository write toggle is at least 44 pixels tall

    Examples:
      | viewport          | writes    |
      | narrow 320x568    | read-only |
      | narrow 320x568    | enabled   |
      | phone 360x640     | read-only |
      | phone 360x640     | enabled   |
      | mobile 390x844    | read-only |
      | mobile 390x844    | enabled   |
      | landscape 844x390 | read-only |
      | landscape 844x390 | enabled   |

  @fe-vitest-unit
  Scenario: The Codex message box keeps its name when the window is short
    Given the Codex chat page is open at "landscape 844x390"
    When the page is laid out
    Then the message box is named "Message"
    And the visible Message label takes no space in the composer

  Rule: Codex chat follows the newest message and fits every screen

  @fe-vitest-unit
  # Exemption(integration): where a conversation is scrolled is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex conversation opens at its newest message
  @integration-exempt
  Scenario: The Codex conversation opens at its newest message
    Given the visitor has a Codex conversation with older replies
    When the visitor opens the Codex chat page
    Then the newest reply is at the bottom of the conversation

  @fe-vitest-unit
  # Exemption(integration): the scroll position while a reply streams is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex conversation follows a new reply
  @integration-exempt
  Scenario: The Codex conversation follows a new reply
    Given the visitor is at the bottom of the Codex conversation
    When the visitor sends a message and Codex streams the reply
    Then the newest part of the reply is in view

  @fe-vitest-unit
  # Exemption(integration): the scroll position of a reader who scrolled up is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex conversation keeps a reader who scrolled up in place
  @integration-exempt
  Scenario: The Codex conversation keeps a reader who scrolled up in place
    Given the visitor has sent a message and Codex is still streaming its reply
    And the visitor has scrolled up in the Codex conversation
    When Codex streams more of the reply
    Then the visitor's position in the conversation does not change

  @fe-vitest-unit
  # Exemption(integration): a diagram's drawn height and the scroll position after it are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex conversation keeps its newest reply in view when a diagram draws
  @integration-exempt
  Scenario: The Codex conversation keeps its newest reply in view when a diagram draws
    Given the visitor is at the bottom of the Codex conversation
    And a Codex reply holds a diagram that is not yet drawn
    When the diagram is drawn
    Then the newest reply is in view above the composer

  @fe-vitest-unit
  # Exemption(integration): the heights of the header, the conversation and the composer are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex composer and most of the conversation fit a small phone
  @integration-exempt
  Scenario Outline: The Codex composer and most of the conversation fit a small phone
    Given the Codex chat page is open at "<viewport>"
    And a Codex reply answers "Show a wide table, a long code block and the logo"
    When the page is laid out
    Then the message composer is on screen without scrolling the page
    And the Codex header keeps its controls on wrapping rows
    And the conversation takes at least 40 percent of the screen on a small phone
    And the Send button is beside the message box
    And the Codex header keeps its controls on a small phone

    Examples:
      | viewport          |
      | narrow 320x568    |
      | phone 375x667     |
      | mobile 390x844    |

  @fe-vitest-unit
  # Exemption(integration): the height of the panel and the scrolling of the conversation are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex panel fits the window on a tablet, a landscape phone and a desktop
  @integration-exempt
  Scenario Outline: The Codex panel fits the window on a tablet, a landscape phone and a desktop
    Given the Codex chat page is open at "<viewport>"
    And the conversation holds three long Codex replies
    When the page is laid out
    Then the Codex panel is no taller than the window
    And the conversation scrolls inside the panel

    Examples:
      | viewport          |
      | tablet 768x1024   |
      | landscape 844x390 |
      | desktop 1440x900  |

  @fe-vitest-unit
  # Exemption(integration): the width of a bubble around a drawn diagram is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A wide Codex diagram uses the width of a desktop column
  @integration-exempt
  Scenario Outline: A wide Codex diagram uses the width of a desktop column
    Given the Codex chat page is open at "<viewport>"
    And a completed Codex reply shows a drawn flowchart
    When the page is laid out
    Then the reply bubble takes at least 80 percent of the conversation width

    Examples:
      | viewport          |
      | desktop 1024x768  |
      | desktop 1440x900  |

  @fe-vitest-unit
  # Exemption(integration): the accessible names of scroll regions are read from the rendered page, which Phoenix.LiveViewTest never builds; alternative-proof: bnest-app-fe-e2e:test:e2e / Codex scrollable tables and code blocks are named as in Family Chat
  @integration-exempt
  Scenario: Codex scrollable tables and code blocks are named as in Family Chat
    Given the Codex chat page is open at "mobile 390x844"
    And a Codex reply answers "Show a wide table, a long code block and the logo"
    When the page is laid out
    Then the wide table is named "Table, scrollable"
    And the wide code block is named "Code, scrollable"

  @fe-vitest-unit
  # Exemption(integration): the colours a browser paints for a button are part of the rendered page, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The repository write toggle text meets the contrast target
  @integration-exempt
  Scenario: The repository write toggle text meets the contrast target
    Given the Codex chat page is open at "desktop 1440x900"
    When the page is laid out
    Then the repository write toggle text has a contrast ratio of at least 4.5 to 1

  @fe-vitest-unit
  # Exemption(integration): the width of the chat panel and the place of the Send button with an unbroken draft are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A long unbroken draft keeps the Codex chat inside the screen
  @integration-exempt
  Scenario Outline: A long unbroken draft keeps the Codex chat inside the screen
    Given the Codex chat page is open at "<viewport>"
    When the visitor types an unbroken 240 character address into the Codex message box
    And the page is laid out
    Then the Codex chat panel is inside the screen
    And the Send button is on screen and is not covered by the message box
    And the Codex page does not scroll sideways

    Examples:
      | viewport          |
      | narrow 320x568    |
      | phone 390x844     |
      | landscape 844x390 |
      | tablet 768x1024   |
      | laptop 1024x768   |
      | desktop 1440x900  |

  Rule: Codex header and composer stay in place while the messages scroll

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): where the header and the composer sit while a long conversation scrolls is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex header and composer stay in place while the messages scroll
  @integration-exempt
  Scenario Outline: The Codex header and composer stay in place while the messages scroll
    Given a Codex conversation holds 30 messages
    And the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a <pointer> pointer
    And the newest Codex message ends above the composer
    When the visitor scrolls the Codex conversation to the middle
    Then the Codex header is at the top of the screen
    And the Codex composer is at the bottom of the screen
    And the page does not scroll

    Examples:
      | pointer | viewport          |
      | touch   | narrow 320x568    |
      | touch   | mobile 360x740    |
      | touch   | mobile 390x844    |
      | touch   | landscape 844x390 |
      | touch   | tablet 768x1024   |
      | fine    | desktop 1280x800  |
      | fine    | desktop 1440x900  |

  @fe-vitest-unit
  # Exemption(integration): whether the newest message clears the composer is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The last Codex message is not hidden behind the composer
  @integration-exempt
  Scenario Outline: The last Codex message is not hidden behind the composer
    Given a Codex conversation holds 30 messages
    And the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the page is laid out
    Then the newest Codex message ends above the composer

    Examples:
      | viewport          |
      | narrow 320x568    |
      | mobile 390x844    |
      | landscape 844x390 |

  @fe-vitest-unit
  # Exemption(integration): whether the message list keeps its overscroll to itself is a browser scroll behaviour Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Codex message list keeps its overscroll inside itself
  @integration-exempt
  Scenario: The Codex message list keeps its overscroll inside itself
    Given a Codex conversation holds 30 messages
    And the Codex chat page is open at "mobile 390x844"
    And the visitor's pointer is a touch pointer
    When the visitor scrolls the Codex conversation to the middle
    Then the Codex message list keeps its overscroll inside itself
    And the page does not scroll

  @fe-vitest-unit
  # Exemption(integration): how far the message box grows, and where Send and the header sit, are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A long Codex draft grows the message box to its cap and keeps Send and the header on screen
  @integration-exempt
  Scenario Outline: A long Codex draft grows the message box to its cap and keeps Send and the header on screen
    Given a Codex conversation holds 30 messages
    And the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the visitor types a draft of <lines> lines into the Codex message box
    And the page is laid out
    Then the Codex message box is at least two lines tall
    And the Codex message box is no taller than 5 lines
    And the message box stops at its height cap and scrolls the rest of the draft
    And the Send button and the Codex header are on screen
    And the newest Codex message ends above the composer
    And the conversation is at least 25 percent of the screen height

    Examples:
      | viewport          | lines |
      | narrow 320x568    | 6     |
      | landscape 844x390 | 6     |
      | mobile 390x844    | 14    |

  @fe-vitest-unit
  # Exemption(integration): where the composer and the newest message sit after the soft keyboard shrinks the screen are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A smaller screen from the soft keyboard keeps the Codex composer on screen
  @integration-exempt
  Scenario Outline: A smaller screen from the soft keyboard keeps the Codex composer on screen
    Given a Codex conversation holds 30 messages
    And the Codex chat page is open at "<viewport>"
    And the visitor's pointer is a touch pointer
    When the soft keyboard shrinks the screen to "<shrunk>"
    Then the Codex composer is at the bottom of the screen
    And the newest Codex message ends above the composer
    And the Codex header is at the top of the screen
    And the Codex header keeps its full height and its controls stay inside it
    And the Codex room fills the visible area above the keyboard

    Examples:
      | viewport          | shrunk  |
      | mobile 390x844    | 390x430 |
      | landscape 844x390 | 844x240 |

  Rule: Codex reply images

  Scenario: A Codex reply shows an image from the repository
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show the repository logo"
    And a Codex response appears incrementally
    Then the latest Codex reply shows the repository image "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  @remote-image
  Scenario: External https and small inline images in a Codex reply are shown
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show external and inline images"
    And a Codex response appears incrementally
    Then the latest Codex reply loads the inline image "Remote logo" from "https://images.example.test/remote-logo.png"
    And the latest Codex reply shows an inline image with the alt text "Inline dot"

  Scenario: A Codex reply keeps http, svg and oversized images as text
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Show http, svg and oversized images"
    And a Codex response appears incrementally
    Then the latest Codex reply contains no "img" element
    And the latest Codex reply links "Plain logo (image not shown)" to "http://images.example.test/plain-logo.png"
    And the latest Codex reply shows the text "[image not shown: Vector logo]"
    And the latest Codex reply shows the text "[image not shown: Long logo]"

  @remote-image
  Scenario: A half-written image address in a streaming reply is not shown as an image
    Given an approved admin is logged in
    And a visitor opens "/chat"
    When the visitor sends "Stream a half-written image"
    And Codex streams the first part of the reply
    Then the latest Codex reply is still streaming
    And the latest Codex reply contains no "img" element
    And the latest Codex reply shows the text "Remote logo"
    When Codex streams the rest of the reply
    Then the latest Codex reply is complete
    And the latest Codex reply loads the inline image "Remote logo" from "https://images.example.test/remote-logo.png"

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
