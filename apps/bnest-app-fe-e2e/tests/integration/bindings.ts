// Integration-level bindings of the app-fe behaviour corpus. Each `@scenario` line binds one scenario to the
// integration level declared in `policies.behaviour.levels.integration` of repo-config.yml. tools/run-integration.mts
// reads these lines and runs exactly the named scenarios through the existing browser steps in tests/steps, against a
// primary server started locally on loopback.

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A member sends a message online and sees it reach Sent
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A network failure shows Retrying then automatic recovery
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A non-retryable rejection shows Couldn't send
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A 101st waiting message in one room is refused with a retry-or-discard hint
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A member opens the message action menu
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Closing the menu returns focus to the message it came from
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A press that turns into a scroll does not open the menu
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Only one menu is open at a time
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A committed message offers both actions
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The actions control is visible, large enough to press, beside its bubble and inside the history
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The actions control has an accessible name
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Holding a message to open its menu clears the text the browser selects during the press
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message that is not yet committed cannot be replied to
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A system message can be replied to like any other
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Copying a message puts its text on the clipboard
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A fine-pointer Enter send keeps keyboard focus in the Family composer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A waiting message stays waiting after sign-in expires and is never sent by another member
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Logging out discards the member's waiting messages
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Logging out turns off push notifications for this device session
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The composer keeps focus after a message is sent
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Enter and Shift+Enter follow the pointer in Family Chat
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Enter that confirms a composition does not send in Family Chat
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A held Enter sends one message in Family Chat
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Shift+Enter does not send an empty Family Chat draft
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Sending brings the visitor to their own message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat send shortcut hint follows the pointer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Choosing Reply puts the target above the message input
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Typing right after choosing Reply reaches the message input
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A long quoted message is shortened in the strip
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The member abandons the reply
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The reply target does not survive a reload
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Sending clears the reply target
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat history has most of the screen with an empty draft
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The newest message is fully above the composer on a phone
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The header and the composer leave most of a phone screen to the history
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat header and composer stay in place while the messages scroll
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The last Family Chat message is not hidden behind the composer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat message list keeps its overscroll inside itself
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat header and composer stay in place with a fine pointer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A long Family Chat draft grows the message box to its cap and keeps Send and the header on screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A smaller screen from the soft keyboard keeps the Family Chat header, composer and newest message on screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat message box has an accessible name
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat message box placeholder meets the contrast target
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat Send button has four equal round corners
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Family Chat keeps one light appearance and has no theme control
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A committed message with a mermaid flowchart shows a diagram
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A diagram with a syntax error stays visible as source with a note
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Hostile diagram text in a message is inert
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: An oversized, unsupported or surplus diagram in a message stays as source
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A diagram that arrives live is drawn
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message that is still sending shows its diagram source as typed
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A diagram stays as source when the diagram engine cannot load
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A diagram in another message adds no tab stop to the history
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Copying a message with a diagram copies the typed Markdown
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Replying to a message with a diagram quotes the typed Markdown as plain text
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A narrow diagram is readable on the own message bubble and fits a 320 px message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A wide diagram keeps a readable size and scrolls inside its own box at 320 px
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The newest message stays in view when a diagram draws
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A wide diagram in a message uses most of a desktop column

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A committed message is shown as formatted Markdown
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Raw HTML in a message is shown as text and never runs
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message that is still sending is shown as typed
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Typed line breaks in a message are kept
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: An https image in a message is shown inline
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A repository image in a message is shown inline
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Images a message may not show stay as text
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A formatted message that arrives live is formatted
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Links in a message open in a new tab
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A wide image or table fits a phone-width message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Copying a formatted message copies what was typed
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Replying to a formatted message quotes plain text
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Inline text in my own message stays readable
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Tab moves from a message into its links and opens one
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Tab and Shift+Tab pass through message content without a trap
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Escape returns focus from message content to the message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Keys inside message content keep their own meaning
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A wide table, code block or diagram can be scrolled from the keyboard
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A table or code block that fits is not a tab stop
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Only the focused message's links are reachable
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A new message keeps the focused message's content reachable
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A diagram in an older message can be reached from the keyboard on a phone
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Keyboard focus stays in a diagram's message when its picture replaces the source
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The quote card can be used from the keyboard
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A tab that lost its connection while hidden receives new messages again once it is shown, without reloading
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A reply carries its quote through each arrival path
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A reply to a reply shows only one level of quote
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The original is already on screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The original is above the loaded window
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The original is beyond the jump bound
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Highlighting respects reduced motion
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The whole journey works from the keyboard alone
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Tab does not walk through every message in the room
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A quote exposes an accessible name naming its sender
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The keys that move focus through the history bring the focused message into view
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The action menu opened from the keyboard sits beside its message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message taller than the window shows its top when focus reaches it
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message already in view does not move the history
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A returning member lands on the first unread message with an unread marker
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Earlier messages are shown above the unread marker and older history can be loaded
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A member with nothing unread lands on the newest message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Reading down to the newest message moves the resume point
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: More unread messages than one page still offer a way back to the newest
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Loading older history preserves the visitor's scroll anchor
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A new message is announced to assistive technology without moving focus from the composer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A new message away from the bottom shows "New messages below" instead of scrolling
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room shows that notifications are blocked
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Opening the room offline shows no signed-in messages from the device's saved copy
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A streaming Codex reply shows the diagram source until the reply is complete
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: An oversized diagram stays as source with a note
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: An unsupported diagram type stays as source with a note
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Diagrams beyond the first four in a message stay as source with a note
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex flowchart is drawn as a picture
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex diagram with a syntax error stays visible as source with a note
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Hostile Codex diagram text is inert
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A diagram that carries settings is not drawn and shows a note
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A drawn diagram stays drawn and keeps its source open when the conversation grows
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex diagram stays as source when the diagram engine cannot load
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex diagram draws after the diagram engine starts on a later try
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Clearing the Codex chat removes its diagrams and the next reply draws again
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A narrow Codex diagram fits a 320 pixel bubble
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A wide Codex diagram keeps a readable size and scrolls inside its own box
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex diagram draws again offline after it was drawn once
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex chat without a diagram does not load the diagram engine
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The largest allowed Codex flowchart is drawn within the time budget
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Enter and Shift+Enter follow the visitor's pointer, not the screen size
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A filled draft is sent once, and a blank, whitespace or busy draft is never sent
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Keyboard focus stays in the Codex message box after a reply
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A confirmed composition never sends in the Codex message box
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex send shortcut hint follows the visitor's pointer
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex message box follows a pointer change while the page is open
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Send button lines up with the message box
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex message box has no resize handle
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex message box placeholder meets the contrast target
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex Send button and the Family Chat Send button share one colour
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex Send button has four equal round corners that match the Family Chat Send button

export const bindingLevel = "integration";
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Every control in the room is reachable by keyboard with a visible focus indicator
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room has no horizontal page scroll
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room does not scroll the whole page vertically
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The conversation keeps room on a short screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message uses most of a narrow phone's width
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The message composer grows with a long draft and then stops at five lines
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The message composer leaves most of a short screen to the conversation
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The newest message stays above the composer when the draft grows
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A long unbroken draft leaves the Family room inside the screen (a regression guard)
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Send button text meets the contrast target
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Reopening the app resumes queued sends
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A queued message survives a real browser reload while offline
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A waiting message is sent as soon as the connection returns
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Each failed automatic retry waits longer than the last, up to one minute
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message queued more than seven days becomes manual-only
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: An offline reply waits for the connection and stays a reply
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A queued reply survives closing the app
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A queued reply commits with its link on reconnect
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A message queued before the update still sends after it
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor can install Beaver Nest as an app
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home controls and content remain visually separated
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor sends a message with Shift+Enter
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: After a dropped connection, a resumed reply shows its later text and diagram without a reload
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Codex reply tables, task lists, links and images keep their layout
