// The live-arrival and live-region half of `store.js`'s test double (tech-doc
// 005's live-arrival rules), plus the synthetic-message factory both halves
// share. Split out of `store.js` purely to stay under this project's
// max-lines lint budget; `store.js` composes what is here and is the only
// importer.

/** @typedef {import("./store.js").StoreState} StoreState */

let nextSyntheticId = 1;

/**
 * @param {string} body
 * @returns {{id: number, body: string}}
 */
export function syntheticMessage(body) {
  const id = nextSyntheticId;
  nextSyntheticId += 1;
  return { id, body };
}

/** @param {StoreState} state */
export function createArrivalMethods(state) {
  return {
    /** @param {{scrolledAwayFromBottom?: boolean}} [opts] */
    async receiveRemoteMessage(opts = {}) {
      await Promise.resolve();
      const message = syntheticMessage("New message from another member");

      // A window that stops short of the newest committed message cannot
      // append a non-contiguous arrival; it reports it instead.
      if (state.hasNewer) {
        state.newMessagesIndicatorLabel = "New messages below";
        state.lastAnnouncement = `New message: ${message.body}`;
        state.focusMoved = false;
        return;
      }

      state.messages.push(message);

      if (opts.scrolledAwayFromBottom) {
        state.atBottom = false;
        state.newMessagesIndicatorLabel = "New messages below";
        state.lastAnnouncement = `New message: ${message.body}`;
        // A remote arrival never steals focus.
        state.focusMoved = false;
      } else {
        state.atBottom = true;
        state.positionedOnId = String(message.id);
        state.newMessagesIndicatorLabel = null;
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
  };
}
