// A deterministic in-memory room for `history.js`'s plain unit tests: it
// reproduces the server's own cursor contract exactly -- ascending nodes,
// `beforeId`/`afterId` exclusive, `hasOlder`/`hasNewer` computed from what
// the cursor actually excluded -- so the paging decisions are proven against
// the real contract rather than a convenient approximation of it. The
// Gherkin harness uses `graphql_server.ts`, which answers the same contract
// over GraphQL.

type RenderableMessage =
  import("../../js/family_chat/real_store.js").RenderableMessage;
type FetchPage = import("../../js/family_chat/history.js").FetchPage;

function numericId(message: RenderableMessage): number {
  return Number(message.id ?? 0);
}

/**
 * A growable in-memory room. `append` exists so a test can say "messages
 * arrived while the visitor was away" between two opens of the same room.
 */
export function createTestPageSource(seed: RenderableMessage[] = []) {
  const messages: RenderableMessage[] = [...seed];

  const fetchPage: FetchPage = async ({ beforeId, afterId, limit }) => {
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
  };

  return {
    fetchPage,
    append(arrivals: RenderableMessage[]): void {
      messages.push(...arrivals);
    },
    all(): RenderableMessage[] {
      return messages.toSorted((a, b) => numericId(a) - numericId(b));
    },
  };
}

/**
 * Builds `count` committed messages whose ids continue from `startId`,
 * matching the shape `real_store.js` renders.
 */
export function buildTestMessages({
  startId,
  count,
  body,
  senderId = "test-user-family-chat-other",
  senderDisplayName = "Other member",
}: {
  startId: number;
  count: number;
  body: string;
  senderId?: string;
  senderDisplayName?: string;
}): RenderableMessage[] {
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
