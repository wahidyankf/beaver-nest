// Getting back to the message a quote answers, without unbounded paging.
//
// The whole decision is in tech-doc 004's "Jump to Original": if the target
// is already rendered, land on it; otherwise load older pages, one at a
// time, until it appears or the bound is reached, and say so out loud rather
// than silently doing nothing.
//
// Kept out of `history.js` because it is navigation, not reading: it must
// not move the unread divider, `hasNewer`, or the stored read position, and
// keeping it in its own module is how that stays true as `history.js` grows.

import { MESSAGE_PAGE_SIZE } from "./page_source.js";

/**
 * Five pages of at most `MESSAGE_PAGE_SIZE` each -- 250 messages of
 * catch-up, far more than a quote a member is plausibly following, and
 * bounded enough that a quote of something ancient fails fast instead of
 * paging the room in.
 */
export const MAX_JUMP_PAGES = 5;

export const JUMP_REFUSED_REMEDIATION =
  "That message is too far back to jump to.";

/**
 * @typedef {object} JumpResult
 * @property {boolean} found
 * @property {number} pagesLoaded
 * @property {string | null} remediation stated only when the jump refused.
 */

/**
 * @param {{
 *   store: {hasRendered: (id: string) => boolean},
 *   loadOlder: () => Promise<void>,
 * }} options
 * @param {string} messageId
 * @returns {Promise<JumpResult>}
 */
export async function jumpToMessage({ store, loadOlder }, messageId) {
  if (store.hasRendered(messageId)) {
    return { found: true, pagesLoaded: 0, remediation: null };
  }

  for (let pagesLoaded = 1; pagesLoaded <= MAX_JUMP_PAGES; pagesLoaded += 1) {
    // Sequential by necessity: each page's own oldest message is the cursor
    // for the next, and whether a next one is needed at all depends on what
    // this one rendered.
    // eslint-disable-next-line no-await-in-loop -- see above.
    await loadOlder();
    if (store.hasRendered(messageId)) {
      return { found: true, pagesLoaded, remediation: null };
    }
  }

  // The window is left where the paging put it. Rewinding would throw away
  // history the member may now want, and the refusal already tells them why
  // they are not where they asked to be.
  return {
    found: false,
    pagesLoaded: MAX_JUMP_PAGES,
    remediation: JUMP_REFUSED_REMEDIATION,
  };
}

export { MESSAGE_PAGE_SIZE };
