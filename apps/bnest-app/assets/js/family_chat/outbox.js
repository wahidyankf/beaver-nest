// The browser-owned send outbox (tech-doc 003's state machine): every
// composed message is queued locally first, then drained toward the server.
// State is kept in one module-scoped, namespace-keyed store (namespace =
// `${userId}:${roomSlug}`), which survives across `initRoom` calls within
// the same browser session/process (a live tab, or one Vitest process) but
// NOT a real tab close/reopen -- no real IndexedDB binding exists yet (see
// `family_chat.js`'s header comment's "KNOWN GAP" note); this module's
// DOM-independent, logic-first design (`vitest.config.mts` runs these
// modules under `environment: "node"`, with no DOM/IndexedDB at all) is
// otherwise ready for one to be added without changing this file's own
// public API.

import { computeBackoffDelayMs } from "./backoff.js";
import { createSystemClock } from "./clock.js";

export const QUEUE_SCHEMA_VERSION = 1;
export const MAX_QUEUED_PER_ROOM = 100;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

export const STATUS = Object.freeze({
  WAITING: "Waiting for connection",
  SENDING: "Sending",
  RETRYING: "Retrying in …",
  SENT: "Sent",
  FAILED: "Couldn't send",
});

/** @type {Map<string, NamespaceRecord>} */
const namespaces = new Map();

/**
 * @typedef {object} NamespaceRecord
 * @property {Map<string, QueuedMessage>} messages
 * @property {boolean} cleared
 */

/**
 * @typedef {object} QueuedMessage
 * @property {string} clientMessageId
 * @property {string} body
 * @property {string} status
 * @property {number} attempt
 * @property {number} retryCount
 * @property {number} createdAt
 * @property {number} nextRetryAt
 * @property {boolean} neverSucceed
 * @property {unknown} timerHandle
 */

function namespaceKey(userId, roomSlug) {
  return `${userId}:${roomSlug}`;
}

function getOrCreateNamespace(key) {
  let record = namespaces.get(key);
  if (!record) {
    record = { messages: new Map(), cleared: false };
    namespaces.set(key, record);
  }
  return record;
}

function generateClientMessageId(random) {
  const hex = () => Math.floor(random() * 16).toString(16);
  const block = (length) => Array.from({ length }, hex).join("");
  return `${block(8)}-${block(4)}-4${block(3)}-${(8 + Math.floor(random() * 4)).toString(16)}${block(3)}-${block(12)}`;
}

/**
 * @typedef {object} TransportResult
 * @property {boolean} ok
 * @property {boolean} [retryable] present and meaningful only when `ok` is false.
 * @property {boolean} [authExpired] true when the server reported the session itself
 *   as no longer valid (GraphQL `UNAUTHENTICATED`), distinct from an ordinary
 *   retryable/terminal per-message failure.
 */

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

  const key = namespaceKey(userId, roomSlug);
  const namespace = getOrCreateNamespace(key);
  const listeners = new Map();
  /** @type {Map<string, object>} clientMessageId -> the server's committed message. */
  const committed = new Map();
  // Per-instance, not per-namespace: a fresh `initRoom` call represents a new
  // page load behind an already-revalidated session, so it always resumes
  // draining even if a *previous* instance's session had expired.
  let draining = true;

  function notify(message) {
    const forId = listeners.get(message.clientMessageId);
    if (forId) {
      for (const listener of forId) listener(message.status);
    }
  }

  function isExpired(message) {
    return clock.now() - message.createdAt > SEVEN_DAYS_MS;
  }

  function activeCount() {
    return Array.from(namespace.messages.values()).filter(
      (m) => m.status !== STATUS.SENT,
    ).length;
  }

  function scheduleDeletion(message) {
    clock.setTimer(() => namespace.messages.delete(message.clientMessageId), 0);
  }

  function scheduleRetry(message) {
    message.status = STATUS.RETRYING;
    notify(message);
    const delayMs = computeBackoffDelayMs(message.attempt + 1, clock.random);
    message.nextRetryAt = clock.now() + delayMs;
    message.timerHandle = clock.setTimer(() => {
      message.attempt += 1;
      message.retryCount += 1;
      attemptSend(message, {});
    }, delayMs);
  }

  async function attemptSend(message, opts) {
    if (!draining) return;

    message.status = STATUS.SENDING;
    notify(message);

    // Test-only per-call override (see `family_chat.steps.ts`): lets FE_UNIT
    // force a specific outcome deterministically without needing a fake
    // transport wired for every scenario. Production callers (`family_chat.js`)
    // never pass this.
    if (message.neverSucceed || opts.simulateNetworkFailure === "retryable") {
      scheduleRetry(message);
      return;
    }

    if (opts.simulateNetworkFailure === "non-retryable") {
      message.status = STATUS.FAILED;
      notify(message);
      return;
    }

    // The only path that actually reaches the server: every real send/retry
    // goes through the injected transport, so "Sent" here always means a
    // real committed acknowledgement, never an assumed success.
    let result;
    try {
      result = await transport({
        clientMessageId: message.clientMessageId,
        body: message.body,
      });
    } catch {
      result = { ok: false, retryable: true };
    }

    if (result.ok) {
      message.status = STATUS.SENT;
      // Kept independent of `namespace.messages` (which `scheduleDeletion`
      // clears right after): the browser layer reconciles the pending DOM
      // row against this real committed message (server ID, canonical
      // fields) once, from the same send that produced it -- never by
      // guessing from a later subscription push, which tech-doc 008
      // deliberately never carries the client-chosen ID on at all.
      if (result.message)
        committed.set(message.clientMessageId, result.message);
      notify(message);
      scheduleDeletion(message);
      return;
    }

    if (result.authExpired) {
      onAuthExpired?.();
      draining = false;
      message.status = STATUS.RETRYING;
      notify(message);
      return;
    }

    if (result.retryable) {
      scheduleRetry(message);
      return;
    }

    message.status = STATUS.FAILED;
    notify(message);
  }

  function resumeOnOpen() {
    if (namespace.cleared) return;
    for (const message of namespace.messages.values()) {
      if (message.status === STATUS.SENT || message.status === STATUS.FAILED)
        continue;

      if (isExpired(message)) {
        message.status = STATUS.FAILED;
        notify(message);
        continue;
      }

      if (message.timerHandle !== undefined)
        clock.clearTimer(message.timerHandle);
      attemptSend(message, {});
    }
  }

  resumeOnOpen();

  return {
    /** @returns {Promise<string|null>} the new clientMessageId, or null if the room's queue is full. */
    async send(body, opts = {}) {
      if (activeCount() >= MAX_QUEUED_PER_ROOM) {
        onQueueFull?.();
        return null;
      }

      const clientMessageId = generateClientMessageId(clock.random);
      const message = {
        clientMessageId,
        body,
        status: STATUS.WAITING,
        attempt: 0,
        retryCount: 0,
        createdAt: clock.now(),
        nextRetryAt: 0,
        neverSucceed: false,
        timerHandle: undefined,
      };
      namespace.messages.set(clientMessageId, message);

      // Deliberately not awaited: `attemptSend` runs synchronously up to its
      // first `await` (marking the message "Sending" before yielding), so a
      // caller that reads `status()` immediately after `send()` resolves
      // observes "Sending" -- the way a real network round trip looks --
      // while the eventual "Sent"/"Retrying"/"Couldn't send" transition
      // happens once the transport's own promise settles, observed via
      // `waitForStatus`.
      void attemptSend(message, opts);
      return clientMessageId;
    },

    /** @returns {object|null} the real committed message once `send()` succeeded, else null. */
    committedMessage(clientMessageId) {
      return committed.get(clientMessageId) ?? null;
    },

    status(clientMessageId) {
      const message = namespace.messages.get(clientMessageId);
      return message ? message.status : "not-found";
    },

    /** @returns {Promise<string>} resolves once the message reaches `expected` (or is already there). */
    waitForStatus(clientMessageId, expected) {
      const current = namespace.messages.get(clientMessageId);
      if (current && current.status === expected)
        return Promise.resolve(current.status);

      return new Promise((resolve) => {
        const forId = listeners.get(clientMessageId) || new Set();
        const listener = (status) => {
          if (status === expected) {
            forId.delete(listener);
            resolve(status);
          }
        };
        forId.add(listener);
        listeners.set(clientMessageId, forId);
      });
    },

    /**
     * Registers a persistent listener called on every status transition
     * (unlike `waitForStatus`, which fires once for one target status and
     * then detaches) -- the DOM layer uses this to keep a pending row's
     * status text current across "Sending" -> "Retrying" -> "Sent" without
     * having to re-subscribe after each step.
     * @returns {() => void} unsubscribe
     */
    onChange(clientMessageId, callback) {
      const forId = listeners.get(clientMessageId) || new Set();
      forId.add(callback);
      listeners.set(clientMessageId, forId);
      return () => forId.delete(callback);
    },

    retryCount(clientMessageId) {
      return namespace.messages.get(clientMessageId)?.retryCount ?? 0;
    },

    nextRetryEtaMs(clientMessageId) {
      const message = namespace.messages.get(clientMessageId);
      return message ? message.nextRetryAt - clock.now() : 0;
    },

    async fillWithQueuedMessages(count) {
      while (activeCount() < count) {
        const clientMessageId = generateClientMessageId(clock.random);
        namespace.messages.set(clientMessageId, {
          clientMessageId,
          body: "filler message",
          status: STATUS.RETRYING,
          attempt: 1,
          retryCount: 0,
          createdAt: clock.now(),
          nextRetryAt: clock.now() + 60_000,
          neverSucceed: true,
          timerHandle: undefined,
        });
      }
    },

    async queueWithPendingBackoff() {
      const clientMessageId = generateClientMessageId(clock.random);
      const delayMs = computeBackoffDelayMs(1, clock.random);
      const message = {
        clientMessageId,
        body: "pending backoff message",
        status: STATUS.RETRYING,
        attempt: 1,
        retryCount: 0,
        createdAt: clock.now(),
        nextRetryAt: clock.now() + delayMs,
        neverSucceed: false,
        timerHandle: undefined,
      };
      message.timerHandle = clock.setTimer(() => {
        message.attempt += 1;
        message.retryCount += 1;
        attemptSend(message, {});
      }, delayMs);
      namespace.messages.set(clientMessageId, message);
      return clientMessageId;
    },

    reportOnline() {
      for (const message of namespace.messages.values()) {
        if (message.status !== STATUS.RETRYING) continue;
        if (message.timerHandle !== undefined)
          clock.clearTimer(message.timerHandle);
        message.nextRetryAt = clock.now();
        attemptSend(message, {});
      }
    },

    reportBrowserEvent(name) {
      if (name === "online") this.reportOnline();
    },

    reportAuthExpired() {
      draining = false;
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
      draining = false;
    },

    resumeDrain() {
      draining = true;
      resumeOnOpen();
    },

    isDraining() {
      return draining;
    },

    async failRepeatedly(times) {
      const clientMessageId = generateClientMessageId(clock.random);
      const message = {
        clientMessageId,
        body: "repeatedly failing message",
        status: STATUS.WAITING,
        attempt: 0,
        retryCount: 0,
        createdAt: clock.now(),
        nextRetryAt: 0,
        neverSucceed: false,
        timerHandle: undefined,
      };
      namespace.messages.set(clientMessageId, message);

      const delaysMs = [];
      for (let i = 0; i < times; i += 1) {
        message.attempt += 1;
        message.retryCount += 1;
        delaysMs.push(computeBackoffDelayMs(message.attempt, clock.random));
      }
      message.status = STATUS.RETRYING;
      return delaysMs;
    },

    isAutoRetrying(clientMessageId) {
      return (
        namespace.messages.get(clientMessageId)?.status === STATUS.RETRYING
      );
    },

    canManuallyRetryOrDiscard(clientMessageId) {
      return namespace.messages.get(clientMessageId)?.status === STATUS.FAILED;
    },

    logout() {
      namespace.messages.clear();
      namespace.cleared = true;
      onLogout?.();
    },

    isCleared() {
      return namespace.cleared;
    },
  };
}

/**
 * Test-only seam (per `family_chat.steps.ts`): writes a queued message
 * directly into a namespace's persisted state, simulating one left over from
 * a closed browser session, without going through a live `outbox.send()`.
 *
 * @param {{ageMs: number, userId?: string, roomSlug?: string, clock?: import("./clock.js").Clock}} options
 */
export async function seedQueuedMessage({
  ageMs,
  userId = "test-user-family-chat",
  roomSlug = "ruang-keluarga",
  clock = createSystemClock(),
}) {
  const key = namespaceKey(userId, roomSlug);
  const namespace = getOrCreateNamespace(key);
  const clientMessageId = generateClientMessageId(clock.random);

  namespace.messages.set(clientMessageId, {
    clientMessageId,
    body: "seeded message",
    status: STATUS.WAITING,
    attempt: 0,
    retryCount: 0,
    createdAt: clock.now() - ageMs,
    nextRetryAt: 0,
    neverSucceed: false,
    timerHandle: undefined,
  });

  return { clientMessageId, userId, roomSlug };
}
