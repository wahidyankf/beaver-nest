// Test-only seams for `outbox.js` (queue-cap fillers, deterministic backoff
// fixtures, a cross-session-reopen seed) -- split out purely to stay under
// this project's max-lines/max-lines-per-function lint budget. None of this
// is reached by production code; `family_chat.steps.ts`/the unit specs are
// the only callers.

import { computeBackoffDelayMs } from "./backoff.js";
import { createSystemClock } from "./clock.js";
import {
  STATUS,
  namespaceKey,
  getOrCreateNamespace,
  generateClientMessageId,
} from "./outbox_namespace.js";
import { activeCount, attemptSend } from "./outbox_send.js";

/** @typedef {import("./outbox_namespace.js").QueuedMessage} QueuedMessage */

/** @param {import("./outbox_send.js").OutboxState} state */
function createFillMethod(state) {
  return {
    /** @param {number} count */
    async fillWithQueuedMessages(count) {
      await Promise.resolve();
      while (activeCount(state) < count) {
        const clientMessageId = generateClientMessageId(state.clock.random);
        /** @type {QueuedMessage} */
        const filler = {
          clientMessageId,
          body: "filler message",
          status: STATUS.RETRYING,
          attempt: 1,
          retryCount: 0,
          createdAt: state.clock.now(),
          nextRetryAt: state.clock.now() + 60_000,
          neverSucceed: true,
          timerHandle: undefined,
        };
        state.namespace.messages.set(clientMessageId, filler);
      }
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createQueueWithPendingBackoffMethod(state) {
  return {
    async queueWithPendingBackoff() {
      await Promise.resolve();
      const clientMessageId = generateClientMessageId(state.clock.random);
      const delayMs = computeBackoffDelayMs(1, state.clock.random);
      /** @type {QueuedMessage} */
      const message = {
        clientMessageId,
        body: "pending backoff message",
        status: STATUS.RETRYING,
        attempt: 1,
        retryCount: 0,
        createdAt: state.clock.now(),
        nextRetryAt: state.clock.now() + delayMs,
        neverSucceed: false,
        timerHandle: undefined,
      };
      message.timerHandle = state.clock.setTimer(() => {
        message.attempt += 1;
        message.retryCount += 1;
        attemptSend(state, message, {});
      }, delayMs);
      state.namespace.messages.set(clientMessageId, message);
      return clientMessageId;
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createFailRepeatedlyMethod(state) {
  return {
    /** @param {number} times */
    async failRepeatedly(times) {
      await Promise.resolve();
      const clientMessageId = generateClientMessageId(state.clock.random);
      /** @type {QueuedMessage} */
      const message = {
        clientMessageId,
        body: "repeatedly failing message",
        status: STATUS.WAITING,
        attempt: 0,
        retryCount: 0,
        createdAt: state.clock.now(),
        nextRetryAt: 0,
        neverSucceed: false,
        timerHandle: undefined,
      };
      state.namespace.messages.set(clientMessageId, message);

      const delaysMs = [];
      for (let i = 0; i < times; i += 1) {
        message.attempt += 1;
        message.retryCount += 1;
        delaysMs.push(
          computeBackoffDelayMs(message.attempt, state.clock.random),
        );
      }
      message.status = STATUS.RETRYING;
      return delaysMs;
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createQueueFixtureMethods(state) {
  return {
    ...createFillMethod(state),
    ...createQueueWithPendingBackoffMethod(state),
    ...createFailRepeatedlyMethod(state),
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
function createRetryStatusMethods(state) {
  return {
    /** @param {string} clientMessageId */
    isAutoRetrying(clientMessageId) {
      return (
        state.namespace.messages.get(clientMessageId)?.status ===
        STATUS.RETRYING
      );
    },

    /** @param {string} clientMessageId */
    canManuallyRetryOrDiscard(clientMessageId) {
      return (
        state.namespace.messages.get(clientMessageId)?.status === STATUS.FAILED
      );
    },
  };
}

/** @param {import("./outbox_send.js").OutboxState} state */
export function createTestSeamMethods(state) {
  return {
    ...createQueueFixtureMethods(state),
    ...createRetryStatusMethods(state),
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
  await Promise.resolve();
  const namespace = getOrCreateNamespace(namespaceKey(userId, roomSlug));
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
