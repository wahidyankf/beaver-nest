// The real (browser) message-list store: message list + scroll anchor +
// live region -- split out of `family_chat.js`, and split further into
// several small factory functions (plus `message_render.js` for the
// rendering primitives they share and `real_store_render.js` for the
// window-rendering method groups), purely to stay under this project's
// max-lines/max-lines-per-function lint budget. `createRealStore` below is
// the only export `family_chat.js`/`mount_browser.js` need to know about.
//
// Where the visitor is placed in the conversation is decided by
// `history.js`; this module only carries it out. Two rendering entry points
// exist because there are two landing places: `renderInitial` for the newest
// page (scrolled to the bottom, the way a chat room is expected to open) and
// `renderResumed` for a window anchored on the unread marker.

import {
  isNearBottom,
  messageNode,
  scrollToBottom,
  setNewMessagesIndicator,
} from "./message_render.js";
import {
  createAppendNewerMethods,
  createInitialRenderMethods,
  createPrependOlderMethods,
  createResumeRenderMethods,
} from "./real_store_render.js";

/** @typedef {import("./message_render.js").RenderableMessage} RenderableMessage */
/** @typedef {import("./real_store_render.js").RealStoreState} RealStoreState */

/** @returns {RealStoreState} */
function createRealStoreState() {
  return {
    rendered: new Map(),
    lastAnnouncement: null,
    newMessagesLabel: null,
    oldestKnownId: null,
    newestKnownId: null,
    hasNewer: false,
    atBottom: true,
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function createPendingRenderMethods(elements, state) {
  return {
    /** @param {RenderableMessage} message */
    renderPending(message) {
      const node = messageNode(message, { pending: true });
      elements.list.append(node);
      state.rendered.set(message.clientMessageId ?? "", node);
      // Always, not only when already near the bottom: this row is the
      // member's own message, and a send that leaves it off-screen -- which
      // is what happens to anyone writing from their unread marker -- reads
      // as the message never having been sent.
      scrollToBottom(elements);
      state.atBottom = true;
      // While the window still stops short of the newest committed message
      // the indicator stays up: it is the way to the messages this send did
      // not catch up on.
      if (!state.hasNewer) {
        state.newMessagesLabel = null;
        setNewMessagesIndicator(elements, false);
      }
    },

    /**
     * @param {string} clientMessageId
     * @param {string} status
     */
    updatePendingStatus(clientMessageId, status) {
      const node = state.rendered.get(clientMessageId);
      const statusNode = node?.querySelector(
        '[data-role="family-chat-message-status"]',
      );
      if (statusNode) statusNode.textContent = status;
      if (node) node.dataset["deliveryState"] = status;
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
function createReconcileMethod(elements, state, currentUserId) {
  return {
    /**
     * @param {string} clientMessageId
     * @param {RenderableMessage} committedMessage
     */
    reconcile(clientMessageId, committedMessage) {
      const pendingNode = state.rendered.get(clientMessageId);
      const committedKey = committedMessage.id ?? "";
      const existingCommittedNode = state.rendered.get(committedKey);

      // The subscription push for this same message already rendered it
      // (a race against this send's own mutation response, since tech-doc
      // 008's subscription payload never carries the client-chosen ID) --
      // the committed row is already correct on screen, so just drop the
      // now-redundant pending row instead of creating a second copy of it.
      if (existingCommittedNode) {
        if (pendingNode && pendingNode !== existingCommittedNode)
          pendingNode.remove();
        state.rendered.delete(clientMessageId);
        return;
      }

      const node = messageNode(committedMessage, {
        pending: false,
        currentUserId,
      });
      if (pendingNode) {
        pendingNode.replaceWith(node);
      } else {
        elements.list.append(node);
      }
      state.rendered.delete(clientMessageId);
      state.rendered.set(committedKey, node);
      state.newestKnownId = committedKey;
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {RenderableMessage} message
 */
function announceArrival(elements, state, message) {
  const senderLabel =
    message.senderKind === "system" ? "System" : message.senderDisplayName;
  state.lastAnnouncement = `New message from ${senderLabel}: ${message.body}`;
  elements.liveRegion.textContent = state.lastAnnouncement;
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function reportPending(elements, state) {
  state.atBottom = false;
  state.newMessagesLabel = "New messages below";
  setNewMessagesIndicator(elements, true);
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 * @param {string | null} currentUserId
 */
function createReceiveRemoteMessageMethod(elements, state, currentUserId) {
  return {
    /** @param {RenderableMessage} message */
    async receiveRemoteMessage(message) {
      await Promise.resolve();
      const key = message.id ?? "";
      // Already reconciled from our own send.
      if (state.rendered.has(key)) return;

      // The rendered window deliberately stops short of the newest committed
      // message, so this arrival is not contiguous with it: appending would
      // render it directly after an older message with a silent gap in
      // between. Report it instead, and let the visitor reach it by reading
      // forward or jumping to the newest page.
      if (state.hasNewer) {
        reportPending(elements, state);
        announceArrival(elements, state, message);
        return;
      }

      const wasNearBottom = isNearBottom(elements);
      const node = messageNode(message, { pending: false, currentUserId });
      elements.list.append(node);
      state.rendered.set(key, node);
      state.newestKnownId = key;

      if (wasNearBottom) {
        state.atBottom = true;
        state.newMessagesLabel = null;
        setNewMessagesIndicator(elements, false);
        scrollToBottom(elements);
      } else {
        reportPending(elements, state);
      }

      announceArrival(elements, state, message);
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function createArrivalReaderMethods(elements, state) {
  return {
    lastLiveRegionAnnouncement() {
      return state.lastAnnouncement;
    },

    focusMovedFromComposer() {
      return false;
    },

    newMessagesIndicatorLabel() {
      return state.newMessagesLabel;
    },

    isAtBottom() {
      return state.atBottom;
    },

    hasNewer() {
      return state.hasNewer;
    },

    /** Records that the visitor has reached the end of the rendered window. */
    scrolledToBottom() {
      state.atBottom = true;
      if (!state.hasNewer) {
        state.newMessagesLabel = null;
        setNewMessagesIndicator(elements, false);
      }
    },
  };
}

/** @param {RealStoreState} state */
function createCursorReaderMethods(state) {
  return {
    oldestId() {
      return state.oldestKnownId;
    },

    newestId() {
      return state.newestKnownId;
    },

    /** @param {string} id */
    hasRendered(id) {
      return state.rendered.has(id);
    },
  };
}

/**
 * @param {{
 *   roomSlug: string,
 *   elements: import("./elements.js").FamilyChatElements,
 *   currentUserId?: string | null,
 * }} options
 */
export function createRealStore({ elements, currentUserId = null }) {
  const state = createRealStoreState();
  return {
    ...createInitialRenderMethods(elements, state, currentUserId),
    ...createResumeRenderMethods(elements, state, currentUserId),
    ...createPrependOlderMethods(elements, state, currentUserId),
    ...createAppendNewerMethods(elements, state, currentUserId),
    ...createPendingRenderMethods(elements, state),
    ...createReconcileMethod(elements, state, currentUserId),
    ...createReceiveRemoteMessageMethod(elements, state, currentUserId),
    ...createArrivalReaderMethods(elements, state),
    ...createCursorReaderMethods(state),
  };
}
