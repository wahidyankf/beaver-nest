# Business Requirements — Family Chat Room

## Business Need

Bn​est already gives family members private individual experiences, but it does not give the household one shared place
to exchange short messages. Family conversation therefore remains split across other applications even when the rest of
the household workflow is moving into Bnest. A small shared room closes that gap without attempting to replace a mature
messaging product.

The capability is valuable only if it stays as easy as a familiar family group chat: open the app, see the newest
conversation, write text, and find older messages by moving upward. Because Bnest is often used as an installed PWA, a
new message also needs a phone-visible signal when the recipient is not looking at the app.

## People Served

- **Children** need a safe, simple room without administrative controls or complex navigation.
- **Parents** need one durable family conversation that works on a phone and larger screens.
- **Administrators** participate as family members; administration does not grant special chat powers in v1.
- **The household operator** needs the capability to preserve the existing 24/7 route, local data ownership, backups,
  privacy boundaries, and rollback discipline.

## Desired Outcomes

1. Every approved account can reach one shared family room only after authentication.
2. A successfully sent message becomes durable before anyone is told it exists.
3. Connected family members see committed messages without refreshing.
4. A long conversation remains usable because opening the room does not load the full history.
5. An opted-in phone receives a useful notification containing the sender and a short preview.
6. Push failure never loses or rolls back the accepted chat message.
7. The first release stays intentionally small while preserving a clean path to multiple channels.

## Business Rules

- The shared room is family-wide. Existing roles do not create message visibility differences.
- Messages are permanent in v1. Users cannot edit, delete, or expire them.
- A notification is a delivery aid, not the system of record. SQLite history is authoritative.
- Notification permission belongs to each device and is always voluntary.
- Bnest never sends a notification for the sender's own message.
- A phone push may traverse the browser vendor's push service, but its payload uses standards-based Web Push encryption.
- A missing or denied notification capability cannot block the family from using chat.

## Success Measures

- Two separately authenticated synthetic users can exchange messages in real time and recover the same history after an
  application restart.
- Opening a history with more than 50 messages transfers only the newest page; older pages load upward without duplicate
  or skipped IDs.
- Retrying the same client message identity creates exactly one durable message and one delivery per target
  subscription.
- Every retryable push delivery reaches a terminal state within the declared five-attempt, one-hour ceiling.
- A physical supported phone proves opt-in, background delivery, sender-plus-preview content, and notification-click
  navigation at the exact routed origin.
- The active service stays within the repository's zero-failure, 500 ms routed p95, and 2-second per-sample continuity
  budgets throughout rollout.

## Non-Goals

- Replacing WhatsApp or importing its history.
- Moderation, legal discovery, export, or retention-policy administration.
- User-created, private, archived, or role-scoped channels.
- A general notification platform for every Bnest feature.
- Guaranteed end-device display after a push service accepts a request; operating systems retain final delivery policy.
- Offline message composition or an offline-readable authenticated transcript.

## Risks and Responses

| Risk                                          | Business impact                                           | Planned response                                                                                  |
| --------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Notification previews appear on a lock screen | Family content may be visible to someone holding a device | Make opt-in explicit, name the preview behavior before permission, and support per-device disable |
| A browser push service is unavailable         | A recipient may not see a timely alert                    | Persist the message independently; use bounded outbox retry and show history on the next visit    |
| The conversation grows indefinitely           | Initial load or SQLite queries may become slow            | Use indexed keyset pagination and load only 50 messages at a time                                 |
| Two release slots dispatch the same job       | Duplicate phone notifications                             | Lease outbox claims in SQLite and use a deterministic notification tag                            |
| A cached authenticated page survives logout   | Family content could remain in browser cache              | Restrict the service-worker cache to static assets and never cache authenticated HTML             |
| Future channels require a rewrite             | Delivery cost and migration risk increase                 | Store channels as first-class rows and require every message to reference one from v1             |

## Material Decisions

- Permanent history, rather than a 90-day or one-year purge, is selected by the user.
- Notification content includes sender plus preview, rather than sender-only or generic copy, selected by the user.
- Transactional outbox with bounded exponential backoff is selected over one-shot best effort.
- The plan selects one family-wide channel and explicitly defers all membership policy.
