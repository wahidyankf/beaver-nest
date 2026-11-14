Feature: Family chat room

  Background:
    Given an approved user is logged in

  Rule: Canonical route

  Scenario: A visitor is redirected from the family chat root to Ruang Keluarga
    When a visitor opens "/family-chat"
    Then the current route is "/family-chat/ruang-keluarga"
    And the page displays the heading "Ruang Keluarga"

  Scenario: A visitor opens Ruang Keluarga directly
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the page displays the heading "Ruang Keluarga"

  Rule: Online send status

  @fe-vitest-unit
  # Exemption(integration): the outbox that queues the message and reports its delivery status runs only in browser JavaScript, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A member sends a message online and sees it reach Sent
  @integration-exempt
  Scenario: A member sends a message online and sees it reach Sent
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends the family chat message "On my way"
    Then the message shows status "Sending"
    And the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(integration): a failed browser request and the outbox's own retry run only in browser JavaScript, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A network failure shows Retrying then automatic recovery
  @integration-exempt
  Scenario: A network failure shows Retrying then automatic recovery
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message during a retryable network failure
    Then the message shows status "Retrying in …"
    When the network recovers
    Then the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(integration): classifying a GraphQL rejection into a delivery status is browser outbox logic Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A non-retryable rejection shows Couldn't send
  @integration-exempt
  Scenario: A non-retryable rejection shows Couldn't send
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message the server rejects as invalid
    Then the message shows status "Couldn't send"
    And no automatic retry is attempted

  Rule: Bounded per-room outbox

  @fe-vitest-unit
  # Exemption(integration): the per-room queue lives in the browser's IndexedDB outbox, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / The 101st queued message for one room is rejected
  @integration-exempt
  Scenario: The 101st queued message for one room is rejected
    Given a visitor opens "/family-chat/ruang-keluarga"
    And the visitor's outbox for this room already holds 100 queued messages
    When the visitor attempts to queue one more message
    Then the new message is not queued
    And the composer explains the retry-or-discard remediation

  Rule: Message actions

  @fe-vitest-unit
  # Exemption(integration): each entry point is a real pointer, context-menu, or key event the server never sees; alternative-proof: bnest-app-fe-e2e:test:e2e / A member opens the message action menu
  @integration-exempt
  Scenario Outline: A member opens the message action menu
    Given a visitor opens "/family-chat/ruang-keluarga" with at least one committed message
    When the visitor <entry point> on that message
    Then the message action menu opens for that message
    And keyboard focus is inside the menu

    Examples:
      | entry point                                   |
      | presses and holds for 500 milliseconds        |
      | opens the browser context menu                |
      | activates the actions control revealed on hover |
      | moves focus to the message and presses Enter  |

  @fe-vitest-unit
  # Exemption(integration): where DOM focus lands after a menu closes is browser accessibility-tree state Phoenix.LiveViewTest never observes; alternative-proof: bnest-app-fe-e2e:test:e2e / Closing the menu returns focus to the message it came from
  @integration-exempt
  Scenario: Closing the menu returns focus to the message it came from
    Given the message action menu is open for a committed message
    When the visitor presses Escape
    Then the menu closes
    And keyboard focus is on that same message

  @fe-vitest-unit
  # Exemption(integration): a pointer press and its movement are browser input events the server never sees; alternative-proof: bnest-app-fe-e2e:test:e2e / A press that turns into a scroll does not open the menu
  @integration-exempt
  Scenario: A press that turns into a scroll does not open the menu
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor presses a message and moves more than 10 pixels before releasing
    Then no action menu opens

  @fe-vitest-unit
  # Exemption(integration): two simultaneously rendered menus are real DOM state Phoenix.LiveViewTest never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Only one menu is open at a time
  @integration-exempt
  Scenario: Only one menu is open at a time
    Given the message action menu is open for one committed message
    When the visitor opens the menu on a different message
    Then only the second message has an open menu

  @fe-vitest-unit
  # Exemption(integration): the rendered menu and its enabled items are browser DOM state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / A committed message offers both actions
  @integration-exempt
  Scenario: A committed message offers both actions
    Given a visitor opens "/family-chat/ruang-keluarga" with at least one committed message
    When the visitor opens the action menu on that message
    Then the menu offers exactly "Reply" and "Copy text"
    And both actions are available

  @fe-vitest-unit
  # Exemption(integration): a message that is not yet committed exists only in the browser outbox and its rendered menu, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message that is not yet committed cannot be replied to
  @integration-exempt
  Scenario Outline: A message that is not yet committed cannot be replied to
    Given the visitor's own message is in the "<state>" state
    When the visitor opens the action menu on it
    Then "Reply" is present and unavailable
    And the menu states that the message must send before it can be replied to
    And "Copy text" remains available

    Examples:
      | state                  |
      | Waiting for connection |
      | Sending                |
      | Retrying               |
      | Couldn't send          |

  @fe-vitest-unit
  # Exemption(integration): the action menu is rendered and enabled by browser JavaScript the server never runs; alternative-proof: bnest-app-fe-e2e:test:e2e / A system message can be replied to like any other
  @integration-exempt
  Scenario: A system message can be replied to like any other
    Given the room holds a committed system message
    When the visitor opens the action menu on it
    Then "Reply" is available

  @fe-vitest-unit
  # Exemption(integration): writing to the system clipboard is a browser API the server never reaches; alternative-proof: bnest-app-fe-e2e:test:e2e / Copying a message puts its text on the clipboard
  @integration-exempt
  Scenario: Copying a message puts its text on the clipboard
    Given the visitor opens the action menu on a message whose body is "Dinner is ready"
    When the visitor chooses "Copy text"
    Then the clipboard holds exactly "Dinner is ready"
    And the room announces that the message was copied

  @fe-vitest-unit
  # Exemption(e2e): a rejected Clipboard API promise is driven directly in the frontend Vitest+Gherkin harness, where a real browser would grant permission instead; alternative-proof: bnest-app:test:unit:fe / A refused clipboard is reported, not swallowed
  @e2e-exempt
  # Exemption(integration): a refused clipboard write is a browser API outcome the server never reaches; alternative-proof: bnest-app:test:unit:fe / A refused clipboard is reported, not swallowed
  @integration-exempt
  Scenario: A refused clipboard is reported, not swallowed
    Given the browser refuses clipboard write access
    When the visitor chooses "Copy text" on a committed message
    Then the room states that the text could not be copied
    And the menu closes

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): where keyboard focus lands after a key send is browser focus state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / A fine-pointer Enter send keeps keyboard focus in the Family composer
  @integration-exempt
  Scenario: A fine-pointer Enter send keeps keyboard focus in the Family composer
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    And the visitor's pointer is a fine pointer
    When the visitor types "Keyboard send" and presses "Enter" in the family composer
    Then keyboard focus is in the message input
    And the family room sends 1 messages

  Rule: Composing a reply

  @fe-vitest-unit
  # Exemption(integration): the composer strip and where focus lands afterwards are browser DOM and focus state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Choosing Reply puts the target above the message input
  @integration-exempt
  Scenario: Choosing Reply puts the target above the message input
    Given the visitor opens the action menu on a message from "Ayah" reading "Nanti aku jemput jam 5"
    When the visitor chooses "Reply"
    Then the composer shows a reply strip naming "Ayah"
    And the strip shows the text of that message
    And keyboard focus is in the message input
    And the room announces that the visitor is replying to "Ayah"

  @fe-vitest-unit
  # Exemption(integration): the composer's reply strip is rendered by browser JavaScript the server never runs; alternative-proof: bnest-app-fe-e2e:test:e2e / A long quoted message is shortened in the strip
  @integration-exempt
  Scenario: A long quoted message is shortened in the strip
    Given the selected message body is 400 graphemes long
    When the reply strip renders it
    Then at most 160 graphemes are shown before the ellipsis
    And the shown text ends with an ellipsis

  @fe-vitest-unit
  # Exemption(integration): the reply strip and the draft it leaves behind are browser composer state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / The member abandons the reply
  @integration-exempt
  Scenario Outline: The member abandons the reply
    Given the composer shows a reply strip
    And the visitor has typed "Oke" without sending
    When the visitor <action>
    Then the reply strip is gone
    And the message input still holds "Oke"

    Examples:
      | action                                    |
      | activates the cancel control on the strip |
      | presses Escape in the message input       |

  @fe-vitest-unit
  # Exemption(integration): a real page reload discarding unpersisted draft state requires an actual browser navigation; alternative-proof: bnest-app-fe-e2e:test:e2e / The reply target does not survive a reload
  @integration-exempt
  Scenario: The reply target does not survive a reload
    Given the composer shows a reply strip
    When the visitor reloads the page
    Then no reply strip is shown

  @fe-vitest-unit
  # Exemption(integration): the reply target is browser composer state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Sending clears the reply target
  @integration-exempt
  Scenario: Sending clears the reply target
    Given the composer shows a reply strip
    When the visitor sends the message
    Then no reply strip is shown
    And the next message the visitor sends carries no reply target

  Rule: Reading a reply

  @fe-vitest-unit
  # Exemption(integration): the four arrival paths include a live socket push and a reconnect catch-up that Phoenix.LiveViewTest cannot drive against the browser renderer; alternative-proof: bnest-app-fe-e2e:test:e2e / A reply carries its quote through each arrival path
  @integration-exempt
  Scenario Outline: A reply carries its quote through each arrival path
    Given another member has replied to one of the visitor's messages
    When the reply reaches the visitor through <path>
    Then the reply renders a quote naming the original sender
    And the quote shows the original message text

    Examples:
      | path                                    |
      | the first history page                  |
      | an older history page                   |
      | the live subscription                   |
      | reconnect catch-up after a dropped socket |

  @fe-vitest-unit
  # Exemption(integration): messages and their quotes are rendered by browser JavaScript from GraphQL results, not by a server-rendered page Phoenix.LiveViewTest observes; alternative-proof: bnest-app-fe-e2e:test:e2e / A reply to a reply shows only one level of quote
  @integration-exempt
  Scenario: A reply to a reply shows only one level of quote
    Given message A exists
    And message B is a reply to A
    When a reply to B is rendered
    Then that reply shows a quote of B
    And that quote shows no quote of its own

  @fe-vitest-unit
  # Exemption(integration): scrolling, highlighting, and moving focus to a target message are browser layout and focus state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / The original is already on screen
  @integration-exempt
  Scenario: The original is already on screen
    Given a reply and the message it quotes are both loaded
    When the visitor activates the quote
    Then the history scrolls to the original message
    And that message is highlighted
    And keyboard focus moves to it

  @fe-vitest-unit
  # Exemption(integration): loading older pages in response to a jump and landing on the target is browser paging and scroll state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / The original is above the loaded window
  @integration-exempt
  Scenario: The original is above the loaded window
    Given a reply quotes a message two older pages above the loaded window
    When the visitor activates the quote
    Then older pages are loaded until the original is present
    And the history scrolls to it

  @fe-vitest-unit
  # Exemption(integration): the jump pages older history in from the browser and announces its refusal there, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / The original is beyond the jump bound
  @integration-exempt
  Scenario: The original is beyond the jump bound
    Given a reply quotes a message more than five older pages above the loaded window
    When the visitor activates the quote
    Then no more than five older pages are requested
    And the room states that the message is too far back to jump to

  @fe-vitest-unit
  # Exemption(integration): honouring prefers-reduced-motion is a real media-query and computed-style concern only a browser resolves; alternative-proof: bnest-app-fe-e2e:test:e2e / Highlighting respects reduced motion
  @integration-exempt
  Scenario: Highlighting respects reduced motion
    Given the visitor's system requests reduced motion
    When the visitor jumps to a quoted message
    Then the message is marked without an animated pulse

  Rule: Keyboard reach of the message history

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): a end-to-end keyboard journey needs a real focus engine, which no browserless harness provides; alternative-proof: bnest-app-fe-e2e:test:e2e / The whole journey works from the keyboard alone
  @integration-exempt
  Scenario: The whole journey works from the keyboard alone
    Given a visitor opens "/family-chat/ruang-keluarga" using only a keyboard
    And the visitor's pointer is a fine pointer
    When the visitor moves focus into the history, selects a message, opens the menu, chooses "Reply", types, and sends
    Then the sent message renders a quote of the selected message
    And focus is never left on a control the visitor cannot operate

  @fe-vitest-unit
  # Exemption(integration): tab order across 50 rendered items is real focus-engine behaviour Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Tab does not walk through every message in the room
  @integration-exempt
  Scenario: Tab does not walk through every message in the room
    Given the history holds 50 messages
    When the visitor presses Tab from the control before the history
    Then focus enters the history exactly once
    And the arrow keys move between messages

  @fe-vitest-unit
  # Exemption(integration): an element's computed accessible name comes from the browser accessibility tree, which no browserless harness builds; alternative-proof: bnest-app-fe-e2e:test:e2e / A quote exposes an accessible name naming its sender
  @integration-exempt
  Scenario: A quote exposes an accessible name naming its sender
    Given a reply quoting a message from "Ayah" is rendered
    When assistive technology reads that reply
    Then the quote exposes an accessible name naming "Ayah"
    And the quote is exposed as an activatable control

  @fe-vitest-unit
  # Exemption(integration): where a focused message sits in a scrolled history is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The keys that move focus through the history bring the focused message into view
  @integration-exempt
  Scenario Outline: The keys that move focus through the history bring the focused message into view
    Given the viewport is set to "desktop 1440x900"
    And the history holds 50 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "<key>" <presses> times
    Then the focused message is inside the visible history
    And the focused message is the message with the number <number>

    Examples:
      | key     | presses | number |
      | ArrowUp | 30      | 19     |
      | Home    | 1       | 0      |

  @fe-vitest-unit
  # Exemption(integration): where the action menu opens beside a message in a scrolled history is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The action menu opened from the keyboard sits beside its message
  @integration-exempt
  Scenario: The action menu opened from the keyboard sits beside its message
    Given the viewport is set to "desktop 1440x900"
    And the history holds 50 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "ArrowUp" 30 times
    And the visitor presses "Enter"
    Then the message action menu is beside the focused message inside the screen

  @fe-vitest-unit
  # Exemption(integration): where a focused message sits in a scrolled history after an arrow key moves focus down is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The arrow keys bring a message below the window into view
  @integration-exempt
  Scenario: The arrow keys bring a message below the window into view
    Given the viewport is set to "desktop 1440x900"
    And the history holds 50 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "ArrowUp" 30 times
    And the visitor presses "ArrowDown" 15 times
    Then the focused message is inside the visible history
    And the focused message is the message with the number 34

  @fe-vitest-unit
  # Exemption(integration): where the history scrolls to the newest message after the End key moves focus is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The End key brings the newest message into view
  @integration-exempt
  Scenario: The End key brings the newest message into view
    Given the viewport is set to "desktop 1440x900"
    And the history holds 50 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "ArrowUp" 30 times
    Then the focused message is not the newest message
    And the visitor presses "End" 1 times
    Then the focused message is inside the visible history
    And the focused message is the newest message

  @fe-vitest-unit
  # Exemption(integration): the top edge of a message taller than the scrolled history is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message taller than the window shows its top when focus reaches it
  @integration-exempt
  Scenario: A message taller than the window shows its top when focus reaches it
    Given the viewport is set to "landscape 844x390"
    And the history holds 49 messages and a message taller than the window follows them
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "ArrowUp" 1 times
    Then the focused message is not the newest message
    And the visitor presses "ArrowDown" 1 times
    Then the focused message is the tall message
    And the top of the focused message is inside the visible history

  @fe-vitest-unit
  # Exemption(integration): whether a message already in view stays where it is while the history is scrolled is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message already in view does not move the history
  @integration-exempt
  Scenario: A message already in view does not move the history
    Given the viewport is set to "desktop 1440x900"
    And the history holds 50 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the history is laid out on the screen
    And the visitor presses Tab from the control before the history
    And the visitor presses "ArrowUp" 30 times
    And the history's position is noted
    And the visitor presses "ArrowDown" 1 times
    Then the focused message is inside the visible history
    And the focused message is the message with the number 20
    And the history has not moved since its position was noted

  Rule: Family Chat conversation has most of a phone screen

  @fe-vitest-unit
  # Exemption(integration): the share of the screen the history takes is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat history has most of the screen with an empty draft
  @integration-exempt
  Scenario Outline: The Family Chat history has most of the screen with an empty draft
    Given the viewport is set to "<viewport>"
    And the visitor's pointer is a touch pointer
    When a visitor opens "/family-chat/ruang-keluarga"
    And the page is laid out
    Then the history takes at least <share> percent of the screen with an empty draft

    Examples:
      | viewport          | share |
      | narrow 320x568    | 58    |
      | phone 360x640     | 62    |
      | mobile 390x844    | 75    |
      | landscape 844x390 | 52    |

  @fe-vitest-unit
  # Exemption(integration): the space above and below the history is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A typical Family Chat phone view shows the newest message above the composer
  @integration-exempt
  Scenario: A typical Family Chat phone view shows the newest message above the composer
    Given the viewport is set to "mobile 390x844"
    And the visitor's pointer is a touch pointer
    And the history holds 3 messages
    When a visitor opens "/family-chat/ruang-keluarga"
    And the page is laid out
    Then the newest message is fully above the composer
    And the header and the composer take at most 180 pixels outside the history

  Rule: Family Chat composer hint

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): the hint's visibility is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat send shortcut hint follows a fine pointer
  @integration-exempt
  Scenario Outline: The Family Chat send shortcut hint follows a fine pointer
    Given the viewport is set to "<viewport>"
    And the visitor's pointer is a fine pointer
    When a visitor opens "/family-chat/ruang-keluarga"
    And the page is laid out
    Then the send shortcut hint reads "Enter to send, Shift+Enter for a new line"

    Examples:
      | viewport         |
      | desktop 1440x900 |
      | narrow 320x568   |

  @fe-vitest-unit
  # Exemption(integration): the hint's visibility is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat send shortcut hint follows a touch pointer
  @integration-exempt
  Scenario Outline: The Family Chat send shortcut hint follows a touch pointer
    Given the viewport is set to "<viewport>"
    And the visitor's pointer is a touch pointer
    When a visitor opens "/family-chat/ruang-keluarga"
    And the page is laid out
    Then the send shortcut hint reads "Shift+Enter to send"
    And the send shortcut hint takes no row

    Examples:
      | viewport        |
      | mobile 390x844  |
      | tablet 1024x768 |

  Rule: Family Chat message box reads clearly

  @fe-vitest-unit
  # Exemption(integration): the accessible name is computed from the rendered label and its visibility, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat message box has an accessible name
  @integration-exempt
  Scenario: The Family Chat message box has an accessible name
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the page is laid out
    Then the Family Chat message box is named "Message the family"

  @fe-vitest-unit
  # Exemption(integration): the placeholder colour is painted by the browser from the stylesheet, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat message box placeholder meets the contrast target
  @integration-exempt
  Scenario: The Family Chat message box placeholder meets the contrast target
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the page is laid out
    Then the message box placeholder has at least 4.5 to 1 contrast with the box

  @fe-vitest-unit
  # Exemption(integration): the corner radii are painted by the browser from the stylesheet, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Family Chat Send button has four equal round corners
  @integration-exempt
  Scenario: The Family Chat Send button has four equal round corners
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the page is laid out
    Then the Family Chat Send button has four equal corner radii

  Rule: Single light appearance in Family Chat

  @fe-vitest-unit
  # Exemption(integration): the colour a browser paints for a system dark preference is a rendered-page result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Family Chat keeps one light appearance and has no theme control
  @integration-exempt
  Scenario: Family Chat keeps one light appearance and has no theme control
    Given the visitor's system prefers a dark color scheme
    When an approved admin opens "/family-chat/ruang-keluarga"
    Then the page has no color theme control
    And the page background is light

  Rule: Keyboard reach of message content

  @fe-vitest-unit
  # Exemption(integration): which element Tab reaches inside a rendered message is browser focus order over the DOM that browser JavaScript builds from server HTML, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Tab moves from a message into its links and opens one
  @integration-exempt
  Scenario: Tab moves from a message into its links and opens one
    Given Ayah has sent the family chat message "Dinner plan: [home](https://example.test/home) and [list](https://example.test/list)"
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "home"
    When the visitor presses "Tab"
    Then keyboard focus is on "list"
    When the visitor presses "Enter"
    Then the link "list" opens its address in a new tab
    And no action menu opens

  @fe-vitest-unit
  # Exemption(integration): the order in which Tab visits a message's links, scroll regions, and diagram source is browser focus order over the rendered DOM, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Tab and Shift+Tab pass through message content without a trap
  @integration-exempt
  Scenario: Tab and Shift+Tab pass through message content without a trap
    Given Ayah has sent this family chat message:
      """
      Dinner plan: [home](https://example.test/home)

      | Menu | Drink | Dessert | Notes | Seats |
      | ---- | ----- | ------- | ----- | ----- |
      | Nasigorengkampungspesialbuatkeluargakitasemua | Tehmanisdengansusuhangatbersamakeluarga | Kuehmangkokdaripasarpagihariinisegarsekali | Pedasnyasedanglebihenakdimakanbersama | Tigaorangdewasadanduaanakkecil |

      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    And the "table" in the message is wider than its box
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    When the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "home"
    When the visitor presses "Tab"
    Then keyboard focus is on "table"
    When the visitor presses "Tab"
    Then keyboard focus is on "Diagram source"
    When the visitor presses "Tab"
    Then keyboard focus is outside the history
    When the visitor presses "Shift+Tab"
    Then keyboard focus is on "Diagram source"
    When the visitor presses "Shift+Tab"
    Then keyboard focus is on "table"
    When the visitor presses "Shift+Tab"
    Then keyboard focus is on "home"
    When the visitor presses "Shift+Tab"
    Then keyboard focus is on the message "Dinner plan"

  @fe-vitest-unit
  # Exemption(integration): moving focus back to a message with Escape is a keydown handled on a DOM element built from server HTML, which Phoenix.LiveViewTest never dispatches; alternative-proof: bnest-app-fe-e2e:test:e2e / Escape returns focus from message content to the message
  @integration-exempt
  Scenario: Escape returns focus from message content to the message
    Given Ayah has sent the family chat message "Earlier note"
    And Ayah has sent the family chat message "Dinner plan: [home](https://example.test/home)"
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "home"
    When the visitor presses "Escape"
    Then keyboard focus is on the message "Dinner plan"
    When the visitor presses "ArrowUp"
    Then keyboard focus is on the message "Earlier note"

  @fe-vitest-unit
  # Exemption(integration): what a key does on a link, a summary, or a scroll region is the browser's own default action on DOM that browser JavaScript builds, which Phoenix.LiveViewTest never dispatches; alternative-proof: bnest-app-fe-e2e:test:e2e / Keys inside message content keep their own meaning
  @integration-exempt
  Scenario Outline: Keys inside message content keep their own meaning
    Given Ayah has sent this family chat message:
      """
      Dinner plan: [home](https://example.test/home)

      | Menu | Drink | Dessert | Notes | Seats |
      | ---- | ----- | ------- | ----- | ----- |
      | Nasigorengkampungspesialbuatkeluargakitasemua | Tehmanisdengansusuhangatbersamakeluarga | Kuehmangkokdaripasarpagihariinisegarsekali | Pedasnyasedanglebihenakdimakanbersama | Tigaorangdewasadanduaanakkecil |

      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    And the "table" in the message is wider than its box
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    When the visitor presses Tab from the control before the history
    And the visitor presses "Tab" until keyboard focus is on "<content>"
    And the visitor presses "<key>"
    Then <effect>
    And the message "Dinner plan" is the keyboard stop
    And no action menu opens

    Examples:
      | content        | key        | effect                                         |
      | home           | Enter      | the link "home" opens its address in a new tab |
      | Diagram source | Enter      | the diagram source is shown                    |
      | Diagram source | Space      | the diagram source is shown                    |
      | table          | ArrowRight | the "table" is scrolled to the right           |

  @fe-vitest-unit
  # Exemption(integration): a wide table or code block is a scroll region whose width and scroll position only a browser layout engine computes, which Phoenix.LiveViewTest never measures; alternative-proof: bnest-app-fe-e2e:test:e2e / A wide table or code block can be scrolled from the keyboard
  @integration-exempt
  Scenario Outline: A wide table or code block can be scrolled from the keyboard
    Given the viewport is set to "mobile 390x844"
    And Ayah has sent a wide "<kind>" message
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "<kind>"
    And the "<kind>" shows a visible focus ring
    When the visitor presses "ArrowRight"
    Then the "<kind>" is scrolled to the right
    And keyboard focus is on "<kind>"

    Examples:
      | kind       |
      | table      |
      | code block |

  @fe-vitest-unit
  # Exemption(integration): whether a table or code block fits its box is a browser layout result that Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A table or code block that fits is not a tab stop
  @integration-exempt
  Scenario: A table or code block that fits is not a tab stop
    Given Ayah has sent this family chat message:
      """
      Dinner plan:

      | Menu | Seats |
      | ---- | ----- |
      | Rice | 4     |

      ```text
      rice for four
      ```
      """
    And the "table" in the message fits its box
    And the "code block" in the message fits its box
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is outside the history

  @fe-vitest-unit
  # Exemption(integration): which links of fifty rendered messages Tab reaches is browser focus order over the rendered history, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Only the focused message's links are reachable
  @integration-exempt
  Scenario: Only the focused message's links are reachable
    Given the history holds 50 messages, each with a link
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "link 49"
    And exactly one link in the history is a tab stop
    When the visitor presses "Shift+Tab"
    Then keyboard focus is on the message "Note 49"
    When the visitor presses "ArrowUp"
    Then keyboard focus is on the message "Note 48"
    When the visitor presses "Tab"
    Then keyboard focus is on "link 48"

  @fe-vitest-unit
  # Exemption(integration): a message that arrives while the visitor's focus is inside the history is pushed by the GraphQL subscription and placed by browser JavaScript, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A new message keeps the focused message's content reachable
  @integration-exempt
  Scenario: A new message keeps the focused message's content reachable
    Given Ayah has sent the family chat message "Dinner plan: [home](https://example.test/home)"
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor presses Tab from the control before the history
    And Ayah sends the family chat message "Later note" while the visitor watches
    And the visitor presses "Tab"
    Then keyboard focus is on "home"
    And the message "Dinner plan" is the keyboard stop

  @fe-vitest-unit
  # Exemption(integration): opening the diagram source is a native disclosure toggle on a figure built by browser JavaScript, which Phoenix.LiveViewTest never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / The diagram source opens from the keyboard
  @integration-exempt
  Scenario: The diagram source opens from the keyboard
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    When the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "Diagram source"
    When the visitor presses "Enter"
    Then the diagram source is shown
    When the visitor presses "Tab"
    Then keyboard focus is outside the history

  @fe-vitest-unit
  # Exemption(integration): the picture's width at a 320 px viewport is a browser layout result that Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A scrolled diagram can be scrolled from the keyboard
  @integration-exempt
  Scenario: A scrolled diagram can be scrolled from the keyboard
    Given the viewport is set to "mobile 320x640"
    And Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart LR
        A[Pick up the children from the school gate] --> B[Cook dinner together at home] --> C[Eat together at the table]
      ```
      """
    And the "diagram" in the message is wider than its box
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    When the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "diagram"
    And the "diagram" shows a visible focus ring
    When the visitor presses "ArrowRight"
    Then the "diagram" is scrolled to the right
    And keyboard focus is on "diagram"

  @fe-vitest-unit
  # Exemption(integration): a reply's quote card is a button inside a bubble built by browser JavaScript, and Enter on it moves the stop in the rendered history, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / The quote card can be used from the keyboard
  @integration-exempt
  Scenario: The quote card can be used from the keyboard
    Given Ayah has sent the family chat message "Dinner plan: at seven"
    When a visitor opens "/family-chat/ruang-keluarga"
    And the visitor replies to the message with "Thanks, see you there"
    And the visitor presses Tab from the control before the history
    And the visitor presses "Tab"
    Then keyboard focus is on "quote card"
    When the visitor presses "Enter"
    Then the message "Dinner plan" is the keyboard stop

  Rule: Resume, online reaction, backoff, and seven-day expiry

  @fe-vitest-unit
  # Exemption(integration): a queue left behind by a closed tab lives in browser IndexedDB, which Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / Reopening the app resumes queued sends
  @integration-exempt
  Scenario: Reopening the app resumes queued sends
    Given the visitor has a queued message left over from a closed session
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the queued message resumes toward Sent without visitor action

  @fe-vitest-unit
  # Exemption(integration): a real IndexedDB binding surviving an actual browser reload requires a real browser storage implementation Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / A queued message survives a real browser reload while offline
  @integration-exempt
  Scenario: A queued message survives a real browser reload while offline
    Given a fresh visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message during a retryable network failure
    Then the message shows status "Retrying in …"
    When the visitor reloads the page
    Then the message is durably queued for a closed tab to resume
    When the network recovers
    Then the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(integration): the browser's online event and the outbox's retry timer exist only in the browser; alternative-proof: bnest-app-fe-e2e:test:e2e / An online event makes a retry immediately eligible
  @integration-exempt
  Scenario: An online event makes a retry immediately eligible
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a queued message is waiting on its backoff timer
    When the browser reports the "online" event
    Then the queued message becomes immediately eligible for retry

  @fe-vitest-unit
  # Exemption(integration): the retry timers run in browser JavaScript, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / Automatic retry waits follow the bounded jittered backoff sequence
  @integration-exempt
  Scenario: Automatic retry waits follow the bounded jittered backoff sequence
    Given a visitor opens "/family-chat/ruang-keluarga"
    When a queued message fails five times with a retryable result
    Then each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds

  @fe-vitest-unit
  # Exemption(integration): the queued message and its retry or discard controls live in the browser outbox, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message queued more than seven days becomes manual-only
  @integration-exempt
  Scenario: A message queued more than seven days becomes manual-only
    Given the visitor has a queued message created more than seven days ago
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the message is not automatically retried
    And the visitor can still manually retry or discard it

  @fe-vitest-unit
  # Exemption(integration): an offline browser and the IndexedDB record it queues are invisible to Phoenix.LiveViewTest; alternative-proof: bnest-app-fe-e2e:test:e2e / An offline reply queues with its target
  @integration-exempt
  Scenario: An offline reply queues with its target
    Given the visitor is offline with the room open
    When the visitor replies to a committed message
    Then the queued message shows status "Waiting for connection"
    And the queued record carries the reply target

  @fe-vitest-unit
  # Exemption(integration): surviving a closed app is browser IndexedDB durability, which Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / A queued reply survives closing the app
  @integration-exempt
  Scenario: A queued reply survives closing the app
    Given an offline reply is queued
    When the visitor reopens "/family-chat/ruang-keluarga" while still offline
    Then the queued reply is still present with its target

  @fe-vitest-unit
  # Exemption(integration): draining the browser's queue when the network returns runs only in browser JavaScript; alternative-proof: bnest-app-fe-e2e:test:e2e / A queued reply commits with its link on reconnect
  @integration-exempt
  Scenario: A queued reply commits with its link on reconnect
    Given an offline reply is queued
    When the network recovers
    Then the reply reaches status "Sent" exactly once
    And the committed message renders its quote

  @fe-vitest-unit
  # Exemption(integration): a record stored in browser IndexedDB before this feature is invisible to Phoenix.LiveViewTest; alternative-proof: bnest-app-fe-e2e:test:e2e / A queued record written before this feature still sends
  @integration-exempt
  Scenario: A queued record written before this feature still sends
    Given the outbox holds a queued message stored with no reply target field
    When the network recovers
    Then that message reaches status "Sent"
    And it commits as an ordinary message

  Rule: Auth expiry pause and logout isolation

  @fe-vitest-unit
  # Exemption(integration): pausing the drain is browser outbox state, and a second user's queue on the same device is browser storage Phoenix.LiveViewTest never sees; alternative-proof: bnest-app-fe-e2e:test:e2e / Authentication expiry pauses the queue without cross-user drain
  @integration-exempt
  Scenario: Authentication expiry pauses the queue without cross-user drain
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a message is queued
    When the visitor's authentication expires
    Then queue draining pauses for that namespace
    And no other user's session drains that queued message

  @fe-vitest-unit
  # Exemption(integration): the queue being cleared lives in browser IndexedDB, which Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / Logout clears the current user's queue
  @integration-exempt
  Scenario: Logout clears the current user's queue
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a message is queued
    When the visitor logs out
    Then the visitor's local outbox namespace is cleared
    And the current session's Web Push subscription is disabled

  Rule: Reconnect across Caddy promotion

  @fe-vitest-unit
  # Exemption(integration): holding a socket across a live Caddy config reload crosses browser and release-infrastructure boundaries that Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / A connected client reconnects to the promoted slot without a page refresh
  @integration-exempt
  Scenario: A connected client reconnects to the promoted slot without a page refresh
    Given a visitor opens "/family-chat/ruang-keluarga" with the socket connected to the current slot
    When Caddy promotes a replacement slot
    Then the prior-slot socket closes
    And the browser subscribes on the promoted slot and completes catch-up within ten seconds
    And any queued send drains only after catch-up completes
    And the page does not reload

  @fe-vitest-unit
  # Exemption(integration): serving one revision's bundle against another revision's server crosses a release-infrastructure boundary Phoenix.LiveViewTest cannot stage; alternative-proof: bnest-app-fe-e2e:test:e2e / A browser holding the pre-reply bundle loads the room from the new revision
  @integration-exempt
  Scenario: A browser holding the pre-reply bundle loads the room from the new revision
    Given the compatibility revision is routed
    When a browser loaded from the previous revision opens "/family-chat/ruang-keluarga"
    Then the room loads
    And the visitor can send a message normally

  @fe-vitest-unit
  # Exemption(integration): rolling the routed slot back beneath a browser that keeps its bundle crosses a release-infrastructure boundary Phoenix.LiveViewTest cannot stage; alternative-proof: bnest-app-fe-e2e:test:e2e / The rollback floor can still answer the reply-aware bundle
  @integration-exempt
  Scenario: The rollback floor can still answer the reply-aware bundle
    Given a visitor holds the reply-aware bundle with a reply on screen
    When the routed slot is rolled back to the compatibility revision
    And the visitor replies again with the bundle it still holds
    Then the room loads
    And existing replies still render their quotes

  Rule: Reconnect on visibility resume

  @fe-vitest-unit
  # Exemption(integration): forcing a stale connection and a real document visibility transition crosses browser and OS-lifecycle boundaries that Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / A tab backgrounded with a dead connection reconnects once it becomes visible again
  @integration-exempt
  Scenario: A tab backgrounded with a dead connection reconnects once it becomes visible again
    Given a visitor opens "/family-chat/ruang-keluarga" with the socket connected to the current slot
    When the tab is backgrounded with its connection silently dropped
    And the tab becomes visible again
    Then a fresh socket connection replaces the prior one
    And the page does not reload

  Rule: Subscription channel handshake

  @fe-vitest-unit
  # Exemption(integration): a live phx_join wire frame over a real WebSocket is not observable through Phoenix.LiveViewTest or the frontend Vitest+Gherkin harness; alternative-proof: bnest-app-fe-e2e:test:e2e / A reconnect never attempts to join the per-message subscription channel
  @integration-exempt
  @subscription-handshake
  Scenario: A reconnect never attempts to join the per-message subscription channel
    Given a visitor opens "/family-chat/ruang-keluarga" with the socket connected to the current slot
    When the tab is backgrounded with its connection silently dropped
    And the tab becomes visible again
    Then no phx_join frame is sent for any topic other than the control channel

  Rule: Experience release candidate proof

  # This scenario's two near-simultaneous authenticated first requests
  # against a freshly promoted candidate independently reproduced a real
  # production race in `StorageCoordinator.ensure_started!/1`: an unlocked
  # check-and-maybe-restart let one request tear down the Ecto repo pid a
  # concurrent request was already mid-query against. Fixed with
  # `:global.trans/2` serialization (storage_coordinator.ex); see
  # learnings.md for the reproduction evidence.
  @fe-vitest-unit
  # Exemption(integration): promoting Caddy to a flag-transitioned release candidate and driving two independent browser contexts against it crosses browser and release-infrastructure boundaries that Phoenix.LiveViewTest cannot observe; alternative-proof: bnest-app-fe-e2e:test:e2e / Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate
  @integration-exempt
  Scenario: Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate
    Given Caddy has promoted the flag-enabled experience candidate
    And two members each open "/family-chat/ruang-keluarga"
    And one member queues a message while offline
    When the offline member's connection is restored
    Then the offline member's queued message drains exactly once after reconnect
    And neither member sees a duplicate or lost message

  Rule: Resuming at the last read position

  @fe-vitest-unit
  # Exemption(integration): which message a returning visitor lands on is browser scroll state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / A returning member lands on the first message they have not read
  @integration-exempt
  Scenario: A returning member lands on the first message they have not read
    Given the family chat holds more earlier messages than one context page
    And the visitor has read the family chat up to a known message
    And 5 newer messages arrived while the visitor was away
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the first unread message is the first message in view
    And an unread marker separates the read messages from the new ones
    And one bounded page of earlier messages is loaded above the unread marker
    And older history can still be loaded on request

  @fe-vitest-unit
  # Exemption(integration): landing on the newest message is browser scroll state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / A returning member with nothing unread lands on the newest message
  @integration-exempt
  Scenario: A returning member with nothing unread lands on the newest message
    Given the visitor has read every message in the family chat
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the newest message is in view
    And no unread marker is shown

  @fe-vitest-unit
  # Exemption(integration): landing on the newest message is browser scroll state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / A member who has never opened this room lands on the newest message
  @integration-exempt
  Scenario: A member who has never opened this room lands on the newest message
    Given the visitor has never opened the family chat on this device
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the newest message is in view
    And no unread marker is shown

  @fe-vitest-unit
  # Exemption(integration): reaching the bottom of a scrollable history is browser scroll state the server never observes; alternative-proof: bnest-app-fe-e2e:test:e2e / Reading down to the newest message moves the resume point
  @integration-exempt
  Scenario: Reading down to the newest message moves the resume point
    Given the visitor has read the family chat up to a known message
    And 5 newer messages arrived while the visitor was away
    When the visitor reopens "/family-chat/ruang-keluarga"
    And the visitor scrolls down to the newest message
    And the visitor reopens "/family-chat/ruang-keluarga"
    Then the newest message is in view
    And no unread marker is shown

  @fe-vitest-unit
  # Exemption(integration): a partially loaded history and its jump control are browser-side paging state the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / More unread messages than one page still offer a way back to the newest
  @integration-exempt
  Scenario: More unread messages than one page still offer a way back to the newest
    Given the visitor left more unread messages behind than one page holds
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the first unread message is the first message in view
    And "New messages below" offers a way back to the newest message
    When the visitor jumps to the newest message
    Then the newest message is in view

  Rule: Composer focus and keyboard

  @fe-vitest-unit
  # Exemption(integration): keeping DOM focus across a send is browser accessibility-tree state Phoenix.LiveViewTest never observes; alternative-proof: bnest-app-fe-e2e:test:e2e / The composer keeps focus after a message is sent
  @integration-exempt
  Scenario: The composer keeps focus after a message is sent
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When the visitor sends "Still typing" through the composer
    Then the composer still holds keyboard focus
    And activating the send control never takes focus from the message input
    And the composer is empty and ready for the next message

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): physical keyboard chord handling belongs to the browser boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / Enter and Shift+Enter follow a fine pointer in Family Chat
  @integration-exempt
  Scenario Outline: Enter and Shift+Enter follow a fine pointer in Family Chat
    Given the viewport is set to "<viewport>"
    And the visitor's pointer is a fine pointer
    And a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When the visitor types "Keyboard send" and presses "<key>" in the family composer
    Then the family room sends <sends> messages
    And the family composer shows "<box>"

    Examples:
      | viewport         | key         | sends | box                        |
      | desktop 1440x900 | Enter       | 1     | an empty box               |
      | desktop 1440x900 | Shift+Enter | 0     | a new line after its draft |
      | narrow 320x568   | Enter       | 1     | an empty box               |
      | narrow 320x568   | Shift+Enter | 0     | a new line after its draft |

  @fe-vitest-unit
  # Exemption(integration): physical keyboard chord handling belongs to the browser boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / Enter and Shift+Enter follow a touch pointer in Family Chat
  @integration-exempt
  Scenario Outline: Enter and Shift+Enter follow a touch pointer in Family Chat
    Given the viewport is set to "<viewport>"
    And the visitor's pointer is a touch pointer
    And a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When the visitor types "Keyboard send" and presses "<key>" in the family composer
    Then the family room sends <sends> messages
    And the family composer shows "<box>"

    Examples:
      | viewport        | key         | sends | box                        |
      | mobile 390x844  | Enter       | 0     | a new line after its draft |
      | mobile 390x844  | Shift+Enter | 1     | an empty box               |
      | tablet 1024x768 | Enter       | 0     | a new line after its draft |
      | tablet 1024x768 | Shift+Enter | 1     | an empty box               |

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): an IME composition is a browser input state the server never receives; alternative-proof: bnest-app-fe-e2e:test:e2e / Enter confirming a composition does not send in Family Chat
  @integration-exempt
  Scenario: Enter confirming a composition does not send in Family Chat
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    And the visitor's pointer is a fine pointer
    And the visitor has typed "Still composing" without sending
    When the visitor confirms a composition with Enter in the family composer
    Then nothing is sent yet
    And the composer holds the draft "Still composing"

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): Safari reports its composition Enter with keyCode 229, a browser key-event detail the server never receives; alternative-proof: bnest-app-fe-e2e:test:e2e / Enter with keyCode 229 does not send in Family Chat
  @integration-exempt
  Scenario: Enter with keyCode 229 does not send in Family Chat
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    And the visitor's pointer is a fine pointer
    And the visitor has typed "Still composing" without sending
    When the visitor confirms a composition with keyCode 229 in the family composer
    Then nothing is sent yet
    And the composer holds the draft "Still composing"

  @fe-vitest-unit
  @fine-pointer
  # Exemption(integration): a held key's repeated keydown is a browser key-event detail the server never receives; alternative-proof: bnest-app-fe-e2e:test:e2e / A held Enter sends one message in Family Chat
  @integration-exempt
  Scenario: A held Enter sends one message in Family Chat
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    And the visitor's pointer is a fine pointer
    And the visitor has typed "Held send" without sending
    When the visitor holds Enter in the family composer
    Then the family room sends 1 messages

  @fe-vitest-unit
  # Exemption(integration): a Shift+Enter key chord is a browser boundary the server never receives; alternative-proof: bnest-app-fe-e2e:test:e2e / Shift+Enter does not send an empty Family Chat draft
  @integration-exempt
  Scenario: Shift+Enter does not send an empty Family Chat draft
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    And the visitor's pointer is a touch pointer
    When the visitor presses Shift+Enter with an empty draft
    Then nothing is sent yet
    And the composer is empty and ready for the next message

  @fe-vitest-unit
  # Exemption(integration): whether a sent message ends up on screen is browser scroll position the server never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Sending brings the visitor to their own message
  @integration-exempt
  Scenario: Sending brings the visitor to their own message
    Given a visitor opens "/family-chat/ruang-keluarga" scrolled to a known older message
    When the visitor sends "Down here with everyone" through the composer
    Then the visitor's own message is in view

  Rule: Scroll anchor and live-region announcements

  @fe-vitest-unit
  # Exemption(integration): measured scroll position and focus retention require a real browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / Loading older history preserves the visitor's scroll anchor
  @integration-exempt
  Scenario: Loading older history preserves the visitor's scroll anchor
    Given a visitor opens "/family-chat/ruang-keluarga" scrolled to a known older message
    When the visitor loads an older history page
    Then the previously visible message remains at the same visual position

  @fe-vitest-unit
  # Exemption(integration): live-region announcement and focus retention require a real browser accessibility tree; alternative-proof: bnest-app-fe-e2e:test:e2e / A new message announces without moving focus from the composer
  @integration-exempt
  Scenario: A new message announces without moving focus from the composer
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When another member's message arrives away from the bottom of the scroll position
    Then a live-region announcement names the new message
    And focus remains in the composer
    And "New messages below" is shown instead of auto-scrolling

  Rule: Push permission UX and no authenticated caching

  @fe-vitest-unit
  # Exemption(e2e): headless Playwright Chromium reports every notification permission as denied, always exposes Notification and PushManager, and is never an iOS browser, so it cannot present an undecided, subscribed, uninstalled, or unsupported device; alternative-proof: bnest-app:test:unit:fe / The room shows the correct push permission state
  @e2e-exempt
  # Exemption(integration): the device's notification permission, service worker, and push support are browser capabilities the server never sees; alternative-proof: bnest-app:test:unit:fe / The room shows the correct push permission state
  @integration-exempt
  Scenario Outline: The room shows the correct push permission state
    Given the visitor's device reports push state "<device state>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the room shows the control "<control text>"

    Examples:
      | device state                | control text                              |
      | available, not yet decided  | Enable notifications                      |
      | subscription active         | Notifications on                          |
      | requires installation       | Install Beaver Nest first                 |
      | unsupported                 | Notifications unavailable in this browser |

  @fe-vitest-unit
  # Exemption(integration): the device's notification permission is a browser capability the server never sees; alternative-proof: bnest-app-fe-e2e:test:e2e / The room shows that notifications are blocked
  @integration-exempt
  Scenario: The room shows that notifications are blocked
    Given the visitor's device reports push state "permission denied"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the room shows the control "Notifications blocked"

  @fe-vitest-unit
  # Exemption(e2e): headless Playwright Chromium reports the notification permission as denied, so the room never offers "Turn off" there and a subscription cannot be turned off from it; alternative-proof: bnest-app:test:unit:fe / A member disables notifications from the room
  @e2e-exempt
  # Exemption(integration): turning notifications off unsubscribes the browser's push subscription, a browser capability Phoenix.LiveViewTest never reaches; alternative-proof: bnest-app:test:unit:fe / A member disables notifications from the room
  @integration-exempt
  Scenario: A member disables notifications from the room
    Given a visitor opens "/family-chat/ruang-keluarga" with an active push subscription
    When the visitor selects "Turn off"
    Then the room shows the control "Enable notifications"

  @fe-vitest-unit
  # Exemption(integration): inspecting the service worker's Cache Storage contents requires a real browser cache implementation; alternative-proof: bnest-app-fe-e2e:test:e2e / The service worker cache stores no authenticated content
  @integration-exempt
  Scenario: The service worker cache stores no authenticated content
    Given a visitor opens "/family-chat/ruang-keluarga" and exchanges messages
    When the service worker's Cache Storage is inspected
    Then it contains only static build assets
    And it contains no navigation response, message, or GraphQL response

  Rule: Responsive and accessible presentation

  @fe-vitest-unit
  # Exemption(integration): rendered viewport geometry and zoom layout require a real browser layout engine; alternative-proof: bnest-app-fe-e2e:test:e2e / The room remains keyboard operable and free of horizontal scroll
  @integration-exempt
  Scenario Outline: The room remains keyboard operable and free of horizontal scroll
    Given the viewport is set to "<viewport>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then every control is reachable by keyboard with a visible focus indicator
    And no horizontal page scroll is present

    Examples:
      | viewport             |
      | desktop 1280x800     |
      | tablet 768x1024      |
      | mobile 393x852       |
      | desktop 1280x800 200%|

  @fe-vitest-unit
  # Exemption(integration): the page's scroll height is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The room does not scroll the whole page vertically
  @integration-exempt
  Scenario Outline: The room does not scroll the whole page vertically
    Given the viewport is set to "<viewport>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then no vertical page scroll is present

    Examples:
      | viewport          |
      | tablet 768x1024   |
      | desktop 1280x800  |
      | landscape 844x390 |

  @fe-vitest-unit
  # Exemption(integration): the header's height and the share of a short screen that the list keeps are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The conversation keeps room on a short screen
  @integration-exempt
  Scenario Outline: The conversation keeps room on a short screen
    Given the viewport is set to "<viewport>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the conversation list is at least half the viewport height
    And the message composer is on screen

    Examples:
      | viewport          |
      | landscape 844x390 |
      | short 390x422     |

  @fe-vitest-unit
  # Exemption(integration): the width a message takes is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message uses most of a narrow phone's width
  @integration-exempt
  Scenario: A message uses most of a narrow phone's width
    Given the viewport is set to "narrow 320x640"
    And Ayah has sent the family chat message "Dinner is ready at home tonight, so please come to the big table by the window"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message takes at least 80 percent of the viewport width

  @fe-vitest-unit
  # Exemption(integration): the number of lines the composer shows is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The message composer grows with a long draft and then stops at six lines
  @integration-exempt
  Scenario: The message composer grows with a long draft and then stops at six lines
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor types a draft of 12 lines into the composer
    Then the message composer is at least two lines tall
    And the message composer is at most six lines tall
    And the Send button is on screen

  @fe-vitest-unit
  # Exemption(integration): the height of the message box on a short screen is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The message composer leaves most of a short screen to the conversation
  @integration-exempt
  Scenario Outline: The message composer leaves most of a short screen to the conversation
    Given the viewport is set to "<viewport>"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor types a draft of 12 lines into the composer
    Then the message composer is at most 22 percent of the screen height

    Examples:
      | viewport          |
      | landscape 844x390 |
      | short 390x422     |

  @fe-vitest-unit
  # Exemption(integration): the place of the newest message and the list's height after a draft grows are browser layout results Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The newest message stays above the composer when the draft grows
  @integration-exempt
  Scenario Outline: The newest message stays above the composer when the draft grows
    Given the viewport is set to "<viewport>"
    And a visitor is at the bottom of the family chat conversation
    When the visitor types a draft of <lines> lines into the composer
    Then the newest message is in view above the composer

    Examples:
      | viewport          | lines |
      | mobile 390x844    | 3     |
      | landscape 844x390 | 6     |

  @fe-vitest-unit
  # Exemption(integration): the width of the room and the place of the Send button with an unbroken draft are browser layout results Phoenix.LiveViewTest never computes; this row is a regression guard, not a proof of cause; alternative-proof: bnest-app-fe-e2e:test:e2e / A long unbroken draft leaves the Family room inside the screen (a regression guard)
  @integration-exempt
  Scenario Outline: A long unbroken draft leaves the Family room inside the screen (a regression guard)
    Given the viewport is set to "<viewport>"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor types an unbroken 240 character address into the composer
    Then the Family room is inside the screen
    And the Send button is on screen and is not covered by the composer
    And no horizontal page scroll is present

    Examples:
      | viewport          |
      | narrow 320x568    |
      | mobile 390x844    |
      | landscape 844x390 |
      | tablet 768x1024   |
      | laptop 1024x768   |
      | desktop 1440x900  |

  @fe-vitest-unit
  # Exemption(integration): the colours a browser resolves from the stylesheet are part of the rendered page, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The Send button text meets the contrast target
  @integration-exempt
  Scenario: The Send button text meets the contrast target
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the Send button text has a contrast ratio of at least 4.5 to 1

  Rule: Formatted messages

  @fe-vitest-unit
  # Exemption(integration): the message body is inserted into the page by browser JavaScript from server-rendered HTML, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A committed message is shown as formatted Markdown
  @integration-exempt
  Scenario: A committed message is shown as formatted Markdown
    Given Ayah has sent the family chat message "**Dinner** is at [home](https://example.test/home)"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows "Dinner" in bold
    And the message links "home" to "https://example.test/home"

  @fe-vitest-unit
  # Exemption(integration): the escaped server HTML that must never run exists only as browser DOM after JavaScript inserts it, which Phoenix.LiveViewTest never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Raw HTML in a message is shown as text and never runs
  @integration-exempt
  Scenario: Raw HTML in a message is shown as text and never runs
    Given Ayah has sent the family chat message "<img src=x onerror=alert(1)> <script>alert(1)</script> done"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows the text "<script>alert(1)</script> done"
    And the message contains no script or image element

  @fe-vitest-unit
  # Exemption(integration): a message that is still sending exists only in the browser outbox, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message that is still sending is shown as typed
  @integration-exempt
  Scenario: A message that is still sending is shown as typed
    Given a visitor opens "/family-chat/ruang-keluarga"
    And the server holds the visitor's next message unanswered
    When the visitor sends the family chat message "**not yet** typed"
    Then the message shows status "Sending"
    And the message shows "**not yet** typed" as typed text with no formatting

  @fe-vitest-unit
  # Exemption(integration): the line breaks of a rendered message are browser DOM built from server HTML that Phoenix.LiveViewTest never observes; alternative-proof: bnest-app-fe-e2e:test:e2e / Typed line breaks in a message are kept
  @integration-exempt
  Scenario: Typed line breaks in a message are kept
    Given Ayah has sent a message typed on two lines
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message keeps its two lines on separate lines

  @fe-vitest-unit
  # Exemption(integration): an image that the browser displays from a third-party address is rendered by browser JavaScript from server HTML that Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / An https image in a message is shown inline
  @integration-exempt
  Scenario: An https image in a message is shown inline
    Given Ayah has sent the family chat message "![Garden](https://images.example.test/garden.png)"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows the image "Garden" from "https://images.example.test/garden.png"

  @fe-vitest-unit
  # Exemption(integration): a repository image is displayed from a browser request to the image route inside a message that browser JavaScript renders, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A repository image in a message is shown inline
  @integration-exempt
  Scenario: A repository image in a message is shown inline
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends the family chat message "![Beaver Nest logo](apps/bnest-app/priv/static/images/beaver-nest-logo.png)"
    Then the message shows the image "Beaver Nest logo" from "/chat/images/apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  @fe-vitest-unit
  # Exemption(integration): the message is rendered by browser JavaScript from server HTML, and the text it leaves behind is browser DOM Phoenix.LiveViewTest never observes; alternative-proof: bnest-app-fe-e2e:test:e2e / Images a message may not show stay as text
  @integration-exempt
  Scenario Outline: Images a message may not show stay as text
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends the family chat message "<message>"
    Then the message shows no image
    And the message shows the text "<text>"

    Examples:
      | message                                            | text                     |
      | ![Chart](http://example.test/chart.png)            | Chart (image not shown)  |
      | ![Icon](data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=) | [image not shown: Icon]  |
      | ![Local](javascript:alert(1))                      | [image not shown: Local] |

  @fe-vitest-unit
  # Exemption(integration): a message that arrives live is rendered by browser JavaScript from the GraphQL subscription push, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A formatted message that arrives live is formatted
  @integration-exempt
  Scenario: A formatted message that arrives live is formatted
    Given a visitor opens "/family-chat/ruang-keluarga"
    When Ayah sends the family chat message "**Live** update" while the visitor watches
    Then the message shows "Live" in bold

  @fe-vitest-unit
  # Exemption(integration): link targets are properties of the browser DOM built from server HTML, which Phoenix.LiveViewTest never renders; alternative-proof: bnest-app-fe-e2e:test:e2e / Links in a message open in a new tab
  @integration-exempt
  Scenario: Links in a message open in a new tab
    Given Ayah has sent the family chat message "[home](https://example.test/home) and [list](https://example.test/list)"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the links in the message open in a new tab

  @fe-vitest-unit
  # Exemption(integration): the width of a rendered image and table is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A wide image or table fits a phone-width message
  @integration-exempt
  Scenario: A wide image or table fits a phone-width message
    Given Ayah has sent a wide image and a wide table
    And the viewport is set to "mobile 390x844"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message fits the phone width
    And the image in the message loads

  @fe-vitest-unit
  # Exemption(integration): the clipboard holds the text of a message rendered by browser JavaScript, a browser API Phoenix.LiveViewTest never reaches; alternative-proof: bnest-app-fe-e2e:test:e2e / Copying a formatted message copies what was typed
  @integration-exempt
  Scenario: Copying a formatted message copies what was typed
    Given the visitor opens the action menu on a message whose body is "**Dinner** is at [home](https://example.test/home)"
    When the visitor chooses "Copy text"
    Then the clipboard holds exactly "**Dinner** is at [home](https://example.test/home)"

  @fe-vitest-unit
  # Exemption(integration): the reply strip and the quote card are composer and browser DOM rendered from the message text, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / Replying to a formatted message quotes plain text
  @integration-exempt
  Scenario: Replying to a formatted message quotes plain text
    Given Ayah has sent the family chat message "**Dinner** is at [home](https://example.test/home)"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor replies to the message with "Thanks"
    Then the reply quotes "**Dinner** is at [home](https://example.test/home)" as plain text
    And the quote contains no link

  @fe-vitest-unit
  # Exemption(integration): the colours a browser resolves for inline elements inside a dark own bubble are part of the rendered page, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / Inline text in my own message stays readable
  @integration-exempt
  Scenario: Inline text in my own message stays readable
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends this family chat message:
      """
      ~~struck~~ text with a [link](https://example.test/home) and `inline code`

      > a quoted line

      | Item | Cost |
      | --- | --- |
      | Bread | 2 |
      """
    Then the struck text, the link, the inline code, the quote and the table cell each have a contrast ratio of at least 4.5 to 1 on my own bubble

  Rule: Diagrams in messages

  @fe-vitest-unit
  # Exemption(integration): the diagram is drawn by browser JavaScript from server HTML with a layout only a real browser computes, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A committed message with a mermaid flowchart shows a diagram
  @integration-exempt
  Scenario: A committed message with a mermaid flowchart shows a diagram
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    And the message keeps its diagram source as text

  @fe-vitest-unit
  # Exemption(integration): the drawing attempt and its fallback note are produced by browser JavaScript after the server sends the source, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A diagram with a syntax error stays visible as source with a note
  @integration-exempt
  Scenario: A diagram with a syntax error stays visible as source with a note
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A -->
      ```
      """
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows the note "Diagram not drawn: it has a syntax error."
    And the message keeps its diagram source as text

  @fe-vitest-unit
  # Exemption(integration): a label that tries to run script is drawn or refused in the browser's own engine, where Phoenix.LiveViewTest never looks; alternative-proof: bnest-app-fe-e2e:test:e2e / Hostile diagram text in a message is inert
  @integration-exempt
  Scenario: Hostile diagram text in a message is inert
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A["<img src=x onerror=window.bnestDiagramCanary=true>"] --> B
      ```

      ```mermaid
      flowchart TD
        A --> B
        click A "https://example.test/steal"
      ```
      """
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows a diagram labelled "Flowchart"
    And the message shows the note "Diagram not drawn: it uses settings that are not allowed."
    And no script from the message runs

  @fe-vitest-unit
  # Exemption(integration): the refusal of an oversized, unsupported or surplus diagram is a browser render of server HTML that Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / An oversized, unsupported or surplus diagram in a message stays as source
  @integration-exempt
  Scenario Outline: An oversized, unsupported or surplus diagram in a message stays as source
    Given Ayah has sent the diagram message "<message>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows <drawn> drawn diagrams
    And the message shows the note "<note>"
    And the message keeps its diagram source as text

    Examples:
      | message              | drawn | note                                                                    |
      | oversized flowchart  | 0     | Diagram not drawn: it is too large.                                     |
      | unsupported diagram  | 0     | Diagram not drawn: this diagram type is not supported.                  |
      | five flowcharts      | 4     | Diagram not drawn: only the first 4 diagrams in a message are drawn.    |

  @fe-vitest-unit
  # Exemption(integration): a message that arrives while the page is open is pushed by the GraphQL subscription and drawn by browser JavaScript, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A diagram that arrives live is drawn
  @integration-exempt
  Scenario: A diagram that arrives live is drawn
    Given a visitor opens "/family-chat/ruang-keluarga"
    When Ayah sends this family chat message while the visitor watches:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    Then the message shows a diagram labelled "Flowchart"

  @fe-vitest-unit
  # Exemption(integration): the typed text of a message still in the browser outbox exists only in browser DOM, which Phoenix.LiveViewTest never executes; alternative-proof: bnest-app-fe-e2e:test:e2e / A message that is still sending shows its diagram source as typed
  @integration-exempt
  Scenario: A message that is still sending shows its diagram source as typed
    Given a visitor opens "/family-chat/ruang-keluarga"
    And the server holds the visitor's next message unanswered
    When the visitor sends this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    Then the message shows status "Sending"
    And the message shows the diagram source as typed text with no drawing

  @fe-vitest-unit
  # Exemption(integration): the drawing engine is requested and fails in the browser, a boundary Phoenix.LiveViewTest never reaches; alternative-proof: bnest-app-fe-e2e:test:e2e / A diagram stays as source when the diagram engine cannot load
  @integration-exempt
  Scenario: A diagram stays as source when the diagram engine cannot load
    Given the diagram engine cannot be loaded
    And Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the message shows the note "Diagram not drawn: the diagram tool did not load."
    And the message keeps its diagram source as text

  @fe-vitest-unit
  # Exemption(integration): tab order across a rendered picture is browser focus state built from the drawing, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A diagram in another message adds no tab stop to the history
  @integration-exempt
  Scenario: A diagram in another message adds no tab stop to the history
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    And Ayah has sent the family chat message "Dinner is ready"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the diagram message shows a diagram labelled "Flowchart"
    And the diagram message adds no tab stop

  @fe-vitest-unit
  # Exemption(integration): the clipboard and the reply quote hold the text of a message rendered by browser JavaScript, which Phoenix.LiveViewTest never reaches; alternative-proof: bnest-app-fe-e2e:test:e2e / Copying or replying to a message with a diagram uses the typed Markdown
  @integration-exempt
  Scenario: Copying or replying to a message with a diagram uses the typed Markdown
    Given Ayah has sent this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor opens the action menu on that message
    And the visitor chooses "Copy text"
    Then the clipboard holds the message as typed
    When the visitor replies to the message with "Thanks"
    Then the reply quotes the typed message as plain text

  @fe-vitest-unit
  # Exemption(integration): the picture's width and its surface colour are computed by the browser's layout and stylesheet, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A narrow diagram is readable on the own message bubble and fits a 320 px message
  @integration-exempt
  Scenario: A narrow diagram is readable on the own message bubble and fits a 320 px message
    Given the viewport is set to "mobile 320x640"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends this family chat message:
      """
      ```mermaid
      flowchart TD
        A[Pick up] --> B[Dinner]
      ```
      """
    Then the message shows a diagram labelled "Flowchart"
    And the drawn diagram sits on its own paper surface in the own bubble
    And the diagram fits the message bubble
    And no horizontal page scroll is present

  @fe-vitest-unit
  # Exemption(integration): the picture's width against its box is computed by the browser's layout, which Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A wide diagram keeps a readable size and scrolls inside its own box at 320 px
  @integration-exempt
  Scenario: A wide diagram keeps a readable size and scrolls inside its own box at 320 px
    Given the viewport is set to "mobile 320x640"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends this family chat message:
      """
      ```mermaid
      flowchart LR
        A[Pick up the children from the school gate] --> B[Cook dinner together at home] --> C[Eat together at the table]
      ```
      """
    Then the message shows a diagram labelled "Flowchart"
    And the diagram keeps a readable size
    And the diagram scrolls inside its own box
    And no horizontal page scroll is present

  @fe-vitest-unit
  # Exemption(integration): the place a room scrolls to after a diagram is drawn is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / The newest message stays in view when a diagram draws
  @integration-exempt
  Scenario: The newest message stays in view when a diagram draws
    Given a visitor is at the bottom of the family chat conversation
    And Ayah has sent a family chat message with a mermaid flowchart that is not yet drawn
    When the diagram is drawn
    Then the newest message is in view above the composer

  @fe-vitest-unit
  # Exemption(integration): the width of a bubble around a drawn diagram is a browser layout result Phoenix.LiveViewTest never computes; alternative-proof: bnest-app-fe-e2e:test:e2e / A wide diagram in a message uses most of a desktop column
  @integration-exempt
  Scenario Outline: A wide diagram in a message uses most of a desktop column
    Given the viewport is set to "<viewport>"
    And a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends this family chat message:
      """
      ```mermaid
      flowchart LR
        A[Pick up the children from the school gate] --> B[Cook dinner together at home] --> C[Eat together at the table]
      ```
      """
    Then the message shows a diagram labelled "Flowchart"
    And the diagram bubble takes at least 80 percent of the message list width

    Examples:
      | viewport          |
      | tablet 768x1024   |
      | desktop 1024x768  |
      | desktop 1440x900  |
