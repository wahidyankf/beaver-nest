// Which rendered message a DOM event belongs to. Split out of `mount_browser_actions.js` to stay under that file's
// max-lines lint budget; the key and pointer bindings there use these.

export const MESSAGE_SELECTOR = '[data-role="family-chat-message"]';

/**
 * @param {EventTarget | null} target
 * @returns {HTMLElement | null}
 */
export function messageElementFrom(target) {
  if (!(target instanceof Element)) return null;
  return (
    /** @type {HTMLElement | null} */
    (target.closest(MESSAGE_SELECTOR))
  );
}

/**
 * The message a key was pressed on, only when the message itself is the target: content inside it keeps its own keys
 * (ADR 003, Decision 6, rule 4).
 * @param {EventTarget | null} target
 * @returns {HTMLElement | null}
 */
export function ownMessageOf(target) {
  const element = messageElementFrom(target);
  return element !== null && element === target ? element : null;
}
