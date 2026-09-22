// The subscription/catch-up half of `mount_browser.js` (tech-doc 003's
// ordered promotion sequence's real collaborators) -- split into its own
// file purely to stay under this project's max-lines lint budget.
// `mount_browser.js` is the only importer.

import { request as graphqlRequest } from "./graphql.js";
import {
  familyChatMessagesQuery,
  familyChatMessageCommittedSubscription,
} from "./operations.js";

/** @typedef {import("./mount_browser.js").MountableRoom} MountableRoom */
/** @typedef {import("./mount_browser.js").SubscriptionClient} SubscriptionClient */

/**
 * @param {MountableRoom} room
 * @param {unknown} rawResult
 */
function handleSubscriptionData(room, rawResult) {
  const result =
    /** @type {{data?: {familyChatMessageCommitted?: import("./real_store.js").RenderableMessage}}} */
    (rawResult);
  const message = result?.data?.familyChatMessageCommitted;
  if (!message) return;
  room.reconnect.setHighestCommittedId(message.id);

  // `watchPendingMessage`'s `onChange` listener (see `mount_browser.js`) is
  // the sole authoritative reconciliation point for our *own* sends (keyed
  // by this send's own mutation response -- tech-doc 008's subscription
  // payload never carries the client-chosen ID, so it cannot be matched
  // here). This handler only ever renders a genuinely new arrival;
  // `hasRendered` also absorbs the rare race where this push beats our own
  // mutation response (see `reconcile`'s matching guard in `real_store.js`
  // for that race).
  if (room.store.hasRendered(message.id ?? "")) return;
  void room.store
    .receiveRemoteMessage(message)
    // An arrival the visitor is already looking at (they were at the bottom,
    // so the store just scrolled it into view) is read; one that only lit the
    // "New messages below" indicator is not.
    .then(() => room.history.noteArrival());
}

/**
 * @param {MountableRoom} room
 * @param {SubscriptionClient} subscriptionClient
 */
export async function subscribeToRoom(room, subscriptionClient) {
  await subscriptionClient.subscribe(
    // Built from the same flag the query and mutation use: a subscription
    // that omitted the quote while the query asked for it would show a
    // reply's quote on reload and not on arrival.
    familyChatMessageCommittedSubscription({ replies: room.replies ?? false }),
    { roomSlug: room.roomSlug },
    (rawResult) => handleSubscriptionData(room, rawResult),
  );
}

/**
 * Real gap-fill query for `reconnect.js`'s catch-up step: every message
 * committed after the last one this room saw.
 * @param {string} roomSlug
 * @param {string | null} afterId
 * @param {boolean} replies
 */
async function fetchMissedMessages(roomSlug, afterId, replies) {
  const result = await graphqlRequest(familyChatMessagesQuery({ replies }), {
    roomSlug,
    afterId: afterId ?? undefined,
    limit: 200,
  });
  return result.data?.familyChatMessages?.nodes ?? [];
}

/**
 * Real merge-by-server-ID step: dedupes against whatever is already
 * rendered (including anything the live subscription already delivered
 * while the catch-up query was in flight) before appending the rest.
 * @param {MountableRoom} room
 * @param {unknown[]} rawMessages
 */
export async function mergeMissedMessages(room, rawMessages) {
  await Promise.resolve();
  const messages =
    /** @type {import("./real_store.js").RenderableMessage[]} */
    (rawMessages);
  for (const message of messages) {
    room.reconnect.setHighestCommittedId(message.id ?? null);
    if (!room.store.hasRendered(message.id ?? ""))
      void room.store.receiveRemoteMessage(message);
  }
}

/**
 * @param {MountableRoom} room
 * @param {SubscriptionClient} subscriptionClient
 */
export function bindReconnectCallbacks(room, subscriptionClient) {
  room.reconnect.bindBrowserCallbacks({
    resubscribe: () => subscribeToRoom(room, subscriptionClient),
    fetchMissed: (afterId) =>
      fetchMissedMessages(room.roomSlug, afterId, room.replies ?? false),
    mergeMessages: (rawMessages) => mergeMissedMessages(room, rawMessages),
    // Pausing/resuming the outbox's own drain (not just reconnect's
    // internal flag) is what actually stops a send from racing ahead of
    // the catch-up gap-fill (tech-doc 003).
    onPause: () => room.outbox.pauseDrain(),
    onResume: () => room.outbox.resumeDrain(),
  });
}

/**
 * Where the room opens is `history.js`'s decision (the newest page, or a
 * window anchored on this member's unread marker); this only has to tell
 * reconnect which committed message the room has caught up to.
 * @param {MountableRoom} room
 */
export async function loadInitialMessages(room) {
  const { newestId } = await room.history.loadInitial();
  if (newestId !== null) room.reconnect.setHighestCommittedId(newestId);
}

/**
 * @param {MountableRoom} room
 * @param {HTMLElement} roomElement
 * @param {SubscriptionClient} subscriptionClient
 */
export async function attemptInitialSubscribe(
  room,
  roomElement,
  subscriptionClient,
) {
  try {
    await subscribeToRoom(room, subscriptionClient);
  } catch {
    // Subscription join failure never blocks the already-loaded room; the
    // browser still functions for read/send, just without live push until
    // a future reconnect attempt succeeds.
    roomElement.dataset["connectionState"] = "ready";
  }
}
