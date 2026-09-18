# Family Chat Room

## Status

**In progress — plan authored and quality-gated; delivery has not started.** This plan adds a private, authenticated
family-to-family chat surface to Bnest. Future implementation provisions the repository-relative
`worktrees/family-chat-room/` checkout and remains separately authorized through [`delivery.md`](delivery.md).

## Outcome

Every approved family member can open **Family chat** from the authenticated home page, exchange permanent plain-text
messages in the shared `main` channel, receive committed messages in real time, and load older history by scrolling
upward. An opted-in installed PWA can receive a phone notification for messages sent by another user.

The first release deliberately exposes one channel. Its storage and routing contracts name the channel explicitly so a
later plan can add Slack- or Discord-style channel selection without migrating messages out of a single unscoped log.

## Scope Boundary

Included: authenticated access for every existing role, one seeded channel, text messages, SQLite persistence, realtime
fan-out, keyset history pagination, per-device Web Push subscriptions, bounded delivery retries, responsive UI,
accessibility, behaviour specifications, tests, documentation, and a continuity-safe Bnest rollout.

Excluded: WhatsApp import, attachments, rich text, Markdown, link previews, edits, deletion, reactions, threads,
mentions, presence, typing indicators, read receipts, unread badges, search, channel management, private membership,
moderation, and message-retention jobs.

## Locked Product Decisions

| Decision              | Selected contract                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| Route and home label  | `/family-chat`; **Family chat**                                                                       |
| Channel               | One seeded `main` channel; no switcher in v1                                                          |
| History               | Permanent; newest messages at the bottom                                                              |
| Initial/history page  | Latest 50, then 50 older per upward keyset request                                                    |
| Content               | Escaped plain text, multiline, no formatting or linkification                                         |
| Notification payload  | Sender display name plus a 120-grapheme message preview                                               |
| Notification delivery | Per-device opt-in; never notify the sender                                                            |
| Retry ceiling         | Five attempts within one hour: immediate, then waits of 30s, 2m, 8m, and 32m after retryable failures |
| Unsupported push      | Chat remains usable and explains why notifications are unavailable                                    |

## Selected UI Direction

The selected **Family hearth** direction keeps one chronological conversation central and quiet. It reuses Beaver Nest's
ink, paper, lagoon, sun, and coral identity without copying the denser Codex controls. The composer remains anchored,
history grows upward, and the channel name is present without pretending a channel switcher exists.

![Selected Family hearth desktop chat showing the main channel, chronological family messages, notification control, and anchored composer](assets/ui-hearth-hifi-desktop.svg)

See [UI Design](tech-docs/005-ui-design.md) for all three lo-fi alternatives, the comparison, responsive states, and
the selected desktop, tablet, and mobile hi-fi set.

## Reading Order

1. [Business Requirements](brd.md) — why the family needs the capability and which outcomes matter.
2. [Product Requirements](prd.md) — observable behavior, acceptance criteria, constraints, and non-goals.
3. [Technical Documentation](tech-docs/README.md) — architecture, schemas, realtime behavior, push, UI, specs, and
   operations.
4. [Delivery](delivery.md) — exact execution order, commands, proof, recovery, and checkpoints.
5. [Learnings](learnings.md) — discoveries captured during execution and routed before archival.

## Dependencies and Authority

- Bnest identity, SQLite authority, Caddy blue/green releases, Tailscale HTTPS, and the current PWA shell are retained.
- Web Push requires machine-local VAPID keys and outbound HTTPS to browser-selected push services. No Apple Developer
  membership is required for standards-based iOS/iPadOS Home Screen Web Push.
- The implementation adds one reviewed Web Push protocol dependency; its rationale and ownership are in
  [File Impact, Dependencies, and Operations](tech-docs/007-file-impact-dependencies-and-operations.md).
- This plan does not authorize commit, push, production migration, or deployment by itself. Those actions occur only at
  their explicit delivery checkpoints under repository governance.

## Directory Map

- [`assets/`](assets/README.md) — nine lo-fi and three selected hi-fi responsive design artifacts.
- [`brd.md`](brd.md) — business need, outcomes, rules, risks, and success measures.
- [`delivery.md`](delivery.md) — execution-grade checklist for a cold junior executor.
- [`learnings.md`](learnings.md) — dated discoveries, evidence summaries, and execution deviations.
- [`prd.md`](prd.md) — user stories, observable acceptance scenarios, constraints, and non-goals.
- [`tech-docs/`](tech-docs/README.md) — ordered architecture, data, behavior, UI, and operations contracts.
