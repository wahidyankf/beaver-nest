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
  # Exemption(e2e): queue/status-transition logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A member sends a message online and sees it reach Sent
  @e2e-exempt
  Scenario: A member sends a message online and sees it reach Sent
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends the family chat message "On my way"
    Then the message shows status "Sending"
    And the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(e2e): retry/backoff transition logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A network failure shows Retrying then automatic recovery
  @e2e-exempt
  Scenario: A network failure shows Retrying then automatic recovery
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message during a retryable network failure
    Then the message shows status "Retrying in …"
    When the network recovers
    Then the message reaches status "Sent"

  @fe-vitest-unit
  # Exemption(e2e): terminal-failure classification logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A non-retryable rejection shows Couldn't send
  @e2e-exempt
  Scenario: A non-retryable rejection shows Couldn't send
    Given a visitor opens "/family-chat/ruang-keluarga"
    When the visitor sends a family chat message the server rejects as invalid
    Then the message shows status "Couldn't send"
    And no automatic retry is attempted

  Rule: Bounded per-room outbox

  @fe-vitest-unit
  # Exemption(e2e): the bounded-queue cap is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / The 101st queued message for one room is rejected
  @e2e-exempt
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
  # Exemption(e2e): the hold timer and its movement tolerance are pointer-event arithmetic already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A press that turns into a scroll does not open the menu
  @e2e-exempt
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
  # Exemption(e2e): availability follows from the queued message's delivery state, which the frontend Vitest+Gherkin harness already drives directly; alternative-proof: bnest-app:test:unit:fe / A message that is not yet committed cannot be replied to
  @e2e-exempt
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
  # Exemption(e2e): no sender kind is special-cased, which is a menu-state decision the frontend Vitest+Gherkin harness already covers; alternative-proof: bnest-app:test:unit:fe / A system message can be replied to like any other
  @e2e-exempt
  Scenario: A system message can be replied to like any other
    Given the room holds a committed system message
    When the visitor opens the action menu on it
    Then "Reply" is available

  @fe-vitest-unit
  # Exemption(e2e): clipboard writing is exercised against a stubbed Clipboard API in the frontend Vitest+Gherkin harness, which observes the exact written value; alternative-proof: bnest-app:test:unit:fe / Copying a message puts its text on the clipboard
  @e2e-exempt
  Scenario: Copying a message puts its text on the clipboard
    Given the visitor opens the action menu on a message whose body is "Dinner is ready"
    When the visitor chooses "Copy text"
    Then the clipboard holds exactly "Dinner is ready"
    And the room announces that the message was copied

  @fe-vitest-unit
  # Exemption(e2e): a rejected Clipboard API promise is driven directly in the frontend Vitest+Gherkin harness, where a real browser would grant permission instead; alternative-proof: bnest-app:test:unit:fe / A refused clipboard is reported, not swallowed
  @e2e-exempt
  Scenario: A refused clipboard is reported, not swallowed
    Given the browser refuses clipboard write access
    When the visitor chooses "Copy text" on a committed message
    Then the room states that the text could not be copied
    And the menu closes

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
  # Exemption(e2e): the strip renders the server's bounded preview, and the frontend Vitest+Gherkin harness observes the rendered string directly; alternative-proof: bnest-app:test:unit:fe / A long quoted message is shortened in the strip
  @e2e-exempt
  Scenario: A long quoted message is shortened in the strip
    Given the selected message body is 400 graphemes long
    When the reply strip renders it
    Then at most 160 graphemes are shown
    And the shown text ends with an ellipsis

  @fe-vitest-unit
  # Exemption(e2e): cancelling a reply target is composer state transition logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / The member abandons the reply
  @e2e-exempt
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
  # Exemption(e2e): clearing the target on successful queueing is composer lifecycle logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / Sending clears the reply target
  @e2e-exempt
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
  # Exemption(e2e): flat rendering is a renderer decision the frontend Vitest+Gherkin harness observes directly in the produced markup; alternative-proof: bnest-app:test:unit:fe / A reply to a reply shows only one level of quote
  @e2e-exempt
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
  # Exemption(e2e): the five-page bound and its refusal are paging arithmetic the frontend Vitest+Gherkin harness counts directly; alternative-proof: bnest-app:test:unit:fe / The original is beyond the jump bound
  @e2e-exempt
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
  # Exemption(integration): a end-to-end keyboard journey needs a real focus engine, which no browserless harness provides; alternative-proof: bnest-app-fe-e2e:test:e2e / The whole journey works from the keyboard alone
  @integration-exempt
  Scenario: The whole journey works from the keyboard alone
    Given a visitor opens "/family-chat/ruang-keluarga" using only a keyboard
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

  Rule: Resume, online reaction, backoff, and seven-day expiry

  @fe-vitest-unit
  # Exemption(e2e): resume-on-open queue draining is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Reopening the app resumes queued sends
  @e2e-exempt
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
  # Exemption(e2e): online-event backoff-eligibility logic is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / An online event makes a retry immediately eligible
  @e2e-exempt
  Scenario: An online event makes a retry immediately eligible
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a queued message is waiting on its backoff timer
    When the browser reports the "online" event
    Then the queued message becomes immediately eligible for retry

  @fe-vitest-unit
  # Exemption(e2e): the exact backoff/jitter timing formula is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Automatic retry waits follow the bounded jittered backoff sequence
  @e2e-exempt
  Scenario: Automatic retry waits follow the bounded jittered backoff sequence
    Given a visitor opens "/family-chat/ruang-keluarga"
    When a queued message fails five times with a retryable result
    Then each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds

  @fe-vitest-unit
  # Exemption(e2e): the seven-day auto-retry cutoff is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A message queued more than seven days becomes manual-only
  @e2e-exempt
  Scenario: A message queued more than seven days becomes manual-only
    Given the visitor has a queued message created more than seven days ago
    When the visitor reopens "/family-chat/ruang-keluarga"
    Then the message is not automatically retried
    And the visitor can still manually retry or discard it

  @fe-vitest-unit
  # Exemption(e2e): queue admission and the stored record shape are outbox logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / An offline reply queues with its target
  @e2e-exempt
  Scenario: An offline reply queues with its target
    Given the visitor is offline with the room open
    When the visitor replies to a committed message
    Then the queued message shows status "Waiting for connection"
    And the queued record carries the reply target

  @fe-vitest-unit
  # Exemption(e2e): durable queue state across a closed session is persistence logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / A queued reply survives closing the app
  @e2e-exempt
  Scenario: A queued reply survives closing the app
    Given an offline reply is queued
    When the visitor reopens "/family-chat/ruang-keluarga" while still offline
    Then the queued reply is still present with its target

  @fe-vitest-unit
  # Exemption(e2e): drain-on-reconnect is queue transition logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / A queued reply commits with its link on reconnect
  @e2e-exempt
  Scenario: A queued reply commits with its link on reconnect
    Given an offline reply is queued
    When the network recovers
    Then the reply reaches status "Sent" exactly once
    And the committed message renders its quote

  @fe-vitest-unit
  # Exemption(e2e): hydrating a record stored without the new field is persistence-compatibility logic the frontend Vitest+Gherkin harness already drives; alternative-proof: bnest-app:test:unit:fe / A queued record written before this feature still sends
  @e2e-exempt
  Scenario: A queued record written before this feature still sends
    Given the outbox holds a queued message stored with no reply target field
    When the network recovers
    Then that message reaches status "Sent"
    And it commits as an ordinary message

  Rule: Auth expiry pause and logout isolation

  @fe-vitest-unit
  # Exemption(e2e): per-namespace pause-on-expiry isolation is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Authentication expiry pauses the queue without cross-user drain
  @e2e-exempt
  Scenario: Authentication expiry pauses the queue without cross-user drain
    Given a visitor opens "/family-chat/ruang-keluarga"
    And a message is queued
    When the visitor's authentication expires
    Then queue draining pauses for that namespace
    And no other user's session drains that queued message

  @fe-vitest-unit
  # Exemption(e2e): logout namespace-clearing and subscription disabling are already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / Logout clears the current user's queue
  @e2e-exempt
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
  # Exemption(integration): physical keyboard chord handling belongs to the browser boundary; alternative-proof: bnest-app-fe-e2e:test:e2e / Enter sends and Shift+Enter keeps writing
  @integration-exempt
  Scenario: Enter sends and Shift+Enter keeps writing
    Given a visitor opens "/family-chat/ruang-keluarga" with focus in the composer
    When the visitor submits "Sent with Enter" with the Enter key
    Then the composer still holds keyboard focus
    And the composer is empty and ready for the next message
    When the visitor presses Shift and Enter while writing "Second line"
    Then the composer holds an unsent multi-line draft

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
  # Exemption(e2e): the device-state-to-control-text mapping is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / The room shows the correct push permission state
  @e2e-exempt
  Scenario Outline: The room shows the correct push permission state
    Given the visitor's device reports push state "<device state>"
    When a visitor opens "/family-chat/ruang-keluarga"
    Then the room shows the control "<control text>"

    Examples:
      | device state                | control text                              |
      | available, not yet decided  | Enable notifications                      |
      | subscription active         | Notifications on                          |
      | permission denied           | Notifications blocked                     |
      | requires installation       | Install Beaver Nest first                 |
      | unsupported                 | Notifications unavailable in this browser |

  @fe-vitest-unit
  # Exemption(e2e): the disable-subscription control-text transition is already exercised without a browser through the frontend Vitest+Gherkin harness; alternative-proof: bnest-app:test:unit:fe / A member disables notifications from the room
  @e2e-exempt
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
