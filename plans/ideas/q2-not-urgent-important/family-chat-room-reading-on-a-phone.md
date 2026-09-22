# Family Chat Room Reading on a Phone

Make the family chat room readable and navigable on the device the household actually uses it on. Provenance:
spec-blind usability pass during `family-chat-message-reply` delivery, 2026-09-22; grouped by theme rather than one
brief per finding.

## Problem / Context

A usability pass run without sight of the specifications recorded six findings about reading and moving around the
room. None was introduced or worsened by quoted replies; all predate that work, which is why they were recorded and
not fixed there.

- At 320px the header and composer occupy 291 of 568 available pixels, leaving roughly two message bubbles visible.
- Long messages are hard to read on a phone.
- The composer textarea never grows, so a multi-line message is composed through a one-line window.
- There is no affordance to jump to the newest message once scrolled away.
- Every message repeats the sender's name and the full date, with no day separators and no grouping of consecutive
  messages from the same person.
- The action menu offers Reply and Copy text but no way to reach a quoted message's original from the menu itself;
  the quote card is the only path.

Individually each is small. Together they describe a room where most of the screen is chrome, every message costs a
line of repeated metadata, and getting back to where you were is manual.

## Why Now

Not urgent: the room works and is in daily use. It belongs in this quadrant because the evidence exists now, freshly
dated, from a pass that deliberately had no access to what the room was supposed to do — which is the only kind of
pass that notices that a room is mostly header.

## Prior Art / Precedents

- The room's own resume behaviour already solves the hardest version of "where was I" by placing the reader on the
  unread marker. A jump-to-newest control is the same idea pointed the other way.
- Day separators and same-sender grouping are conventional in every messaging client the household uses, which
  makes their absence a surprise rather than a style choice.

## Proposed Direction (Sketch)

Treat it as one pass over the room's vertical budget and its repetition: shrink or collapse chrome at small widths,
let the composer grow to a bounded height, group consecutive messages from one sender under a single attribution,
insert day separators, and add a jump-to-newest control. Add a `Go to that message` item to the action menu so the
original is reachable without hitting the quote card.

## Rough Scope & Non-Goals

In scope: the room's layout at small widths, message grouping and separators, the composer's height behaviour, a
jump-to-newest affordance, and one action-menu item.

Out of scope: quoted replies, which work; the room's colours, which have their own brief; and any change to
storage, transport, or the message model.

## Risks & Open Questions

- Grouping changes what a "message" looks like, which touches the same rendering path replies just landed in. It
  deserves its own manual pass rather than trusting the suite.
- A `Go to that message` menu item is a specification change, not a defect fix; it needs a scenario before code.
- Collapsing chrome at small widths risks hiding controls that the keyboard and screen-reader paths depend on. The
  room's four invocations were designed so no input method is second-class, and that has to survive.

## What Success Looks Like + Promotion Signal

Success: at 320px the room shows meaningfully more than two bubbles, consecutive messages from one person read as
one block, and returning to the newest message takes one action.

Promotion signal: a household member saying the room is hard to use on their phone, or a second usability pass
repeating any of these findings, promotes this brief to a plan.
