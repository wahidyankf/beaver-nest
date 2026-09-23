# Business Requirements — Family Chat Message Reply

## Business Need

**Ruang Keluarga** is one flat chronological room shared by the whole household. That shape is deliberate and it works
until two conversations overlap. A parent asks about tomorrow's pickup, a child answers a question from ten minutes
earlier, and a third message lands in between. The room stays readable, but the _link_ between a question and its
answer exists only in the head of whoever wrote it. Everyone else reconstructs it, or asks again.

The missing capability is narrow and well understood: let a member point one message at another, so the link is carried
by the message itself instead of by memory. Every mainstream family messaging product the household already uses
provides it, and the household's expectation is set by WhatsApp specifically — hold a message, pick **Reply**, and the
message being answered appears quoted above what you type.

This is worth doing now rather than later for two reasons that are about cost, not enthusiasm. First, the room's message
table is append-only by database trigger: rows can never be edited or deleted. A reply link added to that table can
therefore never point at something that changed or vanished, which removes the single hardest class of defect this
feature has in every other product. Second, the room currently has no per-message interaction of any kind. The first
one to be built pays for the whole affordance — the way a message is selected, focused, described to a screen reader,
and acted on. Reply is a better first tenant for that surface than a cosmetic one, and every later per-message action
inherits it.

## People Served

- **Children** need to answer a specific question without retyping it, and to see which message an answer belongs to.
- **Parents** need household coordination to survive interleaving, so that "yes" is never ambiguous.
- **Family members using a keyboard, a screen reader, or a desktop browser** need the same capability the touch
  long-press gives, through a path that actually exists for them.
- **The household operator** needs the change to reach a 24/7 service without a stop, a forced refresh, or a
  one-way migration.

## Desired Outcomes

1. A member can select any committed message in the room and answer it, and the answer carries the link permanently.
2. The quoted message is visible inside the reply for every reader, on every device, whether the message arrived by
   history page, live subscription, or reconnect catch-up.
3. A reader can move from a quote to the message it points at, and is told plainly when that message is beyond reach
   rather than being left on a control that does nothing.
4. The capability is reachable by touch, mouse, and keyboard, and is described to a screen reader without the reader
   having to infer structure from punctuation.
5. A member who is offline can still compose a reply; it queues and commits with its link intact.
6. Adding the link does not change how a message is committed, deduplicated, notified, backed up, or restored.
7. The change reaches production without stopping Bnest, without a refresh, and with a rollback floor that can still
   serve every client released before it.

## Business Rules

- A reply points at exactly **one** message, and that message must be an already-committed message in the same room.
- The link is a **reference**, not a copy. The quoted text shown is always derived from the original row at read time.
- Replies are **flat**. A reply to a reply quotes only its immediate parent; a quote never renders its own quote.
- A member may reply to their own message and to a system message. No sender kind is privileged or excluded.
- Messages remain permanent, immutable plain text. This plan adds no edit, no delete, and no reaction.
- A message that has not yet committed cannot be replied to, because it has no identity for a link to point at.
- Replying changes nothing about notification content. A reply notifies exactly as an ordinary message does.
- A reply's quote is a reading aid, not an access control. Any member who can read the room can read every quote in it.
- The reply target chosen in the composer is a draft, and drafts are not persisted. Closing the room discards it.

## Non-Goals

Threaded conversation views, reply counts, "replied to you" notification variants, swipe-to-reply gestures, quoting a
selected fragment of text rather than a whole message, forwarding, reactions, edit, delete, mentions, and replying
across rooms. Each is a separate product decision, and none is required for the coordination problem stated above.

## Business Risks

| Risk                                                                                           | Consequence                                                                    | Mitigation                                                                                |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| The new per-message menu is reachable only by touch long-press                                 | Desktop and keyboard members lose a capability the household now has           | Four entry points to one menu, proven at the keyboard and screen-reader layers            |
| Long-press collides with the browser's own text-selection and context menus on iOS and Android | The feature appears broken on exactly the devices it was built for             | Native callout suppressed on coarse pointers only; text stays selectable on fine pointers |
| A quote points at a message the reader's window has not loaded                                 | A dead control, or an unbounded chain of history fetches                       | Bounded jump: at most five older pages, then a stated refusal                             |
| The browser asks a server revision that predates the field                                     | The room fails to load for anyone holding the newer bundle                     | Two-stage release: every routed slot can answer the field before any bundle requests it   |
| The quote doubles the size of a history page                                                   | Slower first paint on the household's weakest device                           | The quoted body is truncated on the server to a fixed grapheme budget, not clamped by CSS |
| The feature is treated as small and skips design and accessibility exploration                 | A permanent interaction surface is set badly and inherited by the next feature | Full lo-fi/hi-fi exploration and both manual testing passes are delivery requirements     |

## Success Measures

- Two isolated `test-user-` contexts exchange a reply; both observe the same quoted sender and text, once.
- Every path that renders a message — first page, older page, live subscription, reconnect catch-up, and the sender's
  own echo — renders the same quote for the same message.
- A reply composed while offline commits with its link after reconnect, with no duplicate and no lost target.
- The complete reply journey is performed with the keyboard alone, and again with a screen reader, and recorded.
- A quote whose target is beyond the jump bound produces a stated refusal, not a silent no-op, and no further fetches.
- Routed responsiveness through both releases holds p95 ≤ 500 ms with every sample ≤ 2 s, with no forced refresh.
- The rollback floor revision serves both the pre-reply and post-reply browser bundles without error.
