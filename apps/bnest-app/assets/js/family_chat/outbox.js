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
  hydrateNamespace,
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

export { STATUS, seedQueuedMessage, namespaceKey, hydrateNamespace };
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
    // Durable from the moment it's queued, not just once it starts sending
    // (see `notify`'s own comment): a `send()` that lands while draining is
    // paused (e.g. auth already expired) would otherwise never notify, and
    // never persist, before a real reload could lose it.
    state.persistence?.save(state.namespaceKey, message);

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

    /**
     * Every message still in this namespace (never yet reached "Sent" --
     * `scheduleDeletion` removes those). `mount_browser.js`'s own mount
     * sequence uses this once, right after the initial history load, to
     * render whatever `resumeOnOpen` (see `outbox_send.js`) already resumed
     * draining on construction -- a message left over from a closed tab
     * (real IndexedDB) or an already-paused one from this same session --
     * so a resumed send is visible on screen, not just resumed internally.
     * @returns {{clientMessageId: string, body: string, status: string}[]}
     */
    pendingMessages() {
      return Array.from(state.namespace.messages.values()).map((message) => ({
        clientMessageId: message.clientMessageId,
        body: message.body,
        status: message.status,
      }));
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
      state.persistence?.clear(state.namespaceKey);
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
 * `persistence` is the real cross-reload durability seam (tech-doc 003 /
 * `outbox_send.js`'s `Persistence` typedef): `family_chat.js` is the only
 * caller that ever passes one, and only on its `hasDocument` branch (real
 * IndexedDB, via `persistence_indexeddb.js`) or when a test explicitly
 * injects a fake one. Omitting it (every existing FE_UNIT scenario but the
 * ones proving this contract) keeps the outbox exactly as in-memory-only as
 * before.
 *
 * @param {{userId: string, roomSlug: string, transport: (message: {clientMessageId: string, body: string}) => Promise<TransportResult>, clock?: import("./clock.js").Clock, persistence?: import("./outbox_send.js").Persistence | undefined, onQueueFull?: () => void, onLogout?: () => void, onAuthExpired?: () => void}} options
 */
export function createOutbox({
  userId,
  roomSlug,
  transport,
  clock = createSystemClock(),
  persistence,
  onQueueFull,
  onLogout,
  onAuthExpired,
}) {
  if (typeof transport !== "function") {
    throw new TypeError("createOutbox requires a transport(message) function");
  }

  const key = namespaceKey(userId, roomSlug);
  const namespace = getOrCreateNamespace(key);
  const state = createOutboxState({
    namespace,
    namespaceKey: key,
    persistence,
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
