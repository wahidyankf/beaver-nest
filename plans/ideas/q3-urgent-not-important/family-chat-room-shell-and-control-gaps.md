# Family Chat Room Shell and Control Gaps

Four small pre-existing defects where the room's shell or its controls claim something that is not true.
Provenance: spec-blind usability pass during `family-chat-message-reply` delivery, 2026-09-22; grouped because each
is a few lines of work, not because they share a cause.

## Problem / Context

- The document declares `<html lang="en">` while the interface is used in Indonesian and the room itself is named
  `ruang-keluarga`. A screen reader is being told the wrong language for the content it is about to read.
- `Use dark theme` sets `data-theme="dark"` and the room's colours do not change. The control appears to work and
  does nothing.
- `Send` is enabled when the composer is empty, so the primary action of the room advertises itself as available
  when it is not.
- `Load older messages` gives no in-flight feedback, so a slow load is indistinguishable from a dead control.

None was introduced or worsened by quoted replies. They are grouped here because splitting four one-line fixes
across four briefs would cost more to read than to do.

## Why Now

Urgent in the narrow sense that each is cheap and currently misleading someone — the language declaration most of
all, because it degrades assistive technology silently and a user cannot work around it. Not important in the sense
that none blocks any task; the room is usable with all four present.

## Prior Art / Precedents

- The reply work fixed a closely related class of defect: a refusal that the room announced to screen readers but
  never showed to sighted users, and an actions control below the WCAG 2.2 target-size minimum. Both were invisible
  to a green suite, and both were found by looking. These four came from the same pass.

## Proposed Direction (Sketch)

Set the language declaration to the language actually in use. Make the theme control either change the room's
colours or stop claiming to. Disable `Send` while the composer holds nothing sendable, matching the behaviour the
room already has for a queued send. Give `Load older messages` a pending state.

## Rough Scope & Non-Goals

In scope: the four fixes and the scenarios that would keep them fixed.

Out of scope: a translation of the interface, which is a much larger question than the `lang` attribute; a theming
system; and the room's layout and density, which have their own brief.

## Risks & Open Questions

- Setting `lang` correctly raises the obvious follow-on — the interface is in English and the content is not.
  Declaring the document's language and translating the interface are different jobs, and conflating them is how
  this stays unfixed.
- Disabling `Send` on an empty composer must not disable it for a draft that is whitespace-only-but-intended, and
  must not fight the offline queue's own disabled states.
- The dark-theme control may be wired to a room-wide system that was never extended here; the fix could be one
  line or could belong to a different surface entirely. Worth establishing before promoting.

## What Success Looks Like + Promotion Signal

Success: no control in the room advertises a capability it does not have, and assistive technology is told the
right language.

Promotion signal: any accessibility complaint, or a decision to translate the interface, promotes this brief to a
plan — the language declaration should land with that work rather than after it.
