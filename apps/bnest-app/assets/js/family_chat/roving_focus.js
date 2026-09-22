// The message history's single tab stop (tech-doc 004, "Keyboard Navigation
// of the History").
//
// The history is a `role="log"` list of 50 or more items. Making each one
// tabbable would put fifty stops between the header and the composer, so
// exactly one message carries `tabindex="0"` and every other carries `-1`;
// the arrow keys move that stop rather than Tab walking through it.
//
// The stop is held here, as a message key, and never recomputed from the
// DOM on a key press. That is not an optimisation: the rendered list is
// replaced continuously (pending rows reconciled, older pages prepended,
// catch-up merged), and a stop derived from "whichever node currently has
// tabindex 0" would be lost on every one of those paths.

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
 * The contract the renderer must keep, stated once so the check and the
 * implementation cannot drift: exactly one reachable message, or none at all
 * when there are no messages to reach.
 * @param {HTMLElement} list
 * @returns {boolean}
 */
export function rovingInvariantHolds(list) {
  const items = itemsOf(list);
  if (items.length === 0) return true;
  const stops = items.filter((item) => item.tabIndex === 0);
  return stops.length === 1 && items.every((item) => item.tabIndex <= 0);
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
 * @typedef {object} RovingFocus
 * @property {() => void} refresh re-applies the stop after the list changed.
 * @property {(key: string) => void} move arrow/Home/End movement.
 * @property {(messageKey: string) => void} moveTo place the stop on one message.
 * @property {() => HTMLElement | null} current the message the stop is on.
 */

/**
 * @param {HTMLElement} list
 * @returns {RovingFocus}
 */
export function createRovingFocus(list) {
  /** @type {string | null} */
  let stopKey = null;

  /** @param {HTMLElement[]} items */
  function apply(items) {
    for (const item of items) item.tabIndex = -1;
    const index = indexOfKey(items, stopKey);
    // No stop yet, or the message it named is no longer rendered: fall back
    // to the newest, which is where a reader entering the history expects to
    // arrive.
    const stop = items[index === -1 ? items.length - 1 : index];
    if (!stop) return;
    stop.tabIndex = 0;
    stopKey = stop.dataset["messageId"] ?? null;
  }

  return {
    refresh() {
      apply(itemsOf(list));
    },

    move(key) {
      const items = itemsOf(list);
      if (items.length === 0) return;
      const from = indexOfKey(items, stopKey);
      const current = from === -1 ? items.length - 1 : from;
      const target = targetIndexFor(key, current, items.length);
      if (target === null) return;
      stopKey = items[target]?.dataset["messageId"] ?? stopKey;
      apply(items);
      items[target]?.focus({ preventScroll: true });
    },

    moveTo(messageKey) {
      stopKey = messageKey;
      apply(itemsOf(list));
    },

    current() {
      const items = itemsOf(list);
      return items[indexOfKey(items, stopKey)] ?? null;
    },
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
