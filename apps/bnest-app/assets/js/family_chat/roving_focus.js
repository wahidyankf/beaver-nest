// The message history's one tab group (tech-doc 004, "Keyboard Navigation
// of the History"; ADR 003, Decision 6).
//
// The history is a `role="log"` list of 50 or more items. Making each one
// tabbable would put fifty stops between the header and the composer, so
// exactly one message carries `tabindex="0"` and every other carries `-1`;
// the arrow keys move that stop rather than Tab walking through it.
//
// The stop message's own content is part of the same tab group: its links,
// quote card, and diagram source, and a table, code block, or picture only
// while it overflows. `message_content_stops.js` applies that, and this module
// re-applies it whenever the stop moves, the list changes, a region gains
// focus, or a diagram source opens.
//
// The stop is held here, as a message key, and never recomputed from the
// DOM on a key press. That is not an optimisation: the rendered list is
// replaced continuously (pending rows reconciled, older pages prepended,
// catch-up merged), and a stop derived from "whichever node currently has
// tabindex 0" would be lost on every one of those paths.

import {
  CONTENT_SELECTORS,
  syncContentStops,
} from "./message_content_stops.js";
import { revealInHistory } from "./focus_reveal.js";

const MESSAGE_SELECTOR = '[data-role="family-chat-message"]';

/**
 * @param {HTMLElement} list
 * @returns {HTMLElement[]}
 */
function itemsOf(list) {
  return (
    /** @type {HTMLElement[]} */
    ([...list.querySelectorAll(MESSAGE_SELECTOR)])
  );
}

/**
 * Anything inside a message a browser would stop on while tabbing. Buttons,
 * links, and fields are focusable by default, so a control added inside a
 * bubble is a tab stop unless it says otherwise -- which is exactly how the
 * quote card first slipped in.
 * @param {HTMLElement} item
 * @returns {HTMLElement[]}
 */
function tabbableInside(item) {
  const candidates =
    /** @type {HTMLElement[]} */
    ([
      ...item.querySelectorAll(
        "a[href], area[href], button, input, select, textarea, summary, [tabindex]",
      ),
    ]);
  return candidates.filter((candidate) => candidate.tabIndex >= 0);
}

/**
 * The contract the renderer must keep, stated once so the check and the
 * implementation cannot drift: exactly one reachable message, or none at all
 * when there are no messages to reach. Inside that message, only content a
 * reader can act on may be reachable; no other message may hold anything
 * reachable, because "Tab enters the history once and leaves it once" is
 * broken just as thoroughly by fifty quote cards as by fifty list items.
 * @param {HTMLElement} list
 * @returns {boolean}
 */
export function rovingInvariantHolds(list) {
  const items = itemsOf(list);
  if (items.length === 0) return true;
  const stops = items.filter((item) => item.tabIndex === 0);
  if (stops.length !== 1 || items.some((item) => item.tabIndex > 0)) {
    return false;
  }
  const [stop] = stops;
  return items.every((item) =>
    tabbableInside(item).every(
      (candidate) => item === stop && candidate.matches(CONTENT_SELECTORS),
    ),
  );
}

/**
 * @param {HTMLElement[]} items
 * @param {string | null} key
 */
function indexOfKey(items, key) {
  if (key === null) return -1;
  return items.findIndex((item) => item.dataset["messageId"] === key);
}

/**
 * Clamped rather than wrapped: wrapping from the newest message to the oldest
 * would silently move a reader fifty messages backwards.
 * @param {string} key
 * @param {number} current
 * @param {number} length
 * @returns {number | null} null for a key that does not move the stop.
 */
function targetIndexFor(key, current, length) {
  const next = {
    ArrowUp: current - 1,
    ArrowDown: current + 1,
    Home: 0,
    End: length - 1,
  }[key];
  if (next === undefined) return null;
  return Math.min(Math.max(next, 0), length - 1);
}

/**
 * Where a key moves the stop from its current message (the newest when the
 * stop's message is not rendered).
 * @param {HTMLElement[]} items
 * @param {string | null} stopKey
 * @param {string} key
 * @returns {number | null}
 */
function moveTargetFor(items, stopKey, key) {
  const from = indexOfKey(items, stopKey);
  const current = from === -1 ? items.length - 1 : from;
  return targetIndexFor(key, current, items.length);
}

/**
 * Re-measures the stop's content without moving the stop.
 * @param {HTMLElement} list
 * @param {string | null} stopKey
 */
function remeasureStop(list, stopKey) {
  const items = itemsOf(list);
  const index = indexOfKey(items, stopKey);
  syncContentStops(items, items[index] ?? null);
}

/**
 * Watches the list for changes that do not re-render it, and calls `remeasure`
 * for each burst of them: a table or code block that gains focus, a diagram
 * source that opens (`toggle` does not bubble, so it is listened for in the
 * capture phase), or a drawing that lands in the list.
 * @param {HTMLElement} list
 * @param {() => void} remeasure
 * @returns {() => void} stops watching.
 */
function watchContent(list, remeasure) {
  // A burst of list mutations (one render can add many nodes) is measured
  // once, after the mutations have been applied.
  let scheduled = false;
  const observer = new MutationObserver(() => {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;
      remeasure();
    });
  });
  observer.observe(list, { childList: true, subtree: true });
  list.addEventListener("focusin", remeasure);
  list.addEventListener("toggle", remeasure, true);
  return () => {
    observer.disconnect();
    list.removeEventListener("focusin", remeasure);
    list.removeEventListener("toggle", remeasure, true);
  };
}

/**
 * @typedef {object} RovingFocus
 * @property {() => void} refresh re-applies the stop after the list changed.
 * @property {(key: string) => void} move arrow/Home/End movement.
 * @property {(messageKey: string) => void} moveTo place the stop on one message.
 * @property {() => HTMLElement | null} current the message the stop is on.
 * @property {() => void} disconnect stops observing the list and its events.
 */

/**
 * Puts the one tab stop on the message `stopKey` names. When that message is
 * not rendered, or there is no stop yet, the newest message gets it: that is
 * where a reader entering the history expects to arrive.
 * @param {HTMLElement[]} items
 * @param {string | null} stopKey
 * @returns {string | null} the key the stop now holds.
 */
function applyStop(items, stopKey) {
  for (const item of items) item.tabIndex = -1;
  const index = indexOfKey(items, stopKey);
  const stop = items[index === -1 ? items.length - 1 : index];
  if (!stop) return stopKey;
  stop.tabIndex = 0;
  syncContentStops(items, stop);
  return stop.dataset["messageId"] ?? null;
}

/**
 * @param {HTMLElement} list
 * @returns {RovingFocus}
 */
export function createRovingFocus(list) {
  /** @type {string | null} */
  let stopKey = null;

  const stopWatching = watchContent(list, () => remeasureStop(list, stopKey));

  return {
    refresh() {
      stopKey = applyStop(itemsOf(list), stopKey);
    },

    move(key) {
      const items = itemsOf(list);
      const target =
        items.length === 0 ? null : moveTargetFor(items, stopKey, key);
      if (target === null) return;
      stopKey = applyStop(
        items,
        items[target]?.dataset["messageId"] ?? stopKey,
      );
      const focused = items[target];
      focused?.focus({ preventScroll: true });
      // The history wraps the list and is the element that scrolls it.
      if (focused && list.parentElement) {
        revealInHistory(focused, list.parentElement);
      }
    },

    moveTo(messageKey) {
      stopKey = applyStop(itemsOf(list), messageKey);
    },

    current() {
      const items = itemsOf(list);
      return items[indexOfKey(items, stopKey)] ?? null;
    },

    disconnect: stopWatching,
  };
}

/**
 * Re-applies the history's single tab stop after anything rendered.
 *
 * Wrapping every rendering method, rather than calling `refresh()` at each
 * of the eight call sites, is deliberate: the paths that change this list
 * (initial, resumed, older, newer, pending, reconciled, remote arrival) are
 * added to over time, and the one that forgets to refresh is the one that
 * leaves the history unreachable by Tab.
 * @template {Record<string, (...args: never[]) => unknown>} T
 * @param {T} methods
 * @param {RovingFocus} roving
 * @returns {T}
 */
export function withRovingRefresh(methods, roving) {
  const wrapped = Object.entries(methods).map(([name, method]) => [
    name,
    /** @param {never[]} args */
    (...args) => {
      const result = method(...args);
      if (result instanceof Promise) {
        return result.then((value) => {
          roving.refresh();
          return value;
        });
      }
      roving.refresh();
      return result;
    },
  ]);
  return (
    /** @type {T} */
    (Object.fromEntries(wrapped))
  );
}
