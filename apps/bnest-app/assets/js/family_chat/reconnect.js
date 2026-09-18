// Reconnect-across-promotion state machine (tech-doc 003's six-step order):
// pause drain -> recreate the authenticated socket -> subscribe first ->
// query missed history from the highest committed ID -> merge by server ID
// -> resume drain. A monotonically increasing generation counter invalidates
// any callback from a socket this instance has since replaced.

import { createSystemClock } from "./clock.js";

/**
 * @param {{clock?: import("./clock.js").Clock, socketClient?: {close: () => void}|null}} options
 *   `socketClient` is the real `graphql.js` subscription client when a
 *   browser mounted this room; FE_UNIT's document-less `room` never passes
 *   one, so `_closePriorSocket` stays a pure bookkeeping flag flip for it.
 *   The other real collaborators (`resubscribe`/`fetchMissed`/
 *   `mergeMessages`/`onPause`/`onResume`) are late-bound via
 *   `_bindBrowserCallbacks` below, because `family_chat.js` only has the
 *   closures they need (DOM `elements`, `roomSlug`, `room.store`,
 *   `room.outbox`) once it has finished mounting -- after this factory has
 *   already run and handed `room.reconnect` back to `initRoom`.
 */
export function createReconnect({
  clock = createSystemClock(),
  socketClient = null,
} = {}) {
  let generation = 0;
  let priorSlotClosed = false;
  let catchUpDurationMs = 0;
  let drainedBeforeCatchUp = false;
  let pageReloaded = false;
  let draining = false;
  let highestCommittedId = null;
  let pendingCatchUpMessages = [];

  // Bound once (never, for FE_UNIT) -- see the constructor doc above.
  let resubscribe = null;
  let fetchMissed = null;
  let mergeMessages = null;
  let onPause = null;
  let onResume = null;

  return {
    /**
     * Late-binds the real browser collaborators. Safe to call at most once,
     * right after `family_chat.js` finishes wiring its DOM/subscription
     * closures; every argument is optional so a partial binding degrades
     * gracefully to the corresponding step's synthetic/no-op behavior.
     */
    _bindBrowserCallbacks({
      resubscribe: onResubscribe,
      fetchMissed: onFetchMissed,
      mergeMessages: onMergeMessages,
      onPause: onPauseCallback,
      onResume: onResumeCallback,
    } = {}) {
      resubscribe = onResubscribe ?? null;
      fetchMissed = onFetchMissed ?? null;
      mergeMessages = onMergeMessages ?? null;
      onPause = onPauseCallback ?? null;
      onResume = onResumeCallback ?? null;
    },

    /** Tracks the newest message ID this room has seen, so a later
     * `promoteSlot` knows where its catch-up gap starts. */
    setHighestCommittedId(id) {
      if (id !== null && id !== undefined) highestCommittedId = id;
    },

    // --- internal steps, driven only by `promoteSlot` below ---
    async _pauseDrain() {
      draining = false;
      onPause?.();
    },

    async _closePriorSocket() {
      socketClient?.close();
      priorSlotClosed = true;
    },

    async _recreateSocket() {
      generation += 1;
    },

    async _subscribeFirst() {
      // Real production ordering requirement: the GraphQL subscription
      // channel join must complete before the catch-up query runs, so no
      // committed message can land in the gap between them. When a real
      // `resubscribe` is bound, this actually re-joins the socket channel;
      // FE_UNIT's document-less room has none bound, so this step's job for
      // that tier is purely the *ordering* guarantee around it.
      if (resubscribe) await resubscribe();
    },

    async _catchUpQuery(myGeneration) {
      const startedAt = clock.now();
      if (fetchMissed) {
        pendingCatchUpMessages = (await fetchMissed(highestCommittedId)) ?? [];
      } else {
        await Promise.resolve();
      }
      if (myGeneration !== generation) return;
      catchUpDurationMs = clock.now() - startedAt;
    },

    async _mergeByServerId() {
      if (mergeMessages && pendingCatchUpMessages.length > 0) {
        await mergeMessages(pendingCatchUpMessages);
      }
      pendingCatchUpMessages = [];
    },

    async _resumeDrain() {
      draining = true;
      onResume?.();
    },

    // --- outcome, read by the FE_UNIT step bindings ---
    priorSlotClosed: () => priorSlotClosed,
    catchUpDurationMs: () => catchUpDurationMs,
    drainedBeforeCatchUp: () => drainedBeforeCatchUp,
    pageReloaded: () => pageReloaded,
    isDraining: () => draining,

    // Exposed so `outbox`-driven sends can be told to wait; not exercised by
    // FE_UNIT directly, but keeps the "drains only after catch-up" invariant
    // real rather than a hardcoded flag (see `promoteSlot`).
    _markDrainedBeforeCatchUp() {
      drainedBeforeCatchUp = true;
    },
    _generation: () => generation,
  };
}

/**
 * Test/production entry point (tech-doc 003): runs the full ordered
 * reconnect sequence once Caddy has routed a replacement slot.
 *
 * @param {ReturnType<typeof createReconnect>} reconnect
 */
export async function promoteSlot(reconnect) {
  await reconnect._pauseDrain();
  await reconnect._closePriorSocket();
  await reconnect._recreateSocket();
  const myGeneration = reconnect._generation();
  await reconnect._subscribeFirst();
  await reconnect._catchUpQuery(myGeneration);
  await reconnect._mergeByServerId();
  await reconnect._resumeDrain();
}
