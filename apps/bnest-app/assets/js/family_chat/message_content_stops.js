// Which content of a Family Chat message a keyboard reader can reach (ADR 003, Decision 6, rules 2, 3, 5 and 7).
//
// The history is one tab group: the stop message (roving_focus.js) and the content inside it that a reader can act
// on. Every other message's content is out of the tab order, so Tab still enters the history once and leaves it once.
//
// A link, the quote card, and the diagram's source are stops whenever their message is the stop. A table, code block,
// or diagram picture is a stop only while it overflows its box: a region that fits has nothing to scroll, and a stop
// on it would only add a Tab press. An overflowing region is also named, because a screen reader announces a region
// by its name, and a bare scrolling box does not say what it holds.

import {
  nameScrollRegion,
  unnameScrollRegion,
} from "../scroll_region_names.js";

/** Content inside a message that a keyboard reader can act on, as one selector. */
export const CONTENT_SELECTORS = [
  ".family-chat-message-quote",
  '[data-role="family-chat-message-body"] a[href]',
  ".bnest-diagram-source > summary",
  '[data-role="family-chat-message-body"] table',
  '[data-role="family-chat-message-body"] pre',
  '[data-role="family-chat-message-body"] .bnest-diagram-canvas',
].join(", ");

/** Stops a message raises whatever its size: the quote card, the body's links, and the diagram source. */
const ALWAYS_STOPS = [
  ".family-chat-message-quote",
  '[data-role="family-chat-message-body"] a[href]',
  ".bnest-diagram-source > summary",
].join(", ");

/** Stops a message raises only while they overflow. */
const SCROLL_REGIONS = [
  '[data-role="family-chat-message-body"] table',
  '[data-role="family-chat-message-body"] pre',
  '[data-role="family-chat-message-body"] .bnest-diagram-canvas',
].join(", ");

/**
 * A region overflows when a reader could scroll it. happy-dom has no layout, so tests declare the measurement on the
 * element; a browser measures the real box.
 * @param {Element} region
 */
function overflows(region) {
  return (
    region.scrollWidth > region.clientWidth ||
    region.scrollHeight > region.clientHeight
  );
}

/**
 * Applies the content stops across the history: every message's content is out of the tab order, then the stop
 * message's content is raised. Idempotent, and it adds and removes no node, so its own attribute changes cannot
 * re-trigger the list observer that calls it.
 * @param {HTMLElement[]} items the rendered messages, oldest first.
 * @param {HTMLElement | null} stop the message that holds the history's single tab stop.
 */
export function syncContentStops(items, stop) {
  for (const item of items) {
    /** @type {HTMLElement[]} */
    const content = [...item.querySelectorAll(CONTENT_SELECTORS)].filter(
      (element) => element instanceof HTMLElement,
    );
    for (const element of content) element.tabIndex = -1;

    /** @type {HTMLElement[]} */
    const regions = [...item.querySelectorAll(SCROLL_REGIONS)].filter(
      (element) => element instanceof HTMLElement,
    );
    if (item !== stop) {
      for (const region of regions) unnameScrollRegion(region);
      continue;
    }

    for (const control of item.querySelectorAll(ALWAYS_STOPS)) {
      if (control instanceof HTMLElement) control.tabIndex = 0;
    }
    for (const region of regions) {
      if (overflows(region)) {
        region.tabIndex = 0;
        nameScrollRegion(region);
      } else {
        unnameScrollRegion(region);
      }
    }
  }
}
