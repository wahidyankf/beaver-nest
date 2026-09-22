// The shipped `room.html.heex` template's DOM handles -- split out of
// `family_chat.js` purely to stay under this project's max-lines lint
// budget.

/**
 * Every element the shipped `room.html.heex` template renders together as
 * one static unit; `room` is the only field this module ever null-checks on
 * its own (`mountBrowser`'s "not this route" early return) -- every sibling
 * field is guaranteed present whenever `room` is, by construction of that
 * same template, so the rest are typed non-null rather than repeating the
 * same defensive check at every call site.
 * @typedef {object} FamilyChatElements
 * @property {HTMLElement | null} room
 * @property {HTMLElement} offlineBanner
 * @property {HTMLElement} history
 * @property {HTMLButtonElement} loadOlder
 * @property {HTMLElement} empty
 * @property {HTMLElement} list
 * @property {HTMLElement} scrollAnchor
 * @property {HTMLElement} newMessages
 * @property {HTMLElement} liveRegion
 * @property {HTMLFormElement} composer
 * @property {HTMLInputElement} input
 * @property {HTMLButtonElement} send
 * @property {HTMLElement} remediation
 * @property {HTMLElement} outboxStatus
 * @property {HTMLButtonElement} pushControl
 * @property {HTMLButtonElement} pushDisable
 * @property {HTMLElement} messageActions
 * @property {HTMLElement} replyStrip
 * @property {HTMLElement} replyStripName
 * @property {HTMLElement} replyStripPreview
 * @property {HTMLButtonElement} replyStripCancel
 */

/**
 * `room` is left as the raw, possibly-null query result -- the one field
 * every caller checks before trusting the rest (see `FamilyChatElements`'s
 * own doc comment). Every sibling field is cast to its real element type: it
 * is guaranteed present by the same static template whenever `room` is, so
 * asserting that here once is what lets every call site elsewhere in this
 * module skip repeating the same null check the template itself already
 * rules out.
 * @returns {FamilyChatElements}
 */
/**
 * The shell: header, history, and the surfaces that sit beside them.
 * Split from the composer's own handles only to stay inside this project's
 * max-lines-per-function budget; both halves come from the same template.
 * @returns {Omit<FamilyChatElements, "composer" | "input" | "send" | "remediation" | "outboxStatus" | "replyStrip" | "replyStripName" | "replyStripPreview" | "replyStripCancel">}
 */
function findShellElements() {
  return {
    room: document.querySelector('[data-role="family-chat-room"]'),
    offlineBanner:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-offline-banner"]')),
    history:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-history"]')),
    loadOlder:
      /** @type {HTMLButtonElement} */
      (document.querySelector('[data-role="family-chat-load-older"]')),
    empty:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-empty"]')),
    list:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-message-list"]')),
    scrollAnchor:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-scroll-anchor"]')),
    newMessages:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-new-messages"]')),
    liveRegion:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-live-region"]')),
    pushControl:
      /** @type {HTMLButtonElement} */
      (document.querySelector('[data-role="family-chat-push-control"]')),
    pushDisable:
      /** @type {HTMLButtonElement} */
      (document.querySelector('[data-role="family-chat-push-disable"]')),
    messageActions:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-message-actions"]')),
  };
}

/**
 * The composer form, including the reply strip that lives inside it.
 * @returns {Pick<FamilyChatElements, "composer" | "input" | "send" | "remediation" | "outboxStatus" | "replyStrip" | "replyStripName" | "replyStripPreview" | "replyStripCancel">}
 */
function findComposerElements() {
  return {
    composer:
      /** @type {HTMLFormElement} */
      (document.querySelector('[data-role="family-chat-composer"]')),
    input:
      /** @type {HTMLInputElement} */
      (document.querySelector('[data-role="family-chat-message-input"]')),
    send:
      /** @type {HTMLButtonElement} */
      (document.querySelector('[data-role="family-chat-send"]')),
    remediation:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-remediation"]')),
    outboxStatus:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-outbox-status"]')),
    replyStrip:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-reply-strip"]')),
    replyStripName:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-reply-strip-name"]')),
    replyStripPreview:
      /** @type {HTMLElement} */
      (document.querySelector('[data-role="family-chat-reply-strip-preview"]')),
    replyStripCancel:
      /** @type {HTMLButtonElement} */
      (document.querySelector('[data-role="family-chat-reply-strip-cancel"]')),
  };
}

export function findElements() {
  return { ...findShellElements(), ...findComposerElements() };
}
