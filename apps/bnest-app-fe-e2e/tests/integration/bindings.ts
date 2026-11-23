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

export const bindingLevel = "integration";
