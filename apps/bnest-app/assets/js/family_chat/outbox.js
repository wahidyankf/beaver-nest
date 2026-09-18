// The browser-owned send outbox (tech-doc 003's state machine): every
// composed message is queued locally first, then drained toward the server.
// Namespace storage lives in `outbox_namespace.js` and the send/retry state
// machine in `outbox_send.js` (split out purely to stay under this
// project's max-lines/max-lines-per-function lint budget); this file
// composes them into the public API feature code imports.

import { createSystemClock } from "./clock.js";
import {
  STATUS,
  namespaceKey,
  getOrCreateNamespace,
  generateClientMessageId,
} from "./outbox_namespace.js";
import {
  createOutboxState,
  activeCount,
  attemptSend,
  resumeOnOpen,
} from "./outbox_send.js";
import {
  createTestSeamMethods,
  seedQueuedMessage,
} from "./outbox_test_seam.js";

export { STATUS, seedQueuedMessage };
export const QUEUE_SCHEMA_VERSION = 1;
export const MAX_QUEUED_PER_ROOM = 100;

/** @typedef {import("./outbox_send.js").TransportResult} TransportResult */
/** @typedef {import("./outbox_send.js").SendOptions} SendOptions */
/** @typedef {import("./outbox_namespace.js").QueuedMessage} QueuedMessage */

/** @param {import("./outbox_send.js").OutboxState} state */
function createSendMethod(state) {
  /**
   * @param {string} body
   * @param {SendOptions} [opts]
   * @returns {Promise<string|null>} the new clientMessageId, or null if the room's queue is full.
   */
  return async function send(body, opts = {}) {
    await Promise.resolve();
    if (activeCount(state) >= MAX_QUEUED_PER_ROOM) {
      state.onQueueFull?.();
      return null;
    }

    const clientMessageId = generateClientMessageId(state.clock.random);
    /** @type {QueuedMessage} */
    const message = {
      clientMessageId,
      body,
      status: STATUS.WAITING,
      attempt: 0,
      retryCount: 0,
      createdAt: state.clock.now(),
      nextRetryAt: 0,
      neverSucceed: false,
      timerHandle: undefined,
    };
    state.namespace.messages.set(clientMessageId, message);

    // Deliberately not awaited: `attemptSend` runs synchronously up to its
    // first `await` (marking the message "Sending" before yielding), so a
    // caller that reads `status()` immediately after `send()` resolves
    // observes "Sending" -- the way a real network round trip looks --
    // while the eventual "Sent"/"Retrying"/"Couldn't send" transition
    // happens once the transport's own promise settles, observed via
    // `waitForStatus`.
    void attemptSend(state, message, opts);
    return clientMessageId;
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createReadMethods(state) {
  return {
    /** @param {string} clientMessageId @returns {object|null} the real committed message once `send()` succeeded, else null. */
    committedMessage(clientMessageId) {
      return state.committed.get(clientMessageId) ?? null;
    },

    /** @param {string} clientMessageId */
    status(clientMessageId) {
      const message = state.namespace.messages.get(clientMessageId);
      return message ? message.status : "not-found";
    },

    /** @param {string} clientMessageId */
    retryCount(clientMessageId) {
      return state.namespace.messages.get(clientMessageId)?.retryCount ?? 0;
    },

    /** @param {string} clientMessageId */
    nextRetryEtaMs(clientMessageId) {
      const message = state.namespace.messages.get(clientMessageId);
      return message ? message.nextRetryAt - state.clock.now() : 0;
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createWatchMethods(state) {
  return {
    /**
     * @param {string} clientMessageId
     * @param {string} expected
     * @returns {Promise<string>} resolves once the message reaches `expected` (or is already there).
     */
    waitForStatus(clientMessageId, expected) {
      const current = state.namespace.messages.get(clientMessageId);
      if (current && current.status === expected)
        return Promise.resolve(current.status);

      return new Promise((resolve) => {
        const forId = state.listeners.get(clientMessageId) || new Set();
        /** @param {string} status */
        const listener = (status) => {
          if (status === expected) {
            forId.delete(listener);
            resolve(status);
          }
        };
        forId.add(listener);
        state.listeners.set(clientMessageId, forId);
      });
    },

    /**
     * Registers a persistent listener called on every status transition
     * (unlike `waitForStatus`, which fires once for one target status and
     * then detaches) -- the DOM layer uses this to keep a pending row's
     * status text current across "Sending" -> "Retrying" -> "Sent" without
     * having to re-subscribe after each step.
     * @param {string} clientMessageId
     * @param {(status: string) => void} callback
     * @returns {() => void} unsubscribe
     */
    onChange(clientMessageId, callback) {
      const forId = state.listeners.get(clientMessageId) || new Set();
      forId.add(callback);
      state.listeners.set(clientMessageId, forId);
      return () => forId.delete(callback);
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createOnlineMethods(state) {
  function reportOnline() {
    for (const message of state.namespace.messages.values()) {
      if (message.status !== STATUS.RETRYING) continue;
      if (message.timerHandle !== undefined)
        state.clock.clearTimer(message.timerHandle);
      message.nextRetryAt = state.clock.now();
      attemptSend(state, message, {});
    }
  }

  return {
    reportOnline,

    /** @param {string} name */
    reportBrowserEvent(name) {
      if (name === "online") reportOnline();
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createLifecycleMethods(state) {
  return {
    reportAuthExpired() {
      state.draining = false;
    },

    /**
     * External pause/resume seam for `reconnect.js`'s ordered promotion
     * sequence (tech-doc 003: drain must stay paused until the catch-up
     * query and merge both finish, so nothing races ahead of the gap-fill).
     * Shares the same `draining` flag as the auth-expiry pause above --
     * acceptable because both are "stop sending until externally told
     * otherwise" and a real session always re-authenticates (or the page
     * reloads) before a stale pause could ever matter.
     */
    pauseDrain() {
      state.draining = false;
    },

    resumeDrain() {
      state.draining = true;
      resumeOnOpen(state);
    },

    isDraining() {
      return state.draining;
    },

    logout() {
      state.namespace.messages.clear();
      state.namespace.cleared = true;
      state.onLogout?.();
    },

    isCleared() {
      return state.namespace.cleared;
    },
  };
}

/**
 * Creates an outbox bound to one authenticated user's namespace for one room.
 * On construction, resumes draining any message left over from a prior
 * session (tech-doc 003: reopen must not require visitor action).
 *
 * `transport` is the ONLY way a message ever actually reaches the server:
 * every non-simulated `send()` awaits it, so a caller that forgets to pass a
 * real one gets a hard, obvious error rather than a silent fake "Sent" --
 * `family_chat.js` is the one production caller and always supplies the real
 * GraphQL-backed transport from `graphql.js`; FE_UNIT's `family_chat.js`
 * entry point supplies a deterministic test transport instead (see its own
 * comment for why that split is legitimate rather than a hidden fake).
 *
 * @param {{userId: string, roomSlug: string, transport: (message: {clientMessageId: string, body: string}) => Promise<TransportResult>, clock?: import("./clock.js").Clock, onQueueFull?: () => void, onLogout?: () => void, onAuthExpired?: () => void}} options
 */
export function createOutbox({
  userId,
  roomSlug,
  transport,
  clock = createSystemClock(),
  onQueueFull,
  onLogout,
  onAuthExpired,
}) {
  if (typeof transport !== "function") {
    throw new TypeError("createOutbox requires a transport(message) function");
  }

  const namespace = getOrCreateNamespace(namespaceKey(userId, roomSlug));
  const state = createOutboxState({
    namespace,
    clock,
    transport,
    onQueueFull,
    onLogout,
    onAuthExpired,
  });

  resumeOnOpen(state);

  return {
    send: createSendMethod(state),
    ...createReadMethods(state),
    ...createWatchMethods(state),
    ...createTestSeamMethods(state),
    ...createOnlineMethods(state),
    ...createLifecycleMethods(state),
  };
}
