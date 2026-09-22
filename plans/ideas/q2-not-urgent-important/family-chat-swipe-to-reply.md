# Family Chat Swipe to Reply

Add a horizontal swipe on a message as an optional shortcut to replying, alongside the four invocations the room
already has. Provenance: deliberately deferred by the `family-chat-message-reply` plan, 2026-09-22.

## Problem / Context

Replying today starts by opening a per-message action menu, which four gestures can do: a long press, a
right-click, a keyboard activation, and the visible "more" control. The menu then offers Reply. That is
discoverable and reachable, and it is two steps.

Every messaging application the household already uses offers a one-step swipe instead, so the gesture is learned
before anyone meets this room. The plan left it out on purpose rather than by oversight: a swipe is a pointer-only
affordance, and adding one without an equivalent for keyboard and screen-reader users would make the fast path the
inaccessible path. The room's existing four invocations were designed so no input method is second-class, and a
fifth should not undo that.

## Why Now

Not urgent. Replies work, and the menu is not slow enough to be a complaint. This brief exists so the idea is
recorded with its constraint attached, rather than being re-proposed later without it.

## Prior Art / Precedents

- The room's own action menu already demonstrates the standard this repository holds: the same capability reachable
  by pointer, keyboard, and assistive technology, proven at the layer each one lives in.
- Horizontal swipe-to-reply is conventional in consumer messaging clients; the convention is worth borrowing, and
  its usual accessibility gap is worth not borrowing.

## Proposed Direction (Sketch)

A horizontal drag past a threshold on a message sets that message as the reply target and focuses the composer,
with the existing reply strip as the confirmation. The gesture is additive: the menu keeps its Reply item, and
nothing moves behind the swipe.

Two constraints are not negotiable. It must respect `prefers-reduced-motion`, which the room already honours for
highlighting. And it must not compete with the horizontal scroll of a quoted preview or a long code span inside a
bubble — the plan already fixed two defects caused by the same automatic-minimum-size interaction, and a swipe
handler is another way to collide with it.

## Rough Scope & Non-Goals

In scope: the gesture, its threshold and cancellation, its reduced-motion behaviour, and its interaction with the
existing four invocations.

Out of scope: swipe for any other action; replacing the menu; and any change to what a reply is or how it commits.

## Risks & Open Questions

- What threshold distinguishes a deliberate swipe from a scroll that started slightly sideways? A wrong answer
  makes the room feel unstable, which is worse than a second tap.
- Does a swipe need a visual affordance before it is performed, and if so, does that clutter a room whose bubbles
  are deliberately plain?
- Touch is the obvious target, but a trackpad produces horizontal gestures too. Whether the desktop layout should
  respond at all is genuinely open.

## What Success Looks Like + Promotion Signal

Success: a one-step reply on touch that nobody triggers by accident, with keyboard and screen-reader paths
unchanged and equally fast, and the accessibility evidence recorded at the layer that can prove it.

Promotion signal: a household member asking for it, or a usability pass finding the two-step menu to be the
friction that stops people replying, promotes this brief to a plan.
