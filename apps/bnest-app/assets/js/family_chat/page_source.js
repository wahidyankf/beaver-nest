// The two ways `history.js` can ask for a page of a room's conversation.
//
// `createRealPageSource` is the only one a browser ever uses: it issues
// tech-doc 008's `familyChatMessages` query. `createTestPageSource` is the
// FE_UNIT counterpart (same role `transport.js`'s `createTestTransport` plays
// for sends): a deterministic in-memory room that reproduces the server's own
// cursor contract exactly -- ascending nodes, `beforeId`/`afterId` exclusive,
// `hasOlder`/`hasNewer` computed from what the cursor actually excluded --
// so the paging decisions proven without a browser are proven against the
// real contract rather than a convenient approximation of it.

import { request as graphqlRequest } from "./graphql.js";
import { familyChatMessagesQuery } from "./operations.js";

/** How many already-read messages to keep above the unread marker. */
export const CONTEXT_PAGE_SIZE = 20;

/** The server's own maximum page size (`BnestApp.FamilyChat`'s `@max_limit`). */
export const MESSAGE_PAGE_SIZE = 50;

/** @typedef {import("./real_store.js").RenderableMessage} RenderableMessage */
/** @typedef {import("./history.js").FetchPage} FetchPage */

/**
 * @param {string} roomSlug
 * @param {{replies?: boolean}} [options]
 * @returns {{fetchPage: FetchPage}}
 */
export function createRealPageSource(roomSlug, { replies = false } = {}) {
  const document = familyChatMessagesQuery({ replies });

  /** @type {FetchPage} */
  async function fetchPage({ beforeId, afterId, limit }) {
    const result = await graphqlRequest(document, {
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

/** @param {RenderableMessage} message */
function numericId(message) {
  return Number(message.id ?? 0);
}

/**
 * A growable in-memory room. `append` exists so a scenario can say "messages
 * arrived while the visitor was away" between two opens of the same room,
 * which is the whole precondition resuming is about.
 * @param {RenderableMessage[]} [seed]
 */
export function createTestPageSource(seed = []) {
  /** @type {RenderableMessage[]} */
  const messages = [...seed];

  /** @type {FetchPage} */
  async function fetchPage({ beforeId, afterId, limit }) {
    await Promise.resolve();
    const ordered = messages.toSorted((a, b) => numericId(a) - numericId(b));

    if (afterId !== undefined && afterId !== null) {
      const cursor = Number(afterId);
      const newer = ordered.filter((message) => numericId(message) > cursor);
      return {
        nodes: newer.slice(0, limit),
        hasOlder: ordered.some((message) => numericId(message) < cursor),
        hasNewer: newer.length > limit,
      };
    }

    const upTo =
      beforeId === undefined || beforeId === null
        ? ordered
        : ordered.filter((message) => numericId(message) < Number(beforeId));
    return {
      nodes: upTo.slice(Math.max(0, upTo.length - limit)),
      hasOlder: upTo.length > limit,
      hasNewer: beforeId !== undefined && beforeId !== null,
    };
  }

  return {
    fetchPage,

    /** @param {RenderableMessage[]} arrivals */
    append(arrivals) {
      messages.push(...arrivals);
    },

    /** @returns {RenderableMessage[]} */
    all() {
      return messages.toSorted((a, b) => numericId(a) - numericId(b));
    },
  };
}

/**
 * Builds `count` committed messages whose ids continue from `startId`,
 * matching the shape `real_store.js` renders.
 * @param {{startId: number, count: number, body: string, senderId?: string, senderDisplayName?: string}} options
 * @returns {RenderableMessage[]}
 */
export function buildTestMessages({
  startId,
  count,
  body,
  senderId = "test-user-family-chat-other",
  senderDisplayName = "Other member",
}) {
  return Array.from({ length: count }, (_unused, index) => ({
    id: String(startId + index),
    body: `${body} ${index + 1}`,
    senderKind: "user",
    senderId,
    senderDisplayName,
    committedAt: new Date(
      Date.UTC(2026, 0, 1, 0, 0, startId + index),
    ).toISOString(),
  }));
}
