# Realtime, Pagination, and Consistency

## Ordering Invariant

`family_chat_messages.id` is the only ordering sequence. The server assigns it in SQLite. Browser time, network arrival,
PubSub delivery time, and rendered timestamp never reorder rows. Every query includes `channel_id = 1`, excludes no
message because messages are immutable, and returns a strict ID range.

## Initial Window

The store executes the equivalent of:

```sql
SELECT id, channel_id, author_user_id, author_display_name,
       client_message_id, body, created_at
FROM family_chat_messages
WHERE channel_id = ?
ORDER BY id DESC
LIMIT 51;
```

The 51st row is existence evidence only. The LiveView reverses the first 50 into ascending display order and sets
`has_older?` from the extra row. It does not run `COUNT(*)` and does not expose the total transcript size.

On connected mount, LiveView subscribes to the channel topic before re-reading the latest window. A commit may therefore
arrive through both query and PubSub; stream identity is the integer message ID, so duplicate insertion replaces the same
rendered identity rather than adding a second message.

## Upward Pagination

The browser sends the current minimum rendered ID. The server ignores any channel ID from the client and queries:

```sql
SELECT id, channel_id, author_user_id, author_display_name,
       client_message_id, body, created_at
FROM family_chat_messages
WHERE channel_id = ? AND id < ?
ORDER BY id DESC
LIMIT 51;
```

The oldest 50 are reversed and prepended. The hook captures `scrollHeight` and `scrollTop` before the DOM patch and adds
the height delta afterward, preserving the first visible message. Only one history request may be in flight. A repeated
or stale cursor remains idempotent because stream IDs deduplicate.

When fewer than 51 rows return, the sentinel becomes a visible and screen-reader-readable **Beginning of family chat**
state. IntersectionObserver triggers normal loading; an accessible **Load older messages** button remains the fallback
when automatic observation is unavailable or reduced-motion/manual-control preferences make it preferable.

## New Message Behavior

- If the viewport is within 80 CSS pixels of the bottom, a committed message appends and scrolls into view after render.
- Otherwise, the scroll position stays fixed and a **New messages below** button with the ephemeral count appears.
- Activating that button moves to the bottom, clears the count, and focuses neither a message nor the composer.
- The sender sees the committed message through the same stream identity used by recipients; optimistic uncommitted
  bubbles are not rendered.
- Date separators and displayed local times are derived from `created_at` but never participate in ordering.

## Submission Idempotency

The hook creates `crypto.randomUUID()` when the composer becomes ready. The UUID and body travel together in the
LiveView form and are included in LiveView auto-recovery. The server resets the form and generates/requests the next UUID
only after the existing or newly committed message is returned successfully.

- Validation failure keeps the body and UUID so a correction remains one submission identity.
- Storage failure keeps the body and UUID and reports a retryable generic error.
- A repeated accepted UUID returns the original message even if the repeated body differs; it never mutates history.
- Browser-generated IDs are syntax-checked, but database uniqueness is the concurrency authority.

## PubSub and Process Failure

PubSub carries only post-commit updates. If broadcast fails or a LiveView disconnects, the message is still durable. A
fresh mount reloads the authoritative newest window. PubSub does not carry presence, typing state, delivery state, or
message acknowledgement.

The LiveView must tolerate:

- a message event older than its current minimum window;
- the same ID from query and broadcast;
- an event received while older rows are being prepended;
- a message committed after a pagination query begins;
- connection replacement during a send; and
- stale events from a terminated process.

All are resolved by immutable integer IDs, strict cursors, and idempotent client message identity.

## Reconnect and Release Continuity

Phoenix form recovery preserves an unsent body and client message ID. After a compatible reconnect:

- the route remains `/family-chat` without `page.reload()`;
- a fresh LiveView subscribes and reloads the latest 50 committed messages;
- an accepted submission can be retried without duplication;
- a draft remains editable;
- no promise is made to restore an arbitrary historical scroll offset after the server process itself was replaced.

The release proof uses two authenticated synthetic browser contexts. One holds a draft while both have the room open;
after Caddy promotion and automatic WebSocket recovery, both retain committed history, the draft survives in its owner,
and a new message is committed and rendered once.

## Text Contract

1. Normalize `\r\n` and lone `\r` to `\n`.
2. Reject a body whose trimmed form is empty.
3. Preserve intentional leading/interior whitespace except terminal newline normalization; do not silently rewrite words.
4. Reject more than 4,000 Unicode graphemes or 16,384 UTF-8 bytes.
5. Store the resulting UTF-8 string.
6. Render through HEEx text interpolation with `white-space: pre-wrap`; never use raw HTML, Markdown, or URL
   linkification.

Desktop keyboard behavior is Enter to send and Shift+Enter for a newline. Mobile relies on the visible Send button and
does not repurpose the software keyboard's newline action. IME composition must finish before Enter can send.

## Query and Concurrency Tests

- Empty, exactly 50, 51, 100, 101, and 125-row fixtures.
- Sparse IDs, concurrent inserts, and repeated cursors.
- Two submissions with the same client identity racing in separate processes.
- Two different submissions committing in the same second.
- Broadcast before/after the initial query and during prepend.
- Store failure before message insert, after message insert but before delivery insert, and before transaction commit.
- Fresh-process read-back from the same SQLite database.

Every fixture uses an isolated marked test root and `test-user-` accounts. No test reads the production database.
