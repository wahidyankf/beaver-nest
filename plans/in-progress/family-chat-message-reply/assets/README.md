# Family Chat Message Reply UI Assets

These deterministic SVGs use synthetic family names (Ayah, Bunda, Kakak, Adik) and invented message text only. They
contain no production account, identifier, origin, notification endpoint, key, cookie, path, or household content.

Every asset shows the same representative task at three widths: **Bunda replies to Ayah's message, while the action
menu is open on that message.** Holding the task and the content constant is what makes the three alternatives
comparable.

## Lo-fi Alternatives

- `ui-quote-card-lofi-{desktop,tablet,mobile}.svg` — **selected.** The quote is a bordered card with an accent bar
  inside the reply bubble and is itself the control that jumps to the original. Actions open as one menu, anchored to
  the message on pointer widths and raised from the bottom edge on mobile.
- `ui-inline-prefix-lofi-{desktop,tablet,mobile}.svg` — not selected. The quote is a single condensed prefix line and
  the actions appear as a floating toolbar over neighbouring messages.
- `ui-thread-rail-lofi-{desktop,tablet,mobile}.svg` — not selected. Replies are indented beneath their parent behind a
  connector rail, with a collapse control and, on desktop, a thread list panel.

## Selected Hi-fi

- `ui-quote-card-hifi-{desktop,tablet,mobile}.svg` — the selected direction in the canonical Beaver Nest ink, paper,
  sun, coral, lagoon, mint, and cream tokens. Across the set they show the quote card, the open action menu, the
  composer reply strip, the outlined jump target, the disabled-Reply state on an unsent message, and the
  too-far-back refusal.

Every SVG carries a unique accessible title and description, and no state in them is carried by colour alone: the jump
target is outlined and labelled, the disabled action is labelled with its reason, and the quote is marked by the `↩`
glyph and the sender's name as well as by its tint.

The plan's [UI Design](../tech-docs/003-ui-design.md) embeds the full set, records the comparison, and owns the
selection rationale.

## Directory Map

- [`ui-inline-prefix-lofi-desktop.svg`](ui-inline-prefix-lofi-desktop.svg) — inline-prefix alternative at desktop width.
- [`ui-inline-prefix-lofi-mobile.svg`](ui-inline-prefix-lofi-mobile.svg) — inline-prefix alternative at mobile width.
- [`ui-inline-prefix-lofi-tablet.svg`](ui-inline-prefix-lofi-tablet.svg) — inline-prefix alternative at tablet width.
- [`ui-quote-card-hifi-desktop.svg`](ui-quote-card-hifi-desktop.svg) — selected quote-card desktop visual.
- [`ui-quote-card-hifi-mobile.svg`](ui-quote-card-hifi-mobile.svg) — selected quote-card mobile visual.
- [`ui-quote-card-hifi-tablet.svg`](ui-quote-card-hifi-tablet.svg) — selected quote-card tablet visual.
- [`ui-quote-card-lofi-desktop.svg`](ui-quote-card-lofi-desktop.svg) — selected quote-card desktop structure.
- [`ui-quote-card-lofi-mobile.svg`](ui-quote-card-lofi-mobile.svg) — selected quote-card mobile structure.
- [`ui-quote-card-lofi-tablet.svg`](ui-quote-card-lofi-tablet.svg) — selected quote-card tablet structure.
- [`ui-thread-rail-lofi-desktop.svg`](ui-thread-rail-lofi-desktop.svg) — thread-rail alternative at desktop width.
- [`ui-thread-rail-lofi-mobile.svg`](ui-thread-rail-lofi-mobile.svg) — thread-rail alternative at mobile width.
- [`ui-thread-rail-lofi-tablet.svg`](ui-thread-rail-lofi-tablet.svg) — thread-rail alternative at tablet width.
