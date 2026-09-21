// Message history/scroll-anchor/live-region concerns (tech-doc 003's "upward
// growing history" and tech-doc 005's live-arrival rules). Real pixel scroll
// position and DOM focus are only measurable with a real browser layout
// engine (proven at FE_E2E, per the feature file's own Exemption comments);
// this module keeps the *logical* invariants those pixel behaviors rest on --
// the anchor message survives a prepend, focus is never programmatically
// moved on a remote arrival, a resumed room is positioned on the unread
// marker, and a member's own send is positioned on -- so they are still
// genuinely exercised here. It implements the same store contract
// `history.js` and `composer.js` call, so the paging, read-position, and send
// decisions proven at FE_UNIT run through the real production modules and are
// only *rendered* by this double; `real_store.js` is the browser's
// implementation of that same contract. Split into a state factory plus small
// method-group factories purely to stay under this project's
// max-lines-per-function lint budget.

import {
  createArrivalMethods,
  syntheticMessage,
} from "./store_arrivals.js";

/** @typedef {import("./message_render.js").RenderableMessage} RenderableMessage */

/**
 * `positionedOnId` is this double's stand-in for a scroll offset: the id of
 * the message the room placed the visitor on. `dividerBeforeId` is the id
 * the unread marker sits immediately above, or null when no marker exists.
 * @typedef {{
 *   messages: {id: number | string, body: string}[],
 *   contextCount: number,
 *   anchorMessageId: number | null,
 *   positionedOnId: string | null,
 *   dividerBeforeId: string | null,
 *   lastAnnouncement: string | null,
 *   newMessagesIndicatorLabel: string | null,
 *   focusMoved: boolean,
 *   hasOlder: boolean,
 *   hasNewer: boolean,
 *   atBottom: boolean,
 * }} StoreState
 */

/**
 * @param {boolean} scrolledToOlderMessage
 * @returns {StoreState}
 */
function createStoreState(scrolledToOlderMessage) {
  const messages = [syntheticMessage("Earlier message")];
  // A visitor can only be scrolled *back* in a conversation that has somewhere
  // further forward to be, so this state needs messages after the one they are
  // reading; with a single message "the older message" and "the newest
  // message" would be the same row and nothing could tell the two apart.
  if (scrolledToOlderMessage) {
    messages.push(
      syntheticMessage("Later message"),
      syntheticMessage("Newest message"),
    );
  }
  // Only ever grown, never emptied, so index 0 always exists; the fallback
  // below only satisfies `noUncheckedIndexedAccess`.
  const olderId = messages[0]?.id ?? null;
  return {
    messages,
    contextCount: 0,
    anchorMessageId: scrolledToOlderMessage ? olderId : null,
    // A visitor reading further back is positioned on that older message and
    // is *not* at the bottom. Saying so here is what makes "scrolled to a
    // known older message" a real precondition rather than a label: without
    // it the double would model someone simultaneously scrolled back and at
    // the end, and a scenario about being brought back to the end could not
    // fail. A scenario that seeds a conversation calls `renderInitial` or
    // `renderResumed` next, which set both fields from the rendered page.
    positionedOnId:
      scrolledToOlderMessage && olderId !== null ? String(olderId) : null,
    dividerBeforeId: null,
    lastAnnouncement: null,
    newMessagesIndicatorLabel: null,
    focusMoved: false,
    hasOlder: false,
    hasNewer: false,
    atBottom: !scrolledToOlderMessage,
  };
}

/** @param {StoreState} state */
function newestIdOf(state) {
  const newest = state.messages.at(-1);
  return newest === undefined ? null : String(newest.id);
}

/** @param {RenderableMessage[]} messages */
function asRows(messages) {
  return messages.map((message) => ({
    id: message.id ?? message.clientMessageId ?? "",
    body: message.body,
  }));
}

/** @param {StoreState} state */
function createHistoryMethods(state) {
  return {
    async loadOlderPage() {
      await Promise.resolve();
      const older = [
        syntheticMessage("Older message"),
        syntheticMessage("Even older message"),
      ];
      state.messages.unshift(...older);
    },

    scrollAnchorPreserved() {
      return (
        state.anchorMessageId !== null &&
        state.messages.some((m) => m.id === state.anchorMessageId)
      );
    },
  };
}

/** @param {StoreState} state */
function createRenderMethods(state) {
  return {
    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasOlder]
     */
    renderInitial(messages, hasOlder) {
      state.messages = asRows(messages);
      state.contextCount = 0;
      state.dividerBeforeId = null;
      state.hasOlder = messages.length === 0 ? false : (hasOlder ?? true);
      state.hasNewer = false;
      state.newMessagesIndicatorLabel = null;
      // The newest page opens at its newest message.
      state.positionedOnId = newestIdOf(state);
      state.atBottom = true;
    },

    /** @param {import("./history.js").ResumedPage} page */
    renderResumed({ contextNodes, unreadNodes, hasOlder, hasNewer }) {
      state.messages = asRows([...contextNodes, ...unreadNodes]);
      state.contextCount = contextNodes.length;
      state.dividerBeforeId = unreadNodes[0]?.id ?? null;
      state.hasOlder = hasOlder;
      state.hasNewer = hasNewer;
      state.newMessagesIndicatorLabel = hasNewer ? "New messages below" : null;
      // The room is positioned on the unread marker, so the first message in
      // view is the first one this visitor has not read.
      state.positionedOnId = state.dividerBeforeId;
      // Whether the unread block happens to fit on screen is rendered
      // geometry only `real_store.js` can answer.
      state.atBottom = false;
    },
  };
}

/** @param {StoreState} state */
function createPagingMethods(state) {
  return {
    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasOlder]
     */
    prependOlder(messages, hasOlder) {
      state.messages.unshift(...asRows(messages));
      state.contextCount += messages.length;
      state.hasOlder = Boolean(hasOlder);
    },

    /**
     * The member's own message always lands in view, however far back the
     * visitor happened to be reading.
     * @param {RenderableMessage} message
     */
    renderPending(message) {
      const [row] = asRows([message]);
      if (row === undefined) return;
      state.messages.push(row);
      state.positionedOnId = String(row.id);
      state.atBottom = true;
      if (!state.hasNewer) state.newMessagesIndicatorLabel = null;
    },

    /**
     * @param {RenderableMessage[]} messages
     * @param {boolean} [hasNewer]
     */
    appendNewer(messages, hasNewer) {
      state.messages.push(...asRows(messages));
      state.hasNewer = Boolean(hasNewer);
      if (!state.hasNewer) state.newMessagesIndicatorLabel = null;
      state.atBottom = false;
    },
  };
}

/** @param {StoreState} state */
function createPositionMethods(state) {
  return {
    isAtBottom() {
      return state.atBottom;
    },

    hasNewer() {
      return state.hasNewer;
    },

    hasOlder() {
      return state.hasOlder;
    },

    scrolledToBottom() {
      state.atBottom = true;
      if (!state.hasNewer) {
        state.newMessagesIndicatorLabel = null;
        state.positionedOnId = newestIdOf(state);
      }
    },
  };
}

/** @param {StoreState} state */
function createInspectionMethods(state) {
  return {
    oldestId() {
      const oldest = state.messages[0];
      return oldest === undefined ? null : String(oldest.id);
    },

    newestId() {
      return newestIdOf(state);
    },

    /** The message the room placed the visitor on. */
    firstMessageInViewId() {
      return state.positionedOnId;
    },

    /** The id the unread marker sits immediately above, if it is shown. */
    unreadDividerBeforeId() {
      return state.dividerBeforeId;
    },

    /** How many already-read messages were loaded above the unread marker. */
    contextCount() {
      return state.contextCount;
    },

    /** @param {string} id */
    hasRendered(id) {
      return state.messages.some((message) => String(message.id) === id);
    },
  };
}

/**
 * @param {{scrolledToOlderMessage?: boolean | undefined, focusInComposer?: boolean | undefined}} options
 */
export function createStore({ scrolledToOlderMessage = false } = {}) {
  const state = createStoreState(scrolledToOlderMessage);
  return {
    ...createHistoryMethods(state),
    ...createRenderMethods(state),
    ...createPagingMethods(state),
    ...createArrivalMethods(state),
    ...createPositionMethods(state),
    ...createInspectionMethods(state),
  };
}
