# GraphQL Contract

Every UI-facing operation stays on the existing boundary: authenticated `/api/graphql` for query and mutation,
authenticated `/api/graphql/socket` for the subscription. No new endpoint, no new authentication path, and no new
error code.

## Schema Delta

```graphql
type FamilyChatMessageQuote {
  id: ID!
  senderKind: String!
  senderDisplayName: String!
  bodyPreview: String!
}

type FamilyChatMessage {
  id: ID!
  roomSlug: String!
  senderKind: String!
  senderId: ID!
  senderDisplayName: String!
  body: String!
  committedAt: DateTime!
  replyTo: FamilyChatMessageQuote # new, nullable
}

type Mutation {
  sendFamilyChatMessage(
    roomSlug: String!
    clientMessageId: ID!
    body: String!
    replyToMessageId: ID # new, nullable
  ): FamilyChatMessage
}
```

`replyTo` is a distinct object type rather than a recursive `FamilyChatMessage`. That is the flat-reply rule expressed
in the type system: there is no field on `FamilyChatMessageQuote` that could carry another quote, so no client can
request one and no resolver can accidentally serve one. Telegram's Bot API arrives at the same place by stripping the
nested field at serialization time; a separate type reaches it by construction and cannot be forgotten.

`bodyPreview` is named for what it is. A field called `body` that silently returned 160 of 4,000 graphemes would be a
trap for the next reader.

**The quote's server-side shape is not its published field list.** Added 2026-09-22, after the first build of it
carried exactly the four fields above and nothing else. `FamilyChatMessageQuote.senderDisplayName` resolves live
through `FamilyChat.live_sender_display_name/2`, which reads `message.sender_id` — a field the type does not
publish and the map therefore did not carry. Every unit test passed, because none of them resolved a quote
_through the schema_; the first thing that would have hit it was a real client. The map `quote_of/1` builds now
carries `sender_id` internally, with no field exposing it, and a unit case drives that seam directly.

The general shape is worth keeping: a resolver's input contract is not the type's field list, and matching the two
by eye is how this was missed.

## Operation Documents

`assets/js/family_chat/operations.js` remains the one place any document is written. The message field list becomes a
function of one flag so the compatibility and experience releases can ship the same bundle:

```js
export const MESSAGE_FIELDS_BASE = `
  id
  roomSlug
  senderKind
  senderId
  senderDisplayName
  body
  committedAt
`;

export const REPLY_FIELDS = `
  replyTo { id senderKind senderDisplayName bodyPreview }
`;

export function messageFields({ replies }) {
  return replies
    ? `${MESSAGE_FIELDS_BASE}${REPLY_FIELDS}`
    : MESSAGE_FIELDS_BASE;
}
```

The flag comes from `data-family-chat-reply-enabled` on the room element, written by the controller from
`BNEST_FAMILY_CHAT_REPLY_ENABLED`. It gates three things together — the requested fields, the action menu, and the
composer strip — so there is no state in which the browser asks for a field it will not render, or renders a quote it
did not ask for.

Query, mutation, and subscription documents are all built from `messageFields`. They must stay in step: a subscription
that omits `replyTo` while the query includes it produces a room where a reply's quote appears on reload and not on
arrival, which is the hardest kind of bug to see. Before this plan they were three independent template strings, so
a drift between them was both easy to introduce and invisible until a live message rendered differently from a
resumed one.

**The mutation declares its variable conditionally too.** `sendFamilyChatMessageMutation({replies})` adds
`$replyToMessageId: ID` to the operation's variable list and `replyToMessageId: $replyToMessageId` to the call only
when the flag is on. That is not tidiness: it is what makes the browser emit **byte-identical pre-reply documents**
with the flag off, which is precisely what the compatibility release depends on. A document that declared an unused
variable would still validate, but it would no longer be the document the shipped release sends.

## Validation and Errors

No new error code. `replyToMessageId` failures are `VALIDATION_FAILED`, with the same safe message every other
validation failure returns, because the browser's remediation is identical and because an error that distinguishes
"no such message" from "wrong room" tells an unauthenticated prober something about what exists.

| Input                                           | Result                              |
| ----------------------------------------------- | ----------------------------------- |
| absent, or `null`                               | ordinary message                    |
| a positive integer naming a row in this room    | reply committed with the link       |
| a positive integer naming no row                | `VALIDATION_FAILED`, nothing stored |
| a positive integer naming a row in another room | `VALIDATION_FAILED`, nothing stored |
| a non-integer, zero, or negative value          | `VALIDATION_FAILED`, nothing stored |

`VALIDATION_FAILED` is already in `NON_RETRYABLE_CODES`, so a rejected reply consumes no outbox retry budget and is
reported to the member as `Couldn't send` rather than retried forever. That behaviour needs no change; it needs a test
that proves the new rejection path lands in it.

## Idempotency

The uniqueness key is unchanged: `(room_id, sender_kind, sender_id, idempotency_key)`. `replyToMessageId` is not part
of it and must not become part of it.

The consequence is deliberate and must be tested: **the first commit wins.** If the same `clientMessageId` is replayed
with a different reply target — which a retrying outbox could in principle do after a local edit — the existing row is
returned unchanged, with its original link. A client message ID identifies one intended message, and changing what it
points at after the fact would make a retry a mutation.

## Resolver Boundary

`FamilyChatResolver` gains one argument pass-through and nothing else. It does not parse the ID, does not look the
target up, and does not truncate the preview; `BnestApp.FamilyChat` owns all three. The existing dependency-direction
test in `test/unit/bnest_app_web/schema_test.exs` is what keeps that true, and it must still pass.

`FamilyChat.send_message/5` grows one optional argument. It is added as a trailing optional parameter with a `nil`
default so the backup module's synthetic load probe, which calls it positionally, keeps compiling unchanged.

**Quote resolution is room-scoped at read time as well as at write time.** Added 2026-09-22. `Store.quotes_for/2`
takes the room id and filters on it, so `replyTo` can never resolve to a message outside the room being read. The
two checks are not redundant — the write-time check in `message_by_id/2` guards the rows this application writes,
and the read-time scope guards what a reader is shown. The full reasoning is in
[Data Model](001-data-model-and-migration.md#read-path).

## Manual Proof

Every changed operation gets a real `curl` against the routed origin with a `test-user-` session, recorded without
private values:

- `familyChatMessages` returning a page in which at least one node carries a populated `replyTo` and at least one
  carries `null`;
- `sendFamilyChatMessage` with a valid `replyToMessageId`, returning the committed message and its quote;
- `sendFamilyChatMessage` with a non-existent `replyToMessageId`, returning `VALIDATION_FAILED` and committing nothing;
- `familyChatMessageCommitted` observed over the authenticated socket, carrying `replyTo` on a reply — proven with a
  protocol-capable client, since `curl` cannot hold the subscription.
