// The subscription/catch-up half of `mount_browser.js` (tech-doc 003's
// ordered promotion sequence's real collaborators) -- split into its own
// file purely to stay under this project's max-lines lint budget.
// `mount_browser.js` is the only importer.

import { request as graphqlRequest } from "./graphql.js";
import {
  FAMILY_CHAT_MESSAGES_QUERY,
  FAMILY_CHAT_MESSAGE_COMMITTED_SUBSCRIPTION,
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
  void room.store.receiveRemoteMessage(message);
}

/**
 * @param {MountableRoom} room
 * @param {SubscriptionClient} subscriptionClient
 */
export async function subscribeToRoom(room, subscriptionClient) {
  await subscriptionClient.subscribe(
    FAMILY_CHAT_MESSAGE_COMMITTED_SUBSCRIPTION,
    { roomSlug: room.roomSlug },
    (rawResult) => handleSubscriptionData(room, rawResult),
  );
}

/**
 * Real gap-fill query for `reconnect.js`'s catch-up step: every message
 * committed after the last one this room saw.
 * @param {string} roomSlug
 * @param {string | null} afterId
 */
async function fetchMissedMessages(roomSlug, afterId) {
  const result = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
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
async function mergeMissedMessages(room, rawMessages) {
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
    fetchMissed: (afterId) => fetchMissedMessages(room.roomSlug, afterId),
    mergeMessages: (rawMessages) => mergeMissedMessages(room, rawMessages),
    // Pausing/resuming the outbox's own drain (not just reconnect's
    // internal flag) is what actually stops a send from racing ahead of
    // the catch-up gap-fill (tech-doc 003).
    onPause: () => room.outbox.pauseDrain(),
    onResume: () => room.outbox.resumeDrain(),
  });
}

/** @param {MountableRoom} room */
export async function loadInitialMessages(room) {
  const initial = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
    roomSlug: room.roomSlug,
    limit: 50,
  });
  const nodes = initial.data?.familyChatMessages?.nodes ?? [];
  room.store.renderInitial(nodes, initial.data?.familyChatMessages?.hasOlder);
  const lastNode = nodes.at(-1);
  if (lastNode) room.reconnect.setHighestCommittedId(lastNode.id);
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
