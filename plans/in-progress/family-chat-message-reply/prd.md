# Product Requirements — Family Chat Message Reply

## Personas

- **Family member (touch):** an approved child, parent, or administrator using the installed PWA on a phone. Reaches
  the feature by holding a message.
- **Family member (pointer):** the same person on a laptop. Reaches it by right-clicking a message or by the control
  that appears when the pointer is over it.
- **Family member (keyboard or screen reader):** the same person without a usable pointer. Reaches it by moving focus
  onto a message and pressing a key, and needs the quote described rather than drawn.
- **Household operator:** maintains the private host, the SQLite database, backups, and the release route.

## User Stories

- As a family member, I can hold, right-click, or focus any committed message and choose **Reply**.
- As a family member, I can see which message I am answering while I type, and change my mind before sending.
- As a family member, I can see inside any reply which message it answers, and who wrote it.
- As a family member, I can move from a quote to the original message, and be told when it is out of reach.
- As a family member, I can compose a reply while offline and have it send itself with its link when I reconnect.
- As a family member using a keyboard or a screen reader, I can do every one of the above.
- As the household operator, I can release this without stopping Bnest and roll back to a revision that still works.

## Acceptance Criteria

### AC-FCR-01 — One action menu, four ways in

```gherkin
Scenario Outline: A member opens the message action menu
  Given an approved family member has Ruang Keluarga open with at least one committed message
  When the member <entry point> on that message
  Then the message action menu opens anchored to that message
  And keyboard focus is inside the menu

Examples:
  | entry point |
  | presses and holds for 500 ms on a touch screen |
  | opens the browser context menu with a right click |
  | activates the actions control revealed by pointer hover |
  | moves focus to the message and presses Enter |
```

```gherkin
Scenario: Closing the menu returns focus to the message it came from
  Given the message action menu is open for a committed message
  When the member presses Escape
  Then the menu closes
  And keyboard focus is on that same message
```

```gherkin
Scenario: A press that turns into a scroll does not open the menu
  Given an approved family member has Ruang Keluarga open on a touch screen
  When the member presses a message and moves more than 10 pixels before releasing
  Then no action menu opens
  And the history scrolls
```

```gherkin
Scenario: Only one menu is open at a time
  Given the message action menu is open for one committed message
  When the member opens the menu on a different message
  Then only the second message has an open menu
```

### AC-FCR-02 — What the menu offers, and when

```gherkin
Scenario: A committed message offers both actions
  Given the member opens the action menu on a committed message
  Then the menu contains exactly the actions "Reply" and "Copy text"
  And both are available
```

```gherkin
Scenario Outline: A message that is not yet committed cannot be replied to
  Given the member's own message is in the <state> state
  When the member opens the action menu on it
  Then "Reply" is present and unavailable
  And the menu states that the message must send before it can be replied to
  And "Copy text" remains available

Examples:
  | state |
  | Waiting for connection |
  | Sending |
  | Retrying |
  | Couldn't send |
```

```gherkin
Scenario: A system message can be replied to like any other
  Given Ruang Keluarga contains a committed system message
  When the member opens the action menu on it
  Then "Reply" is available
```

```gherkin
Scenario: Copying a message puts its text on the clipboard
  Given the member opens the action menu on a message whose body is "Dinner is ready"
  When the member chooses "Copy text"
  Then the clipboard contains exactly "Dinner is ready"
  And the room announces that the message was copied
```

```gherkin
Scenario: A refused clipboard is reported, not swallowed
  Given the browser refuses clipboard write access
  When the member chooses "Copy text"
  Then the room states that the text could not be copied
  And the menu closes
```

### AC-FCR-03 — The composer shows what is being answered

```gherkin
Scenario: Choosing Reply puts the target above the message input
  Given the member opens the action menu on a message from "Ayah" reading "Nanti aku jemput jam 5"
  When the member chooses "Reply"
  Then the composer shows a reply strip naming "Ayah"
  And the strip shows the text of that message
  And keyboard focus is in the message input
  And the room announces that the member is replying to "Ayah"
```

```gherkin
Scenario: A long quoted message is shortened in the strip
  Given the selected message body is 400 graphemes long
  When the reply strip renders it
  Then at most 160 graphemes of it are shown, followed by an ellipsis
```

```gherkin
Scenario Outline: The member abandons the reply
  Given the composer shows a reply strip
  When the member <action>
  Then the reply strip is gone
  And the message input keeps whatever was already typed

Examples:
  | action |
  | activates the cancel control on the strip |
  | presses Escape in the message input |
```

```gherkin
Scenario: The reply target does not survive a reload
  Given the composer shows a reply strip
  When the member reloads Ruang Keluarga
  Then no reply strip is shown
```

```gherkin
Scenario: Sending clears the reply target
  Given the composer shows a reply strip
  When the member sends the message
  Then no reply strip is shown
  And the next message the member types is not a reply
```

### AC-FCR-04 — A reply commits its link

```gherkin
Scenario: The mutation accepts and returns the link
  Given an approved member is authenticated to GraphQL
  And a committed message exists in "ruang-keluarga" with a known server ID
  When the member sends a message with that ID as the reply target
  Then the mutation returns one committed message
  And its quote names that server ID
  And its quote carries the original's sender and a preview of its body
```

```gherkin
Scenario: An ordinary message still commits with no link
  Given an approved member is authenticated to GraphQL
  When the member sends a message with no reply target
  Then the mutation returns one committed message
  And that message has no quote
```

```gherkin
Scenario: A replayed client message ID returns the first commit unchanged
  Given a reply was acknowledged for one client message ID
  When the same room, sender, and client message ID are submitted with a different reply target
  Then the mutation returns the original server message ID
  And the stored reply target is the one committed first
  And no second message or push delivery row is created
```

### AC-FCR-05 — An impossible link is refused before any commit

```gherkin
Scenario Outline: The server rejects a reply target it cannot honour
  Given an approved member is authenticated to GraphQL
  When the member sends a message whose reply target <target>
  Then the response is a validation error
  And no message is stored
  And no subscription event is published

Examples:
  | target |
  | is an ID no message has |
  | belongs to a message in another room |
  | is not a positive integer |
```

### AC-FCR-06 — Every arrival path renders the same quote

```gherkin
Scenario Outline: A reply carries its quote through <path>
  Given two approved members have Ruang Keluarga open
  And the first member has replied to a message from the second
  When the reply reaches a reader through <path>
  Then the reply renders a quote naming the original sender
  And the quote shows the original message text

Examples:
  | path |
  | the first history page |
  | an older history page |
  | the live subscription |
  | reconnect catch-up after a dropped socket |
```

```gherkin
Scenario: The quoted sender name follows the account, not the stamp
  Given a member replied to a message committed under an older display name
  When the account's display name is changed
  Then the quote shows the current display name
  And it matches the name shown on the original message itself
```

### AC-FCR-07 — Replies stay flat

```gherkin
Scenario: A reply to a reply quotes only its parent
  Given message A exists
  And message B is a reply to A
  When a member replies to B
  Then the new message renders a quote of B
  And that quote does not itself render a quote of A
```

### AC-FCR-08 — Reaching the message a quote points at

```gherkin
Scenario: The original is already on screen
  Given a reply and the message it quotes are both in the loaded window
  When the member activates the quote
  Then the history scrolls to the original message
  And that message is highlighted briefly
  And keyboard focus moves to it
```

```gherkin
Scenario: The original is above the loaded window
  Given a reply quotes a message that is two older pages above the loaded window
  When the member activates the quote
  Then older pages are loaded until the original is present
  And the history scrolls to it
```

```gherkin
Scenario: The original is beyond the jump bound
  Given a reply quotes a message more than five older pages above the loaded window
  When the member activates the quote
  Then no more than five older pages are requested
  And the room states that the message is too far back to jump to
  And the loaded window is left where the member can continue reading
```

```gherkin
Scenario: Highlighting respects reduced motion
  Given the member's system requests reduced motion
  When the member jumps to a quoted message
  Then the message is marked without an animated pulse
```

### AC-FCR-09 — A reply composed offline survives and commits

```gherkin
Scenario: An offline reply queues with its target
  Given the member is offline with Ruang Keluarga open
  When the member replies to a committed message
  Then the queued message shows "Waiting for connection"
  And the queued record carries the reply target
```

```gherkin
Scenario: A queued reply survives closing the app
  Given an offline reply is queued
  When the member closes and reopens the installed app while still offline
  Then the queued reply is still present with its target
```

```gherkin
Scenario: A queued reply commits with its link on reconnect
  Given an offline reply is queued
  When the connection returns
  Then the reply commits once
  And the committed message renders its quote
```

```gherkin
Scenario: A queued record written before this feature still sends
  Given the outbox holds a queued message stored with no reply target field
  When the connection returns
  Then that message commits as an ordinary message
```

### AC-FCR-10 — Reachable without a pointer, describable without sight

```gherkin
Scenario: The whole journey works from the keyboard alone
  Given an approved member has Ruang Keluarga open and is using only a keyboard
  When the member moves focus into the message history, selects a message, opens the menu, chooses "Reply", types, and sends
  Then the sent message renders a quote of the selected message
  And focus is never trapped outside a control the member can operate
```

```gherkin
Scenario: Tab does not walk through every message in the room
  Given the history holds 50 messages
  When the member presses Tab from the message before the history
  Then focus enters the history once
  And the arrow keys move between messages
```

```gherkin
Scenario: A screen reader is told what a quote is before it reads it
  Given a screen reader is reading a reply
  When it reaches the quote
  Then it announces the quote as a reply to a named sender before reading the quoted text
  And it announces the quote as an activatable control
```

```gherkin
Scenario Outline: No horizontal scrolling appears at any supported width
  Given Ruang Keluarga is open at <viewport> with a reply whose quoted text has no spaces for 200 characters
  Then the page does not scroll horizontally
  And the quoted text is wrapped or truncated within the bubble

Examples:
  | viewport |
  | 320 x 568 |
  | 768 x 1024 |
  | 1440 x 900 |
```

### AC-FCR-11 — The column is additive and reversible while unused

```gherkin
Scenario: Existing messages are untouched by the migration
  Given a database holding messages committed before this change
  When the migration runs
  Then every existing message is unchanged
  And every existing message has no reply target
```

```gherkin
Scenario: The migration is idempotent across a restart
  Given the migration has already run
  When the application starts again
  Then the migration does not run a second time
  And startup succeeds
```

```gherkin
Scenario: Reversal refuses once the feature has been used
  Given at least one stored message carries a reply target
  When the migration is reversed
  Then it refuses with a stated reason
  And no data is removed
```

### AC-FCR-12 — Notifications are unchanged by replying

```gherkin
Scenario: A reply notifies exactly as an ordinary message does
  Given a member has notifications enabled on one device
  When another member sends a reply
  Then the notification carries the sender's display name and a preview of the reply body only
  And it contains no part of the quoted message
```

```gherkin
Scenario: A reply creates the same delivery bookkeeping as any message
  Given one other device has an active subscription
  When a reply commits
  Then exactly one pending delivery row exists for that subscription
```

### AC-FCR-13 — Mixed revisions stay safe through the release

```gherkin
Scenario: A browser holding the pre-reply bundle talks to the new revision
  Given the compatibility revision is routed
  When a browser that was loaded from the previous revision queries the room
  Then the room loads and messages send normally
```

```gherkin
Scenario: The rollback floor can still answer the reply-aware bundle
  Given the experience revision has been rolled back to the compatibility revision
  When a browser holding the reply-aware bundle queries the room
  Then the room loads
  And existing replies still render their quotes
```

**Proven 2026-09-22 (D12)** as a browser scenario in
`specs/apps/bnest/app-fe/behaviours/family_chat.feature`, not as a routed observation. The plan had filed it as
plan-only on the grounds that it had no runnable subject; it does, because the floor and the experience revision
are one build differing by one flag.

```gherkin
Scenario: Promotion moves connected clients without a refresh
  Given two members have Ruang Keluarga open through the routed origin
  When the operator promotes the new revision
  Then both clients reconnect and catch up without a page reload
  And a message committed during the promotion appears exactly once for each
```

### AC-FCR-14 — The routed service stays responsive throughout

**Accepted as permanently unmet 2026-09-23 (D15).** The criterion keeps the wording below; the stage that was
never sampled stays visible as a gap rather than being removed.

**Partially met, 2026-09-22 (D14). Arithmetic corrected 2026-09-22 by the re-check.** This first read "Two of
this criterion's four release-stage sample sets were taken; two never were." That mixed two denominators. Against
the four stages the outline below enumerates, **three carry a 12-sample set and one does not**:

| Stage                                      | Set          | Where                                                           |
| ------------------------------------------ | ------------ | --------------------------------------------------------------- |
| preflight, before any change               | p95 248.4 ms | Phase 0's routed baseline                                       |
| after the compatibility revision is routed | p95 278.1 ms | Phase 9 post-promotion                                          |
| after the experience revision is routed    | **none**     | withdrawn; the figures recorded for it were Phase 9's, repeated |
| after the drain window closes              | p95 48.3 ms  | Phase 10 post-drain                                             |

**The preflight row was mis-sourced, corrected 2026-09-23 by the fourth check.** It read `p95 35.9 ms | Phase 0`,
pairing Phase 9's _release_ preflight figure with Phase 0's _baseline_ row. Phase 0's set is p95 248.4 ms
(`delivery.md`, Phase 0; `learnings.md`, routed readiness baseline); the 35.9 ms set was taken immediately before
the compatibility release. Both are 12-sample sets inside budget and both land on this stage, so it is carried
twice over and the three-of-four conclusion is unaffected — but a reader following the "Where" column reached a
different number than the row stated.

"Two" came from a per-release accounting instead: across two releases each stage recurs, and two of those
moments — Phase 9's post-drain and Phase 10's post-promotion — were never sampled. Both counts are true of
different things, and the earlier sentence attached the per-release number to the per-stage denominator.

What the correction does not change: the criterion is still only partially met, because one enumerated stage was
never measured and that slot no longer exists to be retaken. The distinction the record keeps: the service was
never shown to be slow — every sample ever taken returned 200 inside budget — it was shown to be **unmeasured**
after the experience promotion. The criterion is recorded as holding at three of four stages rather than
rewritten to fit what survived.

```gherkin
Scenario Outline: Routed responsiveness holds at every release stage
  Given the operator samples the routed readiness endpoint 12 times at <stage>
  Then every sample succeeds
  And the 95th percentile is at most 500 ms
  And no single sample exceeds 2 s

Examples:
  | stage |
  | preflight, before any change |
  | after the compatibility revision is routed |
  | after the experience revision is routed |
  | after the drain window closes |
```

## Product Scope

Included: the per-message action menu with **Reply** and **Copy text**; the composer reply strip; the additive
`reply_to_message_id` column; the `replyToMessageId` mutation argument and the `replyTo` quote field; quote rendering
on every arrival path; bounded jump-to-original with highlight; offline queuing of replies; roving-focus keyboard
navigation of the message history; the twelve design assets; specification and C4 updates; and the two-stage release.

Excluded: everything listed as a non-goal in [`brd.md`](brd.md), plus room creation, message edit, message delete,
attachment quoting, and retiring the `BNEST_FAMILY_CHAT_REPLY_ENABLED` flag after the rollback window.

## Product Risks

| Risk                                                                             | Mitigation                                                                                       |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| A one-item-per-message menu feels heavier than the action it performs            | The menu carries two actions from the first release and is built as a reusable component         |
| Roving focus changes how the existing history behaves for current keyboard users | AC-FCR-10 fixes the expected traversal explicitly, and the existing structural check is extended |
| A member expects swipe-to-reply because WhatsApp has it                          | Recorded as a non-goal with its evidence, so the absence is a decision rather than an oversight  |
| Bounded jump feels arbitrary when it refuses                                     | The refusal states the reason in product copy rather than failing silently                       |
