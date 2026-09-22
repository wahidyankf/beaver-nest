// Send transports for `outbox.js` -- split out of `family_chat.js` purely to
// stay under this project's max-lines lint budget.

import { request as graphqlRequest } from "./graphql.js";
import {
  sendFamilyChatMessageMutation,
  NON_RETRYABLE_CODES,
} from "./operations.js";

/** Real GraphQL-backed transport: the only path a production message ever
 * takes to actually reach the server. */
/**
 * `replies` is the room's reply flag. It gates the document, so with the flag
 * off the mutation does not declare `replyToMessageId` at all and an older
 * slot cannot be sent one.
 * @param {string} roomSlug
 * @param {{replies?: boolean}} [options]
 */
export function createRealTransport(roomSlug, { replies = false } = {}) {
  const document = sendFamilyChatMessageMutation({ replies });

  /**
   * @param {{clientMessageId: string, body: string, replyToMessageId?: string}} message
   * @returns {Promise<import("./outbox.js").TransportResult>}
   */
  return async function realTransport({
    clientMessageId,
    body,
    replyToMessageId,
  }) {
    let response;
    try {
      response = await graphqlRequest(document, {
        roomSlug,
        clientMessageId,
        body,
        ...(replies && replyToMessageId !== undefined
          ? { replyToMessageId }
          : {}),
      });
    } catch {
      return { ok: false, retryable: true };
    }

    if (response.errors?.length) {
      const code = response.errors[0]?.extensions?.code;
      if (code === "UNAUTHENTICATED") return { ok: false, authExpired: true };
      return { ok: false, retryable: !NON_RETRYABLE_CODES.has(code) };
    }

    const message = response.data?.sendFamilyChatMessage;
    return message ? { ok: true, message } : { ok: false, retryable: true };
  };
}

/**
 * FE_UNIT's default transport (tech-doc 006 Proof Matrix: the outbox's
 * queue/status-transition logic is a `@fe-vitest-unit`/`@e2e-exempt` proof,
 * deliberately without a browser or a real server -- see the feature file's
 * own exemption comments). Every scenario that needs a *specific* outcome
 * passes `simulateNetworkFailure` instead, which `outbox.js` intercepts
 * before this transport is ever called; this only has to stand in for "the
 * server accepted it" on the happy path.
 *
 * Resolves on the injected clock's timer (a real macrotask via
 * `createSystemClock`, i.e. never synchronously/via a microtask alone) so a
 * scenario's very next Gherkin step -- checked with no `await` of its own --
 * can still observe the intermediate "Sending" status `attemptSend` sets
 * before this settles, the same way a real network response never resolves
 * within the same turn as the request that triggered it.
 */
/** @param {import("./clock.js").Clock} clock */
export function createTestTransport(clock) {
  /**
   * @param {{clientMessageId: string, body: string}} message
   * @returns {Promise<import("./outbox.js").TransportResult>}
   */
  return function testTransport({ clientMessageId, body }) {
    return new Promise((resolve) => {
      clock.setTimer(
        () => resolve({ ok: true, message: { id: clientMessageId, body } }),
        0,
      );
    });
  };
}
