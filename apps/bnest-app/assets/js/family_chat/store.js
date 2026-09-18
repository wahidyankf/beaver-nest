// Message history/scroll-anchor/live-region concerns (tech-doc 003's "upward
// growing history" and tech-doc 005's live-arrival rules). Real pixel scroll
// position and DOM focus are only measurable with a real browser layout
// engine (proven at FE_E2E, per the feature file's own Exemption comments);
// this module keeps the *logical* invariants those pixel behaviors rest on
// (the anchor message survives a prepend; focus is never programmatically
// moved on a remote arrival) so they are still genuinely exercised here.

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
 * @param {{scrolledToOlderMessage?: boolean | undefined, focusInComposer?: boolean | undefined}} options
 */
export function createStore({
  scrolledToOlderMessage = false,
  focusInComposer = false,
} = {}) {
  const messages = [syntheticMessage("Earlier message")];
  // `messages` always starts with the one synthetic message above and is
  // only ever grown (unshift/push), never emptied, so index 0 always
  // exists; the `?? null` fallback only satisfies `noUncheckedIndexedAccess`.
  let anchorMessageId = scrolledToOlderMessage
    ? (messages[0]?.id ?? null)
    : null;
  /** @type {string | null} */
  let lastAnnouncement = null;
  /** @type {string | null} */
  let newMessagesIndicatorLabel = null;
  let focusMoved = false;
  let atBottom = true;

  return {
    async loadOlderPage() {
      const older = [
        syntheticMessage("Older message"),
        syntheticMessage("Even older message"),
      ];
      messages.unshift(...older);
    },

    scrollAnchorPreserved() {
      return (
        anchorMessageId !== null &&
        messages.some((m) => m.id === anchorMessageId)
      );
    },

    /** @param {{scrolledAwayFromBottom?: boolean}} [opts] */
    async receiveRemoteMessage(opts = {}) {
      const message = syntheticMessage("New message from another member");
      messages.push(message);

      if (opts.scrolledAwayFromBottom) {
        atBottom = false;
        newMessagesIndicatorLabel = "New messages below";
        lastAnnouncement = `New message: ${message.body}`;
        // Focus is only ever moved by the visitor's own action -- a remote
        // arrival never steals it, whether or not it was in the composer.
        focusMoved = false;
      } else {
        atBottom = true;
        newMessagesIndicatorLabel = null;
      }

      if (!focusInComposer) {
        // No composer focus was claimed at open, so "did focus move" is not
        // meaningful for this scenario; leave it at its default (false).
      }
    },

    lastLiveRegionAnnouncement() {
      return lastAnnouncement;
    },

    focusMovedFromComposer() {
      return focusMoved;
    },

    newMessagesIndicatorLabel() {
      return newMessagesIndicatorLabel;
    },

    isAtBottom() {
      return atBottom;
    },
  };
}
