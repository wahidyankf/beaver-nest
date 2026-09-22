// Activating a quote card: getting the reader to the message it answers.
//
// The decision (already rendered, load older, or refuse) belongs to
// `jump_to_message.js`; this file is only the browser half -- scrolling,
// the highlight, and moving the roving stop so a reader without sight lands
// *on* the message rather than merely scrolling past it.

/** @typedef {import("./mount_browser.js").MountableRoom} MountableRoom */
/** @typedef {import("./elements.js").FamilyChatElements} FamilyChatElements */

const QUOTE_SELECTOR = '[data-role="family-chat-message-quote"]';

/**
 * How long the target stays marked. The CSS decides whether that is a fade
 * or a held outline -- `prefers-reduced-motion` is a media query, and only a
 * browser resolves it.
 */
const HIGHLIGHT_MS = 2000;

/**
 * @param {FamilyChatElements} elements
 * @param {string} messageId
 */
function landOn(elements, messageId) {
  const target =
    /** @type {HTMLElement | null} */
    (
      elements.list.querySelector(
        `[data-role="family-chat-message"][data-message-id="${CSS.escape(messageId)}"]`,
      )
    );
  if (!target) return null;

  target.scrollIntoView({ block: "center", behavior: "auto" });
  target.dataset["jumpHighlight"] = "on";
  globalThis.setTimeout(() => {
    delete target.dataset["jumpHighlight"];
  }, HIGHLIGHT_MS);
  return target;
}

/**
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 * @param {string} messageId
 */
async function activateQuote(room, elements, messageId) {
  const result = await room.history.jumpToMessage(messageId);
  if (!result.found) {
    // Said out loud rather than silently leaving the reader where they were:
    // a quote that does nothing when activated reads as a broken control.
    elements.liveRegion.textContent = result.remediation ?? "";
    return;
  }

  const target = landOn(elements, messageId);
  if (!target) return;
  // The roving stop moves with the reader, so Tab still enters the history
  // once and lands where they actually are.
  room.store.rovingMoveTo(messageId);
  target.focus({ preventScroll: true });
}

/**
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
export function wireQuoteJump(room, elements) {
  elements.list.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) return;
    const quote =
      /** @type {HTMLElement | null} */
      (event.target.closest(QUOTE_SELECTOR));
    const messageId = quote?.dataset["targetMessageId"];
    if (!messageId) return;
    void activateQuote(room, elements, messageId);
  });
}
