// A store double for `history.js`'s plain unit tests: it implements the
// `HistoryStore` contract `history.js` calls (the browser implements it in
// `real_store.js`) and records what it was asked to render, so a test can
// read back which page the room landed on without a DOM.

type RenderableMessage =
  import("../../js/family_chat/real_store.js").RenderableMessage;
type ResumedPage = import("../../js/family_chat/history.js").ResumedPage;

function idOf(message: RenderableMessage): string {
  return message.id ?? message.clientMessageId ?? "";
}

export function createHistoryStore() {
  let ids: string[] = [];
  let contextCount = 0;
  let dividerBeforeId: string | null = null;
  let positionedOnId: string | null = null;
  let hasOlder = false;
  let hasNewer = false;
  let atBottom = true;

  return {
    renderInitial(messages: RenderableMessage[], older?: boolean): void {
      ids = messages.map(idOf);
      contextCount = 0;
      dividerBeforeId = null;
      hasOlder = messages.length === 0 ? false : (older ?? true);
      hasNewer = false;
      positionedOnId = ids.at(-1) ?? null;
      atBottom = true;
    },

    renderResumed({
      contextNodes,
      unreadNodes,
      hasOlder: older,
      hasNewer: newer,
    }: ResumedPage): void {
      ids = [...contextNodes, ...unreadNodes].map(idOf);
      contextCount = contextNodes.length;
      dividerBeforeId = unreadNodes[0] ? idOf(unreadNodes[0]) : null;
      hasOlder = older;
      hasNewer = newer;
      positionedOnId = dividerBeforeId;
      atBottom = false;
    },

    prependOlder(messages: RenderableMessage[], older?: boolean): void {
      ids = [...messages.map(idOf), ...ids];
      contextCount += messages.length;
      hasOlder = Boolean(older);
    },

    appendNewer(messages: RenderableMessage[], newer?: boolean): void {
      ids = [...ids, ...messages.map(idOf)];
      hasNewer = Boolean(newer);
      atBottom = false;
    },

    scrolledToBottom(): void {
      atBottom = true;
      if (!hasNewer) positionedOnId = ids.at(-1) ?? null;
    },

    newestId: (): string | null => ids.at(-1) ?? null,
    oldestId: (): string | null => ids[0] ?? null,
    hasNewer: (): boolean => hasNewer,
    hasOlder: (): boolean => hasOlder,
    isAtBottom: (): boolean => atBottom,
    hasRendered: (id: string): boolean => ids.includes(id),

    /** The message the room placed the visitor on. */
    firstMessageInViewId: (): string | null => positionedOnId,
    /** The id the unread marker sits immediately above, if it is shown. */
    unreadDividerBeforeId: (): string | null => dividerBeforeId,
    /** How many already-read messages were loaded above the unread marker. */
    contextCount: (): number => contextCount,
  };
}
