// Which page of a room's conversation to load, and where to put the visitor
// in it. This is the DOM-independent half of "open where I left off": it
// owns the paging decisions and the read-position writes, while the store it
// is given owns the rendering and the actual scroll (`real_store.js` in a
// browser, `store.js`'s double everywhere else).
//
// The server's own page contract (tech-doc 008's `familyChatMessages`:
// `beforeId` XOR `afterId`, a bounded `limit`, and truthful `hasOlder`/
// `hasNewer`) already expresses everything this needs, so resuming added no
// new query. The one subtlety worth naming: the earlier-context page is
// fetched with `beforeId: <first unread>`, not `beforeId: <last read>` --
// "before the first unread message" is what *includes* the last-read message
// itself, so the visitor lands with the message they stopped on still on
// screen above the marker.
//
// Split into a pager plus two small method-group factories purely to stay
// under this project's max-lines-per-function lint budget; `createHistory`
// composes them and is the only export callers need.

import { CONTEXT_PAGE_SIZE, MESSAGE_PAGE_SIZE } from "./page_source.js";

export { CONTEXT_PAGE_SIZE, MESSAGE_PAGE_SIZE };

/** @typedef {import("./real_store.js").RenderableMessage} RenderableMessage */

/**
 * @typedef {object} MessagePage
 * @property {RenderableMessage[]} [nodes]
 * @property {boolean} [hasOlder]
 * @property {boolean} [hasNewer]
 */

/**
 * @typedef {(cursor: {
 *   beforeId?: string | null,
 *   afterId?: string | null,
 *   limit: number,
 * }) => Promise<MessagePage>} FetchPage
 */

/**
 * Only the store methods this module calls. Both stores implement them; the
 * browser one also implements the pending/reconcile/arrival methods
 * `mount_browser.js` needs, which are none of this module's business.
 * @typedef {object} HistoryStore
 * @property {(messages: RenderableMessage[], hasOlder?: boolean) => void} renderInitial
 * @property {(page: ResumedPage) => void} renderResumed
 * @property {(messages: RenderableMessage[], hasOlder?: boolean) => void} prependOlder
 * @property {(messages: RenderableMessage[], hasNewer?: boolean) => void} appendNewer
 * @property {() => void} scrolledToBottom
 * @property {() => string | null} newestId
 * @property {() => string | null} oldestId
 * @property {() => boolean} hasNewer
 * @property {() => boolean} isAtBottom
 */

/**
 * @typedef {object} ResumedPage
 * @property {RenderableMessage[]} contextNodes already-read messages above the marker
 * @property {RenderableMessage[]} unreadNodes messages committed after the stored position
 * @property {boolean} hasOlder
 * @property {boolean} hasNewer more unread messages exist than this page holds
 */

/**
 * @typedef {object} HistoryOptions
 * @property {FetchPage} fetchPage
 * @property {HistoryStore} store
 * @property {ReturnType<typeof import("./read_marker.js").createReadMarker>} readMarker
 */

/** @typedef {{mode: "latest" | "resumed", newestId: string | null}} LoadResult */

/** @param {HistoryOptions} options */
function createPager({ fetchPage, store, readMarker }) {
  function rememberNewest() {
    readMarker.remember(store.newestId());
  }

  /** @returns {Promise<LoadResult>} */
  async function renderLatest() {
    const page = await fetchPage({ limit: MESSAGE_PAGE_SIZE });
    store.renderInitial(page.nodes ?? [], page.hasOlder);
    // The latest page is rendered at the bottom, so its newest message is on
    // screen by construction.
    rememberNewest();
    return { mode: "latest", newestId: store.newestId() };
  }

  async function loadNewer() {
    if (!store.hasNewer()) return;
    const page = await fetchPage({
      afterId: store.newestId(),
      limit: MESSAGE_PAGE_SIZE,
    });
    store.appendNewer(page.nodes ?? [], page.hasNewer ?? false);
  }

  return { rememberNewest, renderLatest, loadNewer };
}

/**
 * @param {HistoryOptions} options
 * @param {ReturnType<typeof createPager>} pager
 */
function createInitialLoad({ fetchPage, store, readMarker }, pager) {
  return {
    /** @returns {Promise<LoadResult>} */
    async loadInitial() {
      const lastReadId = readMarker.lastReadId();
      if (lastReadId === null) return pager.renderLatest();

      const unread = await fetchPage({
        afterId: lastReadId,
        limit: MESSAGE_PAGE_SIZE,
      });
      const unreadNodes = unread.nodes ?? [];
      // Nothing committed since the stored position -- or a position this
      // room no longer recognizes at all (a restored database, a cleared
      // room, a marker copied between rooms). The newest page is the right
      // landing place for both, so a stale marker degrades instead of
      // showing an empty room.
      if (unreadNodes.length === 0) return pager.renderLatest();

      const context = await fetchPage({
        beforeId: unreadNodes[0]?.id ?? null,
        limit: CONTEXT_PAGE_SIZE,
      });
      store.renderResumed({
        contextNodes: context.nodes ?? [],
        unreadNodes,
        hasOlder: context.hasOlder ?? true,
        hasNewer: unread.hasNewer ?? false,
      });
      // A handful of unread messages can fit entirely on screen, in which
      // case the visitor is already at the bottom the moment the room opens
      // and there is no scroll event coming to record that.
      if (store.isAtBottom()) pager.rememberNewest();
      return { mode: "resumed", newestId: store.newestId() };
    },
  };
}

/**
 * @param {HistoryOptions} options
 * @param {ReturnType<typeof createPager>} pager
 */
function createNavigation({ fetchPage, store }, pager) {
  return {
    loadNewer: pager.loadNewer,

    async loadOlder() {
      const page = await fetchPage({
        beforeId: store.oldestId(),
        limit: MESSAGE_PAGE_SIZE,
      });
      store.prependOlder(page.nodes ?? [], page.hasOlder);
    },

    /** Abandons the resumed window and lands on the newest page instead. */
    async jumpToLatest() {
      await pager.renderLatest();
    },

    /**
     * A message just landed in the rendered list (a live arrival, or our own
     * send being reconciled). It counts as read only if the visitor was at
     * the bottom, where the store has just scrolled it into view.
     */
    noteArrival() {
      if (store.isAtBottom()) pager.rememberNewest();
    },

    /**
     * The one place "the visitor has caught up" is decided. Reaching the
     * bottom of a partially loaded window means there is more to load rather
     * than more that has been read, so the newer page is fetched and the
     * stored position deliberately left where it was.
     */
    async reportScrolledToBottom() {
      store.scrolledToBottom();
      if (store.hasNewer()) {
        await pager.loadNewer();
        return;
      }
      pager.rememberNewest();
    },
  };
}

/** @param {HistoryOptions} options */
export function createHistory(options) {
  const pager = createPager(options);
  return {
    ...createInitialLoad(options, pager),
    ...createNavigation(options, pager),
  };
}
