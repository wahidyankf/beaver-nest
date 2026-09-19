// Reconnect-across-promotion state machine (tech-doc 003's six-step order):
// pause drain -> recreate the authenticated socket -> subscribe first ->
// query missed history from the highest committed ID -> merge by server ID
// -> resume drain. A monotonically increasing generation counter invalidates
// any callback from a socket this instance has since replaced.
//
// Split into several small factory functions (state, callback binder,
// bookkeeping steps, async steps, outcome readers) purely to stay under this
// project's max-lines-per-function lint budget -- `createReconnect` below
// composes them, and is the only export a caller needs to know about.

import { createSystemClock } from "./clock.js";

/**
 * @typedef {{
 *   generation: number,
 *   priorSlotClosed: boolean,
 *   catchUpDurationMs: number,
 *   drainedBeforeCatchUp: boolean,
 *   pageReloaded: boolean,
 *   draining: boolean,
 *   highestCommittedId: string | null,
 *   pendingCatchUpMessages: unknown[],
 *   resubscribe: (() => Promise<void>) | null,
 *   fetchMissed: ((highestCommittedId: string | null) => Promise<unknown[]>) | null,
 *   mergeMessages: ((messages: unknown[]) => Promise<void>) | null,
 *   onPause: (() => void) | null,
 *   onResume: (() => void) | null,
 * }} ReconnectState
 */

/** @returns {ReconnectState} */
function createReconnectState() {
  return {
    generation: 0,
    priorSlotClosed: false,
    catchUpDurationMs: 0,
    drainedBeforeCatchUp: false,
    pageReloaded: false,
    draining: false,
    highestCommittedId: null,
    pendingCatchUpMessages: [],
    resubscribe: null,
    fetchMissed: null,
    mergeMessages: null,
    onPause: null,
    onResume: null,
  };
}

/**
 * Late-binds the real browser collaborators. Safe to call at most once,
 * right after `family_chat.js` finishes wiring its DOM/subscription
 * closures; every argument is optional so a partial binding degrades
 * gracefully to the corresponding step's synthetic/no-op behavior.
 * @param {ReconnectState} state
 */
function createCallbackBinder(state) {
  /**
   * @param {{
   *   resubscribe?: () => Promise<void>,
   *   fetchMissed?: (highestCommittedId: string | null) => Promise<unknown[]>,
   *   mergeMessages?: (messages: unknown[]) => Promise<void>,
   *   onPause?: () => void,
   *   onResume?: () => void,
   * }} [bindings]
   */
  return function bindBrowserCallbacks({
    resubscribe,
    fetchMissed,
    mergeMessages,
    onPause,
    onResume,
  } = {}) {
    state.resubscribe = resubscribe ?? null;
    state.fetchMissed = fetchMissed ?? null;
    state.mergeMessages = mergeMessages ?? null;
    state.onPause = onPause ?? null;
    state.onResume = onResume ?? null;
  };
}

// Not `async` (no `await` inside): `promoteSlot` still `await`s each call,
// which resolves a non-Promise return value immediately, keeping the
// ordered sequence's shape uniform across every step.
/**
 * @param {ReconnectState} state
 * @param {{close: () => void}|null} socketClient
 */
function createBookkeepingSteps(state, socketClient) {
  return {
    pauseDrainStep() {
      state.draining = false;
      state.onPause?.();
    },

    closePriorSocketStep() {
      socketClient?.close();
      state.priorSlotClosed = true;
    },

    recreateSocketStep() {
      state.generation += 1;
    },

    resumeDrainStep() {
      state.draining = true;
      state.onResume?.();
    },
  };
}

/**
 * @param {ReconnectState} state
 * @param {import("./clock.js").Clock} clock
 */
function createAsyncSteps(state, clock) {
  return {
    async subscribeFirstStep() {
      // Real production ordering requirement: the GraphQL subscription
      // channel join must complete before the catch-up query runs, so no
      // committed message can land in the gap between them. When a real
      // `resubscribe` is bound, this actually re-joins the socket channel;
      // FE_UNIT's document-less room has none bound, so this step's job for
      // that tier is purely the *ordering* guarantee around it.
      if (state.resubscribe) await state.resubscribe();
    },

    /** @param {number} myGeneration */
    async catchUpQueryStep(myGeneration) {
      const startedAt = clock.now();
      if (state.fetchMissed) {
        state.pendingCatchUpMessages =
          (await state.fetchMissed(state.highestCommittedId)) ?? [];
      } else {
        await Promise.resolve();
      }
      if (myGeneration !== state.generation) return;
      state.catchUpDurationMs = clock.now() - startedAt;
    },

    async mergeByServerIdStep() {
      if (state.mergeMessages && state.pendingCatchUpMessages.length > 0) {
        await state.mergeMessages(state.pendingCatchUpMessages);
      }
      state.pendingCatchUpMessages = [];
    },
  };
}

/** @param {ReconnectState} state */
function createOutcomeReaders(state) {
  return {
    priorSlotClosed: () => state.priorSlotClosed,
    catchUpDurationMs: () => state.catchUpDurationMs,
    drainedBeforeCatchUp: () => state.drainedBeforeCatchUp,
    pageReloaded: () => state.pageReloaded,
    isDraining: () => state.draining,
    generation: () => state.generation,
  };
}

/**
 * @param {{clock?: import("./clock.js").Clock, socketClient?: {close: () => void}|null}} options
 *   `socketClient` is the real `graphql.js` subscription client when a
 *   browser mounted this room; FE_UNIT's document-less `room` never passes
 *   one, so `closePriorSocketStep` stays a pure bookkeeping flag flip for it.
 *   The other real collaborators (`resubscribe`/`fetchMissed`/
 *   `mergeMessages`/`onPause`/`onResume`) are late-bound via
 *   `bindBrowserCallbacks` below, because `family_chat.js` only has the
 *   closures they need (DOM `elements`, `roomSlug`, `room.store`,
 *   `room.outbox`) once it has finished mounting -- after this factory has
 *   already run and handed `room.reconnect` back to `initRoom`.
 *
 *   Every method below other than `setHighestCommittedId` and the outcome
 *   readers is an internal seam driven only by `promoteSlot`/this module's
 *   own tests, not a stable feature-author-facing API -- deliberately named
 *   without a leading underscore (oxlint's `no-underscore-dangle` forbids
 *   that convention here), so the doc comments carry that signal instead.
 */
export function createReconnect({
  clock = createSystemClock(),
  socketClient = null,
} = {}) {
  const state = createReconnectState();

  return {
    bindBrowserCallbacks: createCallbackBinder(state),

    /** Tracks the newest message ID this room has seen, so a later
     * `promoteSlot` knows where its catch-up gap starts. */
    /** @param {string | null | undefined} id */
    setHighestCommittedId(id) {
      if (id !== null && id !== undefined) state.highestCommittedId = id;
    },

    ...createBookkeepingSteps(state, socketClient),
    ...createAsyncSteps(state, clock),
    ...createOutcomeReaders(state),

    // Exposed so `outbox`-driven sends can be told to wait; not exercised by
    // FE_UNIT directly, but keeps the "drains only after catch-up" invariant
    // real rather than a hardcoded flag (see `promoteSlot`).
    markDrainedBeforeCatchUp() {
      state.drainedBeforeCatchUp = true;
    },
  };
}

/**
 * Test/production entry point (tech-doc 003): runs the full ordered
 * reconnect sequence once Caddy has routed a replacement slot.
 *
 * @param {ReturnType<typeof createReconnect>} reconnect
 */
export async function promoteSlot(reconnect) {
  await reconnect.pauseDrainStep();
  await reconnect.closePriorSocketStep();
  await reconnect.recreateSocketStep();
  const myGeneration = reconnect.generation();
  await reconnect.subscribeFirstStep();
  await reconnect.catchUpQueryStep(myGeneration);
  await reconnect.mergeByServerIdStep();
  await reconnect.resumeDrainStep();
}

/**
 * Test/production entry point: forces a fresh connection attempt every time
 * the page becomes visible again. A mobile PWA suspended in the background
 * routinely freezes JS timers and silently kills the underlying transport
 * without ever firing a clean close event -- the native WebSocket's own
 * `readyState` can go on reporting "open" long after the connection is
 * actually dead, so a check like "only reconnect if not connected" is not a
 * reliable gate here (confirmed against a real severed connection in this
 * plan's own E2E proof: gating on that check left the stale connection
 * undetected and no reconnect ever fired). Unconditional means an
 * occasional harmless extra reconnect cycle on an already-healthy
 * connection -- cheap and idempotent, since it only re-runs the existing
 * `onReconnect` catch-up sequence (`mount_browser.js`) -- which is a much
 * better trade than a silently stale room. Deliberately does *not* call
 * `promoteSlot` itself: forcing the transport reconnect here is enough,
 * since that catch-up sequence already runs once the fresh connection
 * actually opens, exactly as it does for a Caddy promotion.
 * @param {{reconnectNow: () => void}} socketClient
 */
export function resumeFromBackground(socketClient) {
  socketClient.reconnectNow();
}
