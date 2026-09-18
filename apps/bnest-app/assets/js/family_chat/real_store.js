// The real (browser) message-list store: message list + scroll anchor +
// live region -- split out of `family_chat.js`, and split further into
// several small factory functions (plus `message_render.js` for the
// rendering primitives they share), purely to stay under this project's
// max-lines/max-lines-per-function lint budget. `createRealStore` below is
// the only export `family_chat.js`/`mount_browser.js` need to know about.

import { messageNode, isNearBottom, setHasOlder } from "./message_render.js";

/** @typedef {import("./message_render.js").RenderableMessage} RenderableMessage */

/**
 * @typedef {{
 *   rendered: Map<string, HTMLLIElement>,
 *   lastAnnouncement: string | null,
 *   newMessagesLabel: string | null,
 *   oldestKnownId: string | null,
 *   atBottom: boolean,
 * }} RealStoreState
 */

/** @returns {RealStoreState} */
function createRealStoreState() {
  return {
    rendered: new Map(),
    lastAnnouncement: null,
    newMessagesLabel: null,
    oldestKnownId: null,
    atBottom: true,
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function createInitialRenderMethods(elements, state) {
  return {
    empty() {
      return state.rendered.size === 0;
    },

    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasOlder]
     */
    renderInitial(messages, hasOlder) {
      elements.list.replaceChildren();
      state.rendered.clear();
      for (const message of messages) {
        const node = messageNode(message, { pending: false });
        const key = message.id ?? message.clientMessageId ?? "";
        elements.list.append(node);
        state.rendered.set(key, node);
        state.oldestKnownId =
          state.oldestKnownId === null ? key : state.oldestKnownId;
      }
      elements.empty.hidden = messages.length > 0;
      // An empty room has nothing earlier to load regardless of what the
      // query reported; otherwise trust the server's own `hasOlder` flag,
      // defaulting to true (safe: still offers the button) if a caller ever
      // omits it.
      setHasOlder(elements, messages.length === 0 ? false : (hasOlder ?? true));
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function createPrependOlderMethods(elements, state) {
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
        const node = messageNode(message, { pending: false });
        fragment.append(node);
        state.rendered.set(message.id ?? message.clientMessageId ?? "", node);
      }
      elements.list.prepend(fragment);
      state.oldestKnownId = messages[0]?.id ?? state.oldestKnownId;

      if (anchor) {
        const newOffset = anchor.getBoundingClientRect().top;
        elements.history.scrollTop += newOffset - anchorOffset;
      }
    },

    scrollAnchorPreserved() {
      return true;
    },
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
      if (isNearBottom(elements))
        elements.history.scrollTop = elements.history.scrollHeight;
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
 */
function createReconcileMethod(elements, state) {
  return {
    /**
     * @param {string} clientMessageId
     * @param {RenderableMessage} committedMessage
     */
    reconcile(clientMessageId, committedMessage) {
      const pendingNode = state.rendered.get(clientMessageId);
      const committedKey = committedMessage.id ?? "";
      const existingCommittedNode = state.rendered.get(committedKey);

      if (existingCommittedNode) {
        // The subscription push for this same message already rendered it
        // (a race against this send's own mutation response, since
        // tech-doc 008's subscription payload never carries the
        // client-chosen ID) -- the committed row is already correct on
        // screen, so just drop the now-redundant pending row instead of
        // creating a second copy of it.
        if (pendingNode && pendingNode !== existingCommittedNode)
          pendingNode.remove();
        state.rendered.delete(clientMessageId);
        return;
      }

      const node = messageNode(committedMessage, { pending: false });
      if (pendingNode) {
        pendingNode.replaceWith(node);
      } else {
        elements.list.append(node);
      }
      state.rendered.delete(clientMessageId);
      state.rendered.set(committedKey, node);
    },
  };
}

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {RealStoreState} state
 */
function createReceiveRemoteMessageMethod(elements, state) {
  return {
    /** @param {RenderableMessage} message */
    async receiveRemoteMessage(message) {
      await Promise.resolve();
      const key = message.id ?? "";
      // Already reconciled from our own send.
      if (state.rendered.has(key)) return;
      const wasNearBottom = isNearBottom(elements);
      const node = messageNode(message, { pending: false });
      elements.list.append(node);
      state.rendered.set(key, node);

      if (wasNearBottom) {
        state.atBottom = true;
        state.newMessagesLabel = null;
        elements.newMessages.hidden = true;
        elements.history.scrollTop = elements.history.scrollHeight;
      } else {
        state.atBottom = false;
        state.newMessagesLabel = "New messages below";
        elements.newMessages.hidden = false;
      }

      const senderLabel =
        message.senderKind === "system" ? "System" : message.senderDisplayName;
      state.lastAnnouncement = `New message from ${senderLabel}: ${message.body}`;
      elements.liveRegion.textContent = state.lastAnnouncement;
    },
  };
}

/** @param {RealStoreState} state */
function createArrivalReaderMethods(state) {
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

    oldestId() {
      return state.oldestKnownId;
    },

    /** @param {string} id */
    hasRendered(id) {
      return state.rendered.has(id);
    },
  };
}

/** @param {{roomSlug: string, elements: import("./elements.js").FamilyChatElements}} options */
export function createRealStore({ elements }) {
  const state = createRealStoreState();
  return {
    ...createInitialRenderMethods(elements, state),
    ...createPrependOlderMethods(elements, state),
    ...createPendingRenderMethods(elements, state),
    ...createReconcileMethod(elements, state),
    ...createReceiveRemoteMessageMethod(elements, state),
    ...createArrivalReaderMethods(state),
  };
}
