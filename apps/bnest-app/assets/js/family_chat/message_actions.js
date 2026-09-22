// The per-message action menu, as three separable concerns: recognizing the
// gesture that opens it, holding which message it is open for, and running
// what it offers. Nothing here touches the DOM -- `mount_browser.js` binds
// real events to these decisions, and `real_store_render.js` renders them --
// so the rules tech-doc 004 fixes can be pinned without a browser.
//
// The split is the point: a later per-message action adds one entry to
// `menuItemsFor` and one branch at the call site, and touches neither the
// gesture nor the menu's state.

import { REPLY_UNAVAILABLE_REASON } from "./reply_target.js";

/** Below ~400 ms a hold is a slow tap; above ~600 ms it feels broken. */
export const HOLD_DURATION_MS = 500;

/** What makes a scroll that begins on a bubble a scroll and not a menu. */
export const HOLD_MOVE_TOLERANCE_PX = 10;

export const COPIED_ANNOUNCEMENT = "Message copied.";
export const COPY_REFUSED_ANNOUNCEMENT =
  "Couldn't copy. Select the text manually.";

/**
 * @typedef {object} ActionableMessage
 * @property {string} clientMessageId
 * @property {string | null} [messageId] the server ID, absent until committed.
 * @property {string} body the full body -- what `Copy text` writes.
 * @property {string} senderDisplayName
 */

/**
 * @typedef {object} MenuItem
 * @property {string} label
 * @property {boolean} available
 * @property {string | null} reason why not, when `available` is false.
 */

/**
 * @typedef {object} Point
 * @property {number} x
 * @property {number} y
 */

/**
 * Recognizes a press-and-hold: a timer that only fires if the pointer stays
 * down, and stays put, for the whole duration.
 *
 * Movement is measured from where the press began rather than between
 * successive moves, so a slow drift can never stay under the threshold one
 * event at a time while travelling far in total.
 * @param {{clock: import("./clock.js").Clock, onHold: () => void}} options
 */
export function createHoldGesture({ clock, onHold }) {
  /** @type {Point | null} */
  let origin = null;
  /** @type {unknown} */
  let timer = null;

  function stop() {
    if (timer !== null) clock.clearTimer(timer);
    timer = null;
    origin = null;
  }

  return {
    /** @param {Point} point */
    start(point) {
      stop();
      origin = point;
      timer = clock.setTimer(() => {
        timer = null;
        origin = null;
        onHold();
      }, HOLD_DURATION_MS);
    },

    /** @param {Point} point */
    move(point) {
      if (origin === null) return;
      const dx = point.x - origin.x;
      const dy = point.y - origin.y;
      if (Math.hypot(dx, dy) > HOLD_MOVE_TOLERANCE_PX) stop();
    },

    /** A release before the timer elapses is a tap, not a hold. */
    end: stop,

    /** `pointercancel` -- the browser taking the gesture over, e.g. a scroll. */
    cancel: stop,
  };
}

/**
 * @typedef {object} MenuState
 * @property {() => ActionableMessage | null} openFor
 * @property {() => boolean} isOpen
 * @property {() => ActionableMessage | null} returnFocusTo
 * @property {(message: ActionableMessage) => void} open
 * @property {() => void} close
 * @property {(listener: (next: ActionableMessage | null) => void) => () => void} onChange
 */

/**
 * One menu for the whole room: opening it for another message replaces the
 * first, so two menus can never be open at once and there is one thing to
 * test. The message it was opened from outlives the close, because that is
 * where focus has to return -- on every close path, including choosing an
 * item.
 * @returns {MenuState}
 */
export function createMenuState() {
  /** @type {{open: ActionableMessage | null, last: ActionableMessage | null}} */
  const state = { open: null, last: null };
  /** @type {Set<(next: ActionableMessage | null) => void>} */
  const listeners = new Set();

  function notify() {
    for (const listener of listeners) listener(state.open);
  }

  return {
    openFor: () => state.open,
    isOpen: () => state.open !== null,
    returnFocusTo: () => state.last,

    open(message) {
      state.open = message;
      state.last = message;
      notify();
    },

    close() {
      if (state.open === null) return;
      state.open = null;
      notify();
    },

    onChange(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

/**
 * The menu's items for one message, in render order.
 *
 * No sender kind is special-cased: a system message is replied to like any
 * other. The one thing that gates `Reply` is whether the server has given
 * the message an ID yet, because that ID is the whole reply target.
 * @param {ActionableMessage} message
 * @returns {MenuItem[]}
 */
export function menuItemsFor(message) {
  const committed = Boolean(message.messageId);
  return [
    {
      label: "Reply",
      available: committed,
      reason: committed ? null : REPLY_UNAVAILABLE_REASON,
    },
    { label: "Copy text", available: true, reason: null },
  ];
}

/**
 * Writes the message's full body -- not the preview -- and announces the
 * outcome either way.
 *
 * Always resolves, never rejects: a rejected clipboard promise that nobody
 * handled would leave the member believing the copy worked, which is the one
 * outcome this action must not produce.
 * @param {ActionableMessage} message
 * @param {{writeText?: ((text: string) => Promise<void>) | undefined, announce: (message: string) => void}} options
 * @returns {Promise<boolean>} whether the text reached the clipboard.
 */
export async function runCopyAction(message, { writeText, announce }) {
  if (typeof writeText !== "function") {
    announce(COPY_REFUSED_ANNOUNCEMENT);
    return false;
  }

  try {
    await writeText(message.body);
  } catch {
    announce(COPY_REFUSED_ANNOUNCEMENT);
    return false;
  }

  announce(COPIED_ANNOUNCEMENT);
  return true;
}
