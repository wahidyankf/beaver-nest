// The per-instance send/retry state machine behind `outbox.js`'s public API
// (tech-doc 003) -- split out purely to stay under this project's
// max-lines/max-lines-per-function lint budget. `outbox.js` composes these
// functions with `outbox_namespace.js`'s storage into the public `send`,
// `reportOnline`, etc. methods; nothing here is meant to be imported by
// feature code directly.

import { computeBackoffDelayMs } from "./backoff.js";
import { STATUS } from "./outbox_namespace.js";

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * @typedef {object} TransportResult
 * @property {boolean} ok
 * @property {boolean} [retryable] present and meaningful only when `ok` is false.
 * @property {boolean} [authExpired] true when the server reported the session itself
 *   as no longer valid (GraphQL `UNAUTHENTICATED`), distinct from an ordinary
 *   retryable/terminal per-message failure.
 * @property {object} [message] the server's committed message, present only when `ok`.
 */

/**
 * @typedef {object} SendOptions
 * @property {"retryable"|"non-retryable"} [simulateNetworkFailure] test-only
 *   per-call override; see `attemptSend`'s own comment.
 * @property {string} [replyToMessageId] the server ID of the message this one
 *   answers. Absent for an ordinary message.
 */

/**
 * The real-IndexedDB-vs-Node split lives entirely in `family_chat.js` (see
 * `persistence_indexeddb.js`'s own header comment) -- `outbox.js`/this file
 * only ever see this narrow write-through contract, which is why FE_UNIT can
 * prove the contract itself with a plain in-memory fake.
 * @typedef {{
 *   loadAll(namespace: string): Promise<import("./outbox_namespace.js").QueuedMessage[]>,
 *   save(namespace: string, message: import("./outbox_namespace.js").QueuedMessage): void,
 *   remove(namespace: string, clientMessageId: string): void,
 *   clear(namespace: string): void,
 * }} Persistence
 */

/**
 * @typedef {{
 *   namespace: import("./outbox_namespace.js").NamespaceRecord,
 *   namespaceKey: string,
 *   persistence: Persistence | undefined,
 *   listeners: Map<string, Set<(status: string) => void>>,
 *   committed: Map<string, object>,
 *   clock: import("./clock.js").Clock,
 *   transport: (message: {clientMessageId: string, body: string, replyToMessageId?: string}) => Promise<TransportResult>,
 *   onQueueFull: (() => void) | undefined,
 *   onLogout: (() => void) | undefined,
 *   onAuthExpired: (() => void) | undefined,
 *   draining: boolean,
 * }} OutboxState
 */

/**
 * @param {{namespace: import("./outbox_namespace.js").NamespaceRecord, namespaceKey: string, persistence?: Persistence | undefined, clock: import("./clock.js").Clock, transport: OutboxState["transport"], onQueueFull?: (() => void) | undefined, onLogout?: (() => void) | undefined, onAuthExpired?: (() => void) | undefined}} options
 * @returns {OutboxState}
 */
export function createOutboxState({
  namespace,
  namespaceKey,
  persistence,
  clock,
  transport,
  onQueueFull,
  onLogout,
  onAuthExpired,
}) {
  return {
    namespace,
    namespaceKey,
    persistence,
    listeners: new Map(),
    committed: new Map(),
    clock,
    transport,
    onQueueFull,
    onLogout,
    onAuthExpired,
    // Per-instance, not per-namespace: a fresh `initRoom` call represents a
    // new page load behind an already-revalidated session, so it always
    // resumes draining even if a *previous* instance's session had expired.
    draining: true,
  };
}

/**
 * Every status mutation in this file calls `notify` right after, so this is
 * also the one write-through point for durability (tech-doc 003's promised
 * cross-reload persistence): a message that reaches "Waiting"/"Retrying" is
 * durable from here on, regardless of which transition produced it.
 * @param {OutboxState} state @param {import("./outbox_namespace.js").QueuedMessage} message
 */
function notify(state, message) {
  state.persistence?.save(state.namespaceKey, message);
  const forId = state.listeners.get(message.clientMessageId);
  if (forId) {
    for (const listener of forId) listener(message.status);
  }
}

/** @param {OutboxState} state @param {import("./outbox_namespace.js").QueuedMessage} message */
function isExpired(state, message) {
  return state.clock.now() - message.createdAt > SEVEN_DAYS_MS;
}

/** @param {OutboxState} state */
export function activeCount(state) {
  return Array.from(state.namespace.messages.values()).filter(
    (m) => m.status !== STATUS.SENT,
  ).length;
}

/** @param {OutboxState} state @param {import("./outbox_namespace.js").QueuedMessage} message */
function scheduleDeletion(state, message) {
  state.clock.setTimer(() => {
    state.namespace.messages.delete(message.clientMessageId);
    state.persistence?.remove(state.namespaceKey, message.clientMessageId);
  }, 0);
}

/** @param {OutboxState} state @param {import("./outbox_namespace.js").QueuedMessage} message */
function scheduleRetry(state, message) {
  message.status = STATUS.RETRYING;
  notify(state, message);
  const delayMs = computeBackoffDelayMs(
    message.attempt + 1,
    state.clock.random,
  );
  message.nextRetryAt = state.clock.now() + delayMs;
  message.timerHandle = state.clock.setTimer(() => {
    message.attempt += 1;
    message.retryCount += 1;
    attemptSend(state, message, {});
  }, delayMs);
}

/**
 * @param {OutboxState} state
 * @param {import("./outbox_namespace.js").QueuedMessage} message
 * @param {TransportResult} result
 */
function handleTransportResult(state, message, result) {
  if (result.ok) {
    message.status = STATUS.SENT;
    // Kept independent of `namespace.messages` (which `scheduleDeletion`
    // clears right after): the browser layer reconciles the pending DOM row
    // against this real committed message (server ID, canonical fields)
    // once, from the same send that produced it -- never by guessing from a
    // later subscription push, which tech-doc 008 deliberately never
    // carries the client-chosen ID on at all.
    if (result.message)
      state.committed.set(message.clientMessageId, result.message);
    notify(state, message);
    scheduleDeletion(state, message);
    return;
  }

  if (result.authExpired) {
    state.onAuthExpired?.();
    state.draining = false;
    message.status = STATUS.RETRYING;
    notify(state, message);
    return;
  }

  if (result.retryable) {
    scheduleRetry(state, message);
    return;
  }

  message.status = STATUS.FAILED;
  notify(state, message);
}

/**
 * @param {OutboxState} state
 * @param {import("./outbox_namespace.js").QueuedMessage} message
 * @param {SendOptions} opts
 */
export async function attemptSend(state, message, opts) {
  if (!state.draining) return;

  message.status = STATUS.SENDING;
  notify(state, message);

  // Test-only per-call override (see `family_chat.steps.ts`): lets FE_UNIT
  // force a specific outcome deterministically without needing a fake
  // transport wired for every scenario. Production callers
  // (`family_chat.js`) never pass this.
  if (message.neverSucceed || opts.simulateNetworkFailure === "retryable") {
    scheduleRetry(state, message);
    return;
  }

  if (opts.simulateNetworkFailure === "non-retryable") {
    message.status = STATUS.FAILED;
    notify(state, message);
    return;
  }

  // The only path that actually reaches the server: every real send/retry
  // goes through the injected transport, so "Sent" here always means a real
  // committed acknowledgement, never an assumed success.
  let result;
  try {
    result = await state.transport({
      clientMessageId: message.clientMessageId,
      body: message.body,
      // Same optional-by-absence rule as the queued record itself: a
      // transport never sees the key unless there is a target.
      ...(message.replyToMessageId === undefined
        ? {}
        : { replyToMessageId: message.replyToMessageId }),
    });
  } catch {
    result = { ok: false, retryable: true };
  }

  handleTransportResult(state, message, result);
}

/** @param {OutboxState} state */
export function resumeOnOpen(state) {
  if (state.namespace.cleared) return;
  for (const message of state.namespace.messages.values()) {
    if (message.status === STATUS.SENT || message.status === STATUS.FAILED)
      continue;

    if (isExpired(state, message)) {
      message.status = STATUS.FAILED;
      notify(state, message);
      continue;
    }

    if (message.timerHandle !== undefined)
      state.clock.clearTimer(message.timerHandle);
    attemptSend(state, message, {});
  }
}
