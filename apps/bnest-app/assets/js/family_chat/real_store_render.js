// The rendering half of the real (browser) message-list store: the two
// landing places a room can open on, and the two ways its window can grow.
// Split out of `real_store.js` purely to stay under this project's
// max-lines/max-lines-per-function lint budget; `real_store.js` composes
// everything here with the pending/reconcile/arrival methods and is the only
// importer.

import {
  isNearBottom,
  messageNode,
  scrollToBottom,
  scrollToResumeAnchor,
  setHasOlder,
  setNewMessagesIndicator,
  unreadDividerNode,
} from "./message_render.js";

/** @typedef {import("./message_render.js").RenderableMessage} RenderableMessage */

/**
 * `newestKnownId`/`hasNewer` are the resumed window's own bookkeeping: while
 * `hasNewer` is true the rendered list deliberately stops short of the
 * newest committed message, so nothing may be appended to it that is not
 * contiguous with `newestKnownId` (see `receiveRemoteMessage`).
 * @typedef {{
 *   rendered: Map<string, HTMLLIElement>,
 *   lastAnnouncement: string | null,
 *   newMessagesLabel: string | null,
 *   oldestKnownId: string | null,
 *   newestKnownId: string | null,
 *   hasNewer: boolean,
 *   atBottom: boolean,
 * }} RealStoreState
 */

/** @param {RenderableMessage} message */
export function keyOf(message) {
  return message.id ?? message.clientMessageId ?? "";
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 * @param {RenderableMessage[]} messages
 */
export function appendMessages(elements, state, currentUserId, messages) {
  const fragment = document.createDocumentFragment();
  for (const message of messages) {
    const node = messageNode(message, { pending: false, currentUserId });
    fragment.append(node);
    state.rendered.set(keyOf(message), node);
  }
  elements.list.append(fragment);
  const oldest = messages[0];
  const newest = messages.at(-1);
  if (oldest) state.oldestKnownId ??= keyOf(oldest);
  if (newest) state.newestKnownId = keyOf(newest);
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function resetWindow(elements, state) {
  elements.list.replaceChildren();
  state.rendered.clear();
  state.oldestKnownId = null;
  state.newestKnownId = null;
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
export function createInitialRenderMethods(elements, state, currentUserId) {
  return {
    empty() {
      return state.rendered.size === 0;
    },

    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasOlder]
     */
    renderInitial(messages, hasOlder) {
      resetWindow(elements, state);
      state.hasNewer = false;
      state.newMessagesLabel = null;
      setNewMessagesIndicator(elements, false);
      appendMessages(elements, state, currentUserId, messages);
      elements.empty.hidden = messages.length > 0;
      // An empty room has nothing earlier to load regardless of what the
      // query reported; otherwise trust the server's own `hasOlder` flag,
      // defaulting to true (safe: still offers the button) if a caller ever
      // omits it.
      setHasOlder(elements, messages.length === 0 ? false : (hasOlder ?? true));
      // The newest page opens at its newest message, never at the top of
      // whatever happened to be fetched.
      scrollToBottom(elements);
      state.atBottom = true;
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
export function createResumeRenderMethods(elements, state, currentUserId) {
  return {
    /** @param {import("./history.js").ResumedPage} page */
    renderResumed({ contextNodes, unreadNodes, hasOlder, hasNewer }) {
      resetWindow(elements, state);
      state.hasNewer = hasNewer;

      appendMessages(elements, state, currentUserId, contextNodes);
      const divider = unreadDividerNode();
      elements.list.append(divider);
      appendMessages(elements, state, currentUserId, unreadNodes);

      elements.empty.hidden = true;
      setHasOlder(elements, hasOlder);
      // More unread messages exist than this window holds, so the indicator
      // stays up as the way back to the newest one.
      state.newMessagesLabel = hasNewer ? "New messages below" : null;
      setNewMessagesIndicator(elements, hasNewer);
      scrollToResumeAnchor(elements, divider);
      state.atBottom = isNearBottom(elements);
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
export function createPrependOlderMethods(elements, state, currentUserId) {
  return {
    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasOlder]
     */
    prependOlder(messages, hasOlder) {
      setHasOlder(elements, Boolean(hasOlder));
      if (messages.length === 0) return;
      const anchor = elements.list.firstElementChild;
      const anchorOffset = anchor ? anchor.getBoundingClientRect().top : 0;

      const fragment = document.createDocumentFragment();
      for (const message of messages) {
        const node = messageNode(message, { pending: false, currentUserId });
        fragment.append(node);
        state.rendered.set(keyOf(message), node);
      }
      elements.list.prepend(fragment);
      state.oldestKnownId = messages[0]?.id ?? state.oldestKnownId;
      if (anchor) restoreAnchor(elements, anchor, anchorOffset);
    },

    scrollAnchorPreserved() {
      return true;
    },
  };
}

/**
 * Keeps the message the visitor was looking at exactly where it was, and
 * publishes its measured offset so the stability is observable from outside
 * the page (FE_E2E asserts on it); previously this attribute never moved off
 * its template default, which no prepend could have disturbed.
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {Element} anchor
 * @param {number} anchorOffset
 */
function restoreAnchor(elements, anchor, anchorOffset) {
  const newOffset = anchor.getBoundingClientRect().top;
  elements.history.scrollTop += newOffset - anchorOffset;
  elements.scrollAnchor.dataset["anchorOffset"] = String(
    Math.round(anchor.getBoundingClientRect().top),
  );
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
export function createAppendNewerMethods(elements, state, currentUserId) {
  return {
    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasNewer]
     */
    appendNewer(messages, hasNewer) {
      appendMessages(elements, state, currentUserId, messages);
      state.hasNewer = Boolean(hasNewer);
      if (!state.hasNewer) {
        state.newMessagesLabel = null;
        setNewMessagesIndicator(elements, false);
      }
    },
  };
}
