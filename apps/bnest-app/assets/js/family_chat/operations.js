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

export const MESSAGE_FIELDS = `
  id
  roomSlug
  senderKind
  senderId
  senderDisplayName
  body
  committedAt
`;

export const FAMILY_CHAT_ROOM_QUERY = `
  query FamilyChatRoom($slug: String!) {
    familyChatRoom(slug: $slug) { ${ROOM_FIELDS} }
  }
`;

export const FAMILY_CHAT_MESSAGES_QUERY = `
  query FamilyChatMessages($roomSlug: String!, $beforeId: ID, $afterId: ID, $limit: Int) {
    familyChatMessages(roomSlug: $roomSlug, beforeId: $beforeId, afterId: $afterId, limit: $limit) {
      nodes { ${MESSAGE_FIELDS} }
      hasOlder
      hasNewer
    }
  }
`;

export const SEND_FAMILY_CHAT_MESSAGE_MUTATION = `
  mutation SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
    sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { ${MESSAGE_FIELDS} }
  }
`;

export const FAMILY_CHAT_MESSAGE_COMMITTED_SUBSCRIPTION = `
  subscription FamilyChatMessageCommitted($roomSlug: String!) {
    familyChatMessageCommitted(roomSlug: $roomSlug) { ${MESSAGE_FIELDS} }
  }
`;

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
