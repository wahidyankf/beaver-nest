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

// One string for one condition: the action menu shows it on a disabled
// `Reply`, and `select` returns it if something reaches past the menu. The
// wording is tech-doc 003's Copy Inventory, verbatim.
export const REPLY_UNAVAILABLE_REASON =
  "Send this message before replying to it";

/**
 * The same bound the server applies (`BnestApp.FamilyChat`'s
 * `@preview_graphemes`). A quote that arrives from the server is already
 * shortened; a target selected from a bubble on screen is not, because it
 * is built in the browser from the full rendered body and never passes
 * through the server on its way to the strip. Both go through this, so the
 * strip and the quote card can never disagree about the same message.
 */
export const PREVIEW_GRAPHEMES = 160;

/**
 * Graphemes, not code units: slicing an emoji or a combining sequence in
 * half is how a preview turns into mojibake. Whitespace is collapsed first
 * for the same reason the server collapses it -- a preview is one line.
 * @param {string} body
 * @returns {string}
 */
export function bodyPreview(body) {
  const collapsed = body.replaceAll(/\s+/gu, " ").trim();
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  const graphemes = [...segmenter.segment(collapsed)];
  if (graphemes.length <= PREVIEW_GRAPHEMES) return collapsed;
  const kept = graphemes
    .slice(0, PREVIEW_GRAPHEMES)
    .map((part) => part.segment)
    .join("");
  return `${kept}\u2026`;
}

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
      return { selected: false, reason: REPLY_UNAVAILABLE_REASON };
    }

    state.selection = next;
    // Announced once, here, through the room's existing status element --
    // the strip itself is not a live region, so a screen reader is not
    // re-reading it on every keystroke.
    state.announce(`Replying to ${next.senderDisplayName}.`);
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
