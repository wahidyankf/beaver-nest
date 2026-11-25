// The send transport for `outbox.js` -- split out of `family_chat.js` purely
// to stay under this project's max-lines lint budget.

import { request as graphqlRequest } from "./graphql.js";
import {
  sendFamilyChatMessageMutation,
  NON_RETRYABLE_CODES,
} from "./operations.js";

/**
 * The GraphQL-backed transport: the only path a message ever takes to reach
 * the server, and the one place a server answer is classified for the
 * outbox -- a request that never got an answer is retryable, an expired
 * session pauses the queue, and an error code is terminal or retryable by
 * tech-doc 008's matrix.
 *
 * @param {string} roomSlug
 * @param {{request?: import("./graphql.js").GraphqlRequest}} [options]
 */
export function createRealTransport(
  roomSlug,
  { request = graphqlRequest } = {},
) {
  const document = sendFamilyChatMessageMutation();

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
      response = await request(document, {
        roomSlug,
        clientMessageId,
        body,
        ...(replyToMessageId === undefined ? {} : { replyToMessageId }),
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
