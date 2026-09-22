// One source of truth for every GraphQL operation document the Family Chat
// browser code sends (tech-doc 008's exact contract). Every module that
// needs to query/mutate/subscribe imports its document from here instead of
// inlining its own copy (this plan's REFACTOR requirement) -- a schema
// change only ever needs one edit.

export const ROOM_FIELDS = `
  id
  slug
  name
  roomKind
  memberPostingEnabled
`;

export const MESSAGE_FIELDS_BASE = `
  id
  roomSlug
  senderKind
  senderId
  senderDisplayName
  body
  committedAt
`;

// A flat quote, and only ever one level of it: `familyChatMessageQuote` is a
// distinct object type with no reply field, so asking for a quote's quote is
// a document error rather than an empty result.
export const REPLY_FIELDS = `
  replyTo { id senderKind senderDisplayName bodyPreview }
`;

/**
 * The message field list as a function of one flag, so the compatibility and
 * experience releases ship the same bundle. The flag gates the requested
 * fields, the action menu, and the composer strip together: there is no state
 * in which the browser asks for a field it will not render, or renders a
 * quote it did not ask for.
 * @param {{replies: boolean}} options
 */
export function messageFields({ replies }) {
  return replies
    ? `${MESSAGE_FIELDS_BASE}${REPLY_FIELDS}`
    : MESSAGE_FIELDS_BASE;
}

export const FAMILY_CHAT_ROOM_QUERY = `
  query FamilyChatRoom($slug: String!) {
    familyChatRoom(slug: $slug) { ${ROOM_FIELDS} }
  }
`;

/**
 * Query, mutation, and subscription are all built from `messageFields`, and
 * must stay in step. A subscription that omitted `replyTo` while the query
 * included it would produce a room where a reply's quote appears on reload
 * and not on arrival.
 * @param {{replies: boolean}} options
 */
export function familyChatMessagesQuery({ replies }) {
  return `
  query FamilyChatMessages($roomSlug: String!, $beforeId: ID, $afterId: ID, $limit: Int) {
    familyChatMessages(roomSlug: $roomSlug, beforeId: $beforeId, afterId: $afterId, limit: $limit) {
      nodes { ${messageFields({ replies })} }
      hasOlder
      hasNewer
    }
  }
`;
}

/**
 * With the flag off the argument is not declared at all, so an older slot
 * that has not yet learned it cannot be sent one.
 * @param {{replies: boolean}} options
 */
export function sendFamilyChatMessageMutation({ replies }) {
  const declaration = replies ? ", $replyToMessageId: ID" : "";
  const argument = replies ? "\n      replyToMessageId: $replyToMessageId" : "";
  return `
  mutation SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!${declaration}) {
    sendFamilyChatMessage(
      roomSlug: $roomSlug
      clientMessageId: $clientMessageId
      body: $body${argument}
    ) { ${messageFields({ replies })} }
  }
`;
}

/** @param {{replies: boolean}} options */
export function familyChatMessageCommittedSubscription({ replies }) {
  return `
  subscription FamilyChatMessageCommitted($roomSlug: String!) {
    familyChatMessageCommitted(roomSlug: $roomSlug) { ${messageFields({ replies })} }
  }
`;
}

export const WEB_PUSH_CONFIGURATION_QUERY = `
  query WebPushConfiguration {
    webPushConfiguration { available publicKey }
  }
`;

export const CURRENT_WEB_PUSH_SUBSCRIPTION_QUERY = `
  query CurrentWebPushSubscription {
    currentWebPushSubscription { enabled expirationTime }
  }
`;

export const UPSERT_WEB_PUSH_SUBSCRIPTION_MUTATION = `
  mutation UpsertWebPushSubscription($endpoint: String!, $p256dh: String!, $auth: String!) {
    upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) {
      enabled
      expirationTime
    }
  }
`;

export const DISABLE_CURRENT_WEB_PUSH_SUBSCRIPTION_MUTATION = `
  mutation DisableCurrentWebPushSubscription {
    disableCurrentWebPushSubscription { enabled expirationTime }
  }
`;

// Non-retryable per tech-doc 008's error matrix: the same input/room/session
// would fail again without a real state change, so the outbox must not
// spend an automatic retry budget on it. Every other code (including no
// code at all, e.g. a network-level rejection) is retryable.
export const NON_RETRYABLE_CODES = new Set([
  "VALIDATION_FAILED",
  "ROOM_NOT_FOUND",
  "FORBIDDEN",
  "CSRF_REJECTED",
]);
