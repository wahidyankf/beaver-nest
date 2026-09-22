// The reply target: which message the next send answers, and nothing else.
//
// It lives here rather than inside the composer because three surfaces read
// and write it — the action menu selects a target, the composer strip shows
// it and cancels it, and the outbox sends it — and because the composer's
// own draft and this target must clear independently (tech-doc 004: a
// refused send keeps both the text and the target; a successful one clears
// both, but for different reasons and at different moments).
//
// It is deliberately not persisted. Drafts are not persisted in this room,
// and a target is part of a draft.

/**
 * @typedef {object} ReplyTargetSelection
 * @property {string | null} messageId the target's server ID. `null` while a
 *   message is still queued, which is the one case selection refuses.
 * @property {string} senderDisplayName live-resolved, so the strip and the
 *   quote card can never disagree with the bubble.
 * @property {string} bodyPreview the server's own bounded preview.
 */

/**
 * @typedef {object} SelectResult
 * @property {boolean} selected
 * @property {string | null} reason present only when `selected` is false.
 */

/**
 * @typedef {object} ReplyTargetState
 * @property {ReplyTargetSelection | null} selection
 * @property {Set<(next: ReplyTargetSelection | null) => void>} listeners
 * @property {(message: string) => void} announce
 */

export const UNCOMMITTED_REMEDIATION = "This message hasn't been sent yet.";

/** @param {ReplyTargetState} state */
function notify(state) {
  for (const listener of state.listeners) listener(state.selection);
}

/**
 * Replaces any existing target rather than stacking: there is one reply
 * target, not a list of them.
 * @param {ReplyTargetState} state
 * @returns {(next: ReplyTargetSelection) => SelectResult}
 */
function createSelectMethod(state) {
  return function select(next) {
    if (!next.messageId) {
      return { selected: false, reason: UNCOMMITTED_REMEDIATION };
    }

    state.selection = next;
    // Announced once, here, through the room's existing status element --
    // the strip itself is not a live region, so a screen reader is not
    // re-reading it on every keystroke.
    state.announce(
      `Replying to ${next.senderDisplayName}: ${next.bodyPreview}`,
    );
    notify(state);
    return { selected: true, reason: null };
  };
}

/**
 * Silent when there is nothing to cancel: announcing a no-op is noise.
 * @param {ReplyTargetState} state
 * @returns {() => void}
 */
function createClearMethod(state) {
  return function clear() {
    if (state.selection === null) return;
    state.selection = null;
    state.announce("Reply cancelled");
    notify(state);
  };
}

/**
 * @param {ReplyTargetState} state
 * @returns {(listener: (next: ReplyTargetSelection | null) => void) => () => void}
 */
function createOnChangeMethod(state) {
  return function onChange(listener) {
    state.listeners.add(listener);
    return () => state.listeners.delete(listener);
  };
}

/**
 * @typedef {object} ReplyTargetStore
 * @property {() => ReplyTargetSelection | null} current
 * @property {() => boolean} isSet
 * @property {(next: ReplyTargetSelection) => SelectResult} select
 * @property {() => void} clear
 * @property {(listener: (next: ReplyTargetSelection | null) => void) => () => void} onChange
 */

/**
 * @param {{announce?: (message: string) => void}} [options]
 * @returns {ReplyTargetStore}
 */
export function createReplyTarget({ announce = () => {} } = {}) {
  /** @type {ReplyTargetState} */
  const state = { selection: null, listeners: new Set(), announce };

  return {
    current: () => state.selection,
    isSet: () => state.selection !== null,
    select: createSelectMethod(state),
    clear: createClearMethod(state),
    onChange: createOnChangeMethod(state),
  };
}
