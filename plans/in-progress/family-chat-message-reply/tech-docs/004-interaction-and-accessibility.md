# Interaction and Accessibility

This document owns the behaviour of the three new surfaces — the action menu, the composer reply strip, and the quote
card — including how each is reached without a pointer and described without sight. It is deliberately separate from
[UI Design](003-ui-design.md): that document decides what the room looks like, this one decides what it does.

## The Action Menu

### One menu, four triggers

| Trigger                            | Fires on                                                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Press and hold on a coarse pointer | `pointerdown` starts a 500 ms timer; `pointerup` or `pointercancel` before it elapses cancels, and movement over 10 px cancels |
| Browser context menu               | `contextmenu` on the message, with `preventDefault()`                                                                          |
| The `⋯` actions control            | `click`, on a control rendered only for fine pointers and revealed on hover or focus                                           |
| Keyboard                           | `Enter` or `Space` on the focused message                                                                                      |

All four call the same open function with the same message. There is one menu element in the document, moved and
re-labelled per message, so two menus can never be open at once and there is one thing to test.

**Why 500 ms and 10 px.** Below roughly 400 ms a hold is indistinguishable from a slow tap; above roughly 600 ms it
feels broken. The movement tolerance is what makes a scroll that begins on a bubble a scroll and not a menu.

**Pointer cancellation.** The menu opens on the timer, but no action is performed by the gesture itself — `Reply` and
`Copy text` each require a second, separate activation, and dragging away from the menu and releasing closes it
without acting. That satisfies WCAG 2.5.2 by structure rather than by accident.

**Why `contextmenu` is handled and not only long-press.** On iOS and Android the browser's own long-press produces a
selection callout or a link menu. Suppressing that and substituting ours is the whole trick, and it is done narrowly:

```css
@media (pointer: coarse) {
  .family-chat-message-bubble {
    -webkit-touch-callout: none;
  }
}
```

Only on coarse pointers, and only the callout. Text on a laptop stays selectable, because removing selection from
every message to make a hold gesture work would be a net loss — and `Copy text` exists for the case where selection is
awkward, not as a replacement for it.

### Structure and focus

```html
<div
  class="family-chat-message-actions"
  role="menu"
  aria-label="Message actions"
>
  <button type="button" role="menuitem">Reply</button>
  <button type="button" role="menuitem">Copy text</button>
</div>
```

- Opening moves focus to the first available item.
- `ArrowDown` / `ArrowUp` cycle items; `Home` / `End` jump; `Escape` closes.
- Focus is held inside the menu while it is open, and returns to the message it was opened from on close —
  Escape, clicking outside, and choosing `Copy text`.
- **Corrected 2026-09-22:** this rule originally said _every_ close path, "including choosing an item". `Reply` is
  the one path that must not return focus to the message: it puts focus in the composer, and the dismissal listener
  on the menu host was taking it straight back, in the same gesture. An item that places focus itself now stops the
  click before it reaches the host. The bug was invisible to the unit specs, which drive `createMenuState` and
  `runCopyAction` directly and never dispatch a real event through both listeners — it took a browser-shaped room
  to see it.
- An unavailable `Reply` keeps `aria-disabled="true"` and stays focusable, so a screen-reader user hears the reason
  instead of finding an item that silently is not there. Its reason is on the item as `aria-describedby`.

### Actions

**Reply.** Sets the composer's reply target, closes the menu, moves focus to the message input, and announces
`Replying to {name}.` in the existing live region. Available only when the message has a server ID.

**Copy text.** Writes the message's full body — not the preview — through `navigator.clipboard.writeText`, closes the
menu, returns focus to the message, and announces `Message copied.` A rejected or unavailable clipboard announces
`Couldn't copy. Select the text manually.` instead. The promise is always handled; a silent rejection would leave the
member believing the copy worked.

## Keyboard Navigation of the History

The history is a `role="log"` list of 50 or more items. Making each one tabbable would put fifty stops between the
header and the composer, so the list uses a **roving tabindex**:

- exactly one message carries `tabindex="0"` — the last one focused, or the newest on first render; every other
  message carries `tabindex="-1"`;
- `Tab` enters the list once and leaves it once;
- `ArrowUp` / `ArrowDown` move between messages and move the roving stop with them;
- `Home` / `End` move to the oldest loaded and the newest message;
- `Enter` or `Space` opens the menu for the focused message.

A jump moves the roving stop to the target, which is what makes a jump usable without sight: the reader lands on the
message rather than merely scrolling past it.

### This changes an existing structural check

`assets/js/family_chat/accessibility.js` currently proves keyboard reachability by asserting that the shipped
`room.html.heex` contains no `tabindex="-1"`. Message elements are created in JavaScript, so that check would keep
passing while the rendered room filled with `tabindex="-1"` — it would be green and meaningless.

Routing around it would be dishonest, and so would repairing it in only one place. The contract is therefore proven
at two layers, because they answer different questions:

| Layer     | Proves                                                                                                                                                                                                                                         |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FE_UNIT` | The **renderer's invariant**: exactly one `tabindex="0"` among the message items, every other item `-1`, and the roving stop moving with the arrow keys. This replaces the template text scan, which never looked at the rendered list at all. |
| `FE_E2E`  | The **real focus order**: Tab enters the history once, the arrow keys move between messages, Tab leaves once, and Enter opens the menu — measured by a real layout and focus engine rather than inferred.                                      |

The fast layer keeps the invariant from regressing on every commit; the slow layer keeps the invariant honest about
what a member actually experiences. Either one alone is a check that can be green while the room is unusable.

## The Composer Reply Strip

- Rendered inside the existing composer form, above the textarea, only while a reply target is set.
- Shows `Replying to {name}` and a 160-grapheme preview, bounded by the same rule the quote card uses.
  **Corrected 2026-09-22:** this said "the same server preview the quote card shows", which was true of a quote
  arriving from the server and false of a target chosen on screen. A target picked from a rendered bubble never
  passes through the server at all — it was built from the rendered body, in full, and a 400-grapheme message filled
  the strip with all 400. `bodyPreview` in `reply_target.js` now applies the same rule client-side, by grapheme
  rather than by code unit, so the strip and the quote card can never disagree about the same message. Both the
  backend and browser drivers allow `<= 161`: the budget plus the one ellipsis that marks the cut.
- Carries a `Cancel reply` button. `Escape` in the textarea does the same thing.
- Selecting a different message while a target is set replaces the target; it never stacks.
- Cleared on successful queueing. **Not** cleared when the send is refused — the member keeps both their text and
  their target and can try again.
- Not persisted. Drafts are not persisted in this room today, and a reply target is part of a draft. Reloading
  discards both, and that consistency is worth more than saving one selection.

**The draft and the target clear for different reasons, and that is deliberate.** Added 2026-09-22. The composer
reads the target before awaiting the queue and calls `clear()` only after the queue accepted; a refusal restores
`draftState.body` and leaves the target untouched. Keeping the target **outside** `draftState` is what makes the
two bullets above structural rather than a rule someone has to remember.

The strip is not a live region. Announcing the selection is done once, deliberately, through the room's existing
`role="status"` element, so a screen reader is not re-reading the strip every time the member types.

## The Quote Card

```html
<button
  type="button"
  class="family-chat-message-quote"
  data-role="family-chat-message-quote"
  data-target-message-id="1042"
  aria-label="Reply to Ayah: Nanti aku jemput jam 5. Go to that message."
>
  <span class="family-chat-message-quote-sender">Ayah</span>
  <span class="family-chat-message-quote-preview">Nanti aku jemput jam 5</span>
</button>
```

A `button`, because it performs an action in place rather than navigating. The `aria-label` carries the relationship
first, the content second, and the affordance last, so a screen reader announces what this is before reading it.
No WAI-ARIA pattern covers a quoted reply, so this wording is a decision, not a citation, and it is proven by a manual
screen-reader pass rather than by a static check.

The visible sender name and the label's name are both the live-resolved display name, so they never disagree with the
name on the original bubble.

**Flat rendering.** A quote card never contains a quote card. The GraphQL type makes that unrepresentable
([GraphQL Contract](002-graphql-contract.md)), and the renderer takes no nesting parameter.

## Jump to Original

```text
activate quote (id = T)
├─ T is rendered in the current window
│    → scroll it into view, highlight it, move the roving focus to it
└─ T is not rendered
     → repeat, at most 5 times:
         load one older page (the existing keyset "load older" path)
         if T is now rendered → scroll, highlight, focus; stop
     → after 5 pages without finding T:
         announce "That message is too far back to jump to."
         leave the window where it is
```

**Why five.** Each page is at most 50 messages, so the bound is 250 messages of catch-up — far more than a quote
reachable in ordinary family conversation, and small enough that a pathological case ends in about a second rather
than walking the whole history. The bound is declared here, not discovered at runtime.

**Why a bound at all.** Signal's own issue tracker records a quote that points beyond the client's pagination
boundary rendering as `"Quoted message not found"`; the failure this design avoids is not the refusal itself but an
unbounded chain of fetches, or a control that does nothing and says nothing.

**Scroll.** The jump uses the same container-relative offset arithmetic as `scrollToResumeAnchor`, not
`scrollIntoView`, so the page itself never scrolls and the sticky header and composer stay put on mobile.

**Highlight.** A 1.2 s background fade on the target, or, under `prefers-reduced-motion: reduce`, a static outline
held for 2 s. The target is the **original** message, not the reply — the member asked to see the original, and that
is where their attention should land.

**Interaction with the unread divider and `hasNewer`.** A jump only loads _older_ pages, so it never changes which
messages are considered new, never moves the unread divider, and never clears the `New messages below` indicator. If
the indicator was up before the jump, it is still up after it, and it is the way back.

## Offline Behaviour

The reply target is the committed server ID, so nothing about it needs the network. The outbox record carries one more
optional field:

```js
{ clientMessageId, body, replyToMessageId?, status, attempt, retryCount, createdAt, nextRetryAt, neverSucceed }
```

- The IndexedDB store keeps `DB_VERSION = 1`. Adding a property to records in an existing key-path store needs no
  version bump and no `upgradeneeded` migration; records written before this change simply have no
  `replyToMessageId`, which reads as "not a reply". A version bump would run an upgrade that has nothing to do.
- Drain order, backoff, the 100-record cap, and the seven-day expiry are unchanged.
- A queued reply's target is a permanent, immutable row. It cannot vanish while the reply waits, so no orphan state
  exists and none is handled.
- Replying to a message that has not committed is refused at the menu, which is why the outbox never has to translate
  a `clientMessageId` into a server ID at drain time, and why the queue has no dependency ordering.
