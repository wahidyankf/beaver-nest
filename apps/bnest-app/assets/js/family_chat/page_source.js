// How `history.js` asks for a page of a room's conversation: tech-doc 008's
// `familyChatMessages` query.

import { request as graphqlRequest } from "./graphql.js";
import { familyChatMessagesQuery } from "./operations.js";

/** How many already-read messages to keep above the unread marker. */
export const CONTEXT_PAGE_SIZE = 20;

/** The server's own maximum page size (`BnestApp.FamilyChat`'s `@max_limit`). */
export const MESSAGE_PAGE_SIZE = 50;

/** @typedef {import("./history.js").FetchPage} FetchPage */

/**
 * @param {string} roomSlug
 * @param {{replies?: boolean, request?: import("./graphql.js").GraphqlRequest}} [options]
 * @returns {{fetchPage: FetchPage}}
 */
export function createRealPageSource(
  roomSlug,
  { replies = false, request = graphqlRequest } = {},
) {
  const document = familyChatMessagesQuery({ replies });

  /** @type {FetchPage} */
  async function fetchPage({ beforeId, afterId, limit }) {
    const result = await request(document, {
      roomSlug,
      beforeId: beforeId ?? undefined,
      afterId: afterId ?? undefined,
      limit,
    });
    const page = result.data?.familyChatMessages;
    return {
      nodes: page?.nodes ?? [],
      hasOlder: page?.hasOlder ?? false,
      hasNewer: page?.hasNewer ?? false,
    };
  }

  return { fetchPage };
}
