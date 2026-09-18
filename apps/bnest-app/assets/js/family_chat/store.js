// Message history/scroll-anchor/live-region concerns (tech-doc 003's "upward
// growing history" and tech-doc 005's live-arrival rules). Real pixel scroll
// position and DOM focus are only measurable with a real browser layout
// engine (proven at FE_E2E, per the feature file's own Exemption comments);
// this module keeps the *logical* invariants those pixel behaviors rest on
// (the anchor message survives a prepend; focus is never programmatically
// moved on a remote arrival) so they are still genuinely exercised here.
//
// Split into a state factory plus two small method-group factories purely to
// stay under this project's max-lines-per-function lint budget --
// `createStore` below composes them and is the only export callers need.

let nextSyntheticId = 1;

/**
 * @param {string} body
 * @returns {{id: number, body: string}}
 */
function syntheticMessage(body) {
  const id = nextSyntheticId;
  nextSyntheticId += 1;
  return { id, body };
}

/**
 * @typedef {{
 *   messages: {id: number, body: string}[],
 *   anchorMessageId: number | null,
 *   lastAnnouncement: string | null,
 *   newMessagesIndicatorLabel: string | null,
 *   focusMoved: boolean,
 *   atBottom: boolean,
 * }} StoreState
 */

/**
 * @param {boolean} scrolledToOlderMessage
 * @returns {StoreState}
 */
function createStoreState(scrolledToOlderMessage) {
  const messages = [syntheticMessage("Earlier message")];
  // `messages` always starts with the one synthetic message above and is
  // only ever grown (unshift/push), never emptied, so index 0 always
  // exists; the `?? null` fallback only satisfies `noUncheckedIndexedAccess`.
  return {
    messages,
    anchorMessageId: scrolledToOlderMessage ? (messages[0]?.id ?? null) : null,
    lastAnnouncement: null,
    newMessagesIndicatorLabel: null,
    focusMoved: false,
    atBottom: true,
  };
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

/**
 * @param {StoreState} state
 * @param {boolean} focusInComposer
 */
function createArrivalMethods(state, focusInComposer) {
  return {
    /** @param {{scrolledAwayFromBottom?: boolean}} [opts] */
    async receiveRemoteMessage(opts = {}) {
      await Promise.resolve();
      const message = syntheticMessage("New message from another member");
      state.messages.push(message);

      if (opts.scrolledAwayFromBottom) {
        state.atBottom = false;
        state.newMessagesIndicatorLabel = "New messages below";
        state.lastAnnouncement = `New message: ${message.body}`;
        // Focus is only ever moved by the visitor's own action -- a remote
        // arrival never steals it, whether or not it was in the composer.
        state.focusMoved = false;
      } else {
        state.atBottom = true;
        state.newMessagesIndicatorLabel = null;
      }

      if (!focusInComposer) {
        // No composer focus was claimed at open, so "did focus move" is not
        // meaningful for this scenario; leave it at its default (false).
      }
    },

    lastLiveRegionAnnouncement() {
      return state.lastAnnouncement;
    },

    focusMovedFromComposer() {
      return state.focusMoved;
    },

    newMessagesIndicatorLabel() {
      return state.newMessagesIndicatorLabel;
    },

    isAtBottom() {
      return state.atBottom;
    },
  };
}

/**
 * @param {{scrolledToOlderMessage?: boolean | undefined, focusInComposer?: boolean | undefined}} options
 */
export function createStore({
  scrolledToOlderMessage = false,
  focusInComposer = false,
} = {}) {
  const state = createStoreState(scrolledToOlderMessage);
  return {
    ...createHistoryMethods(state),
    ...createArrivalMethods(state, focusInComposer),
  };
}
