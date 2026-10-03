// The subscription/catch-up half of `mount_browser.js` (tech-doc 003's
// ordered promotion sequence's real collaborators) -- split into its own
// file purely to stay under this project's max-lines lint budget.
// `mount_browser.js` is the only importer.

import { computeBackoffDelayMs } from "./backoff.js";
import {
  familyChatMessagesQuery,
  familyChatMessageCommittedSubscription,
} from "./operations.js";
import { MESSAGE_PAGE_SIZE } from "./page_source.js";

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
 * committed after the last one this room saw, a server-sized page at a
 * time (the server refuses a larger limit outright).
 * @param {MountableRoom} room
 * @param {string | null} afterId
 */
async function fetchMissedMessages(room, afterId) {
  const { request, roomSlug, replies = false } = room;
  const document = familyChatMessagesQuery({ replies });
  /** @type {{id?: string}[]} */
  const missed = [];
  let cursor = afterId;
  for (;;) {
    // eslint-disable-next-line no-await-in-loop -- each page starts after the last message of the one before it.
    const result = await request(document, {
      roomSlug,
      afterId: cursor ?? undefined,
      limit: MESSAGE_PAGE_SIZE,
    });
    const page = result.data?.familyChatMessages;
    const nodes = page?.nodes ?? [];
    missed.push(...nodes);
    const last = nodes.at(-1)?.id;
    if (!page?.hasNewer || last === undefined) return missed;
    cursor = last;
  }
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
      retryWithBackoff(room, () => fetchMissedMessages(room, afterId)),
    mergeMessages: (rawMessages) => mergeMissedMessages(room, rawMessages),
    // Pausing/resuming the outbox's own drain (not just reconnect's
    // internal flag) is what actually stops a send from racing ahead of
    // the catch-up gap-fill (tech-doc 003).
    onPause: () => room.outbox.pauseDrain(),
    onResume: () => room.outbox.resumeDrain(),
  });
}

/**
 * How many times the room asks the server for a page it needs to carry on:
 * up to four attempts, waiting 1 s, 2 s, then 4 s (jittered, at most 8.4 s in
 * all) between them, on the room's own clock.
 */
export const INITIAL_LOAD_ATTEMPTS = 4;

/**
 * Runs `task`, and again after a bounded backoff while it rejects -- no
 * network, or a request landing in a Caddy cutover and meeting a non-JSON 5xx.
 * Rejects with the last failure once the attempts run out.
 * @template T
 * @param {MountableRoom} room
 * @param {() => Promise<T>} task
 * @returns {Promise<T>}
 */
async function retryWithBackoff(room, task) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      // eslint-disable-next-line no-await-in-loop -- an attempt starts only once the one before it has failed.
      return await task();
    } catch (error) {
      if (attempt >= INITIAL_LOAD_ATTEMPTS) throw error;
      const delayMs = computeBackoffDelayMs(attempt, room.clock.random);
      // eslint-disable-next-line no-await-in-loop -- the next attempt waits out this one's backoff.
      await new Promise((resolve) => {
        room.clock.setTimer(() => resolve(null), delayMs);
      });
    }
  }
}

/**
 * Where the room opens is `history.js`'s decision (the newest page, or a
 * window anchored on this member's unread marker); this only has to tell
 * reconnect which committed message the room has caught up to.
 *
 * A failed load is tried again (`retryWithBackoff`) and the room keeps
 * "booting" meanwhile. Nothing is rendered by a failed attempt, so a retry
 * starts clean. Resolves `false` rather than rejecting once the attempts run
 * out, so the caller decides what the member is shown.
 * @param {MountableRoom} room
 * @returns {Promise<boolean>} whether the first page loaded.
 */
export async function loadInitialMessages(room) {
  try {
    const { newestId } = await retryWithBackoff(room, () =>
      room.history.loadInitial(),
    );
    if (newestId !== null) room.reconnect.setHighestCommittedId(newestId);
    return true;
  } catch {
    return false;
  }
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
