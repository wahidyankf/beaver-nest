// Key rules for the two chat message boxes, Family Chat and the Codex chat (ADR 005, decision 1, revised 2026-11-13).
//
// The visitor's primary pointer decides what Enter does. A touch primary pointer makes Enter a new line and Shift+Enter
// a send. A fine primary pointer (mouse, trackpad, or a laptop keyboard) makes Enter a send and Shift+Enter a new line.
// The screen width never decides. A key press that confirms an IME composition never sends. The Send button stays on
// every device. Both rooms read the same rule, so they cannot drift apart.

/**
 * @typedef {{key: string, shiftKey?: boolean, isComposing?: boolean, keyCode?: number}} KeyPress
 * @typedef {"send" | "newline" | "ignore"} KeyIntent
 */

/**
 * Whether the visitor's primary pointer is a touch pointer (`pointer: coarse`). An iPad or a phone with a Bluetooth
 * keyboard counts as touch; a touchscreen laptop whose primary pointer is fine counts as desktop.
 * @param {Window | typeof globalThis} [view]
 * @returns {boolean}
 */
export function isTouchPointer(view = globalThis) {
  if (typeof view?.matchMedia !== "function") return false;
  return Boolean(view.matchMedia("(pointer: coarse)").matches);
}

/**
 * What a key press asks the message box to do, given the visitor's primary pointer.
 * @param {KeyPress} press
 * @param {boolean} [touch] true when the primary pointer is a touch pointer
 * @returns {KeyIntent}
 */
export function keyIntent(
  { key, shiftKey = false, isComposing = false, keyCode = 0 },
  touch = false,
) {
  // Enter that confirms a composition belongs to the input method, not to the message. Safari reports that Enter with
  // keyCode 229 and isComposing false, so both signals are checked.
  if (isComposing || keyCode === 229 || key !== "Enter") return "ignore";
  const sends = touch ? shiftKey : !shiftKey;
  return sends ? "send" : "newline";
}

/**
 * Runs the send for one key press in a message box, in both rooms. A send press stops the browser's newline and runs
 * `send` once. A held key repeats its keydown, so a repeat stops the newline and runs nothing more.
 * @param {KeyPress & {repeat?: boolean, preventDefault: () => void}} press
 * @param {boolean} touch true when the primary pointer is a touch pointer
 * @param {() => void} send
 * @returns {boolean} true when the press was a send key
 */
export function sendOnKey(press, touch, send) {
  if (keyIntent(press, touch) !== "send") return false;
  // The send key must not add a line to the draft it sends.
  press.preventDefault();
  if (!press.repeat) send();
  return true;
}

/**
 * Sends a Codex draft through the form's own submit path, so LiveView's `phx-submit` runs. A blank draft is not sent.
 * A read-only box (Codex is replying) keeps keyboard focus but never sends, so a reply in progress cannot be sent twice.
 * @param {KeyboardEvent} event
 * @param {HTMLTextAreaElement} textarea
 * @param {boolean} [touch] true when the primary pointer is a touch pointer
 */
export function handleComposerKey(event, textarea, touch = false) {
  sendOnKey(event, touch, () => {
    if (textarea.disabled || textarea.readOnly) return;
    if (textarea.value.trim() === "") return;
    textarea.form?.requestSubmit();
  });
}

/**
 * Keeps keyboard focus in the Codex message box when a pointer or mouse press lands on its Send button. A browser moves
 * focus to a button it presses, and a button that turns disabled while it holds focus drops focus to the page, so on a
 * phone the on-screen keyboard closed after every tap. Cancelling the press's default keeps focus where it was. The
 * press still clicks the button, so the form still submits. Family Chat does the same (family_chat/mount_browser_composer.js).
 * @param {Window | typeof globalThis | Document | HTMLElement} target
 */
export function keepFocusOnSendPress(target) {
  target.addEventListener("pointerdown", keepFocusOnSendPressEvent);
  target.addEventListener("mousedown", keepFocusOnSendPressEvent);
}

/** @param {Event} press */
function keepFocusOnSendPressEvent(press) {
  // The target is read as untyped: the closest check below decides whether it is the Send button before it is used.
  /** @type {any} */
  const origin = press.target;
  if (typeof origin?.closest !== "function") return;
  if (origin.closest("#chat-composer-form .send-button") === null) return;
  press.preventDefault();
}

/**
 * Listens for key presses in every Codex message box on the page (`data-role="chat-composer"`). The pointer is read at
 * each key press, so a visitor who connects or disconnects a keyboard gets the new rule without a reload.
 * @param {Window | HTMLElement | Document} target
 * @param {Window | typeof globalThis} [view] the window whose primary pointer decides the rule
 */
export function installComposerKeys(target, view = globalThis) {
  target.addEventListener("keydown", (event) => {
    // The page's event and its target are read as untyped here: the tag and role checks below narrow the target to a
    // message box before any box property is used.
    /** @type {any} */
    const press = event;
    /** @type {any} */
    const textarea = press.target;
    // Tag check, not instanceof: the page may belong to another window (happy-dom tests).
    if (!textarea || textarea.tagName !== "TEXTAREA") return;
    if (textarea.dataset["role"] !== "chat-composer") return;
    handleComposerKey(press, textarea, isTouchPointer(view));
  });
}
