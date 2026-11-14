// Client-side controls of the Codex chat page (ADR 005): the options panel on a phone, the Clear chat confirmation, and
// the raw or rendered view of each visitor message.
//
// Each control is a delegated listener on the document, so it keeps working after LiveView patches the page. None of
// these states goes to the server: the confirmation only reaches it when "Yes, delete" is pressed, which runs the
// LiveView `clear` event on that button.

const OPEN_CLASS = "is-open";

// True while the confirmation moves focus itself, so the focusout that follows is not read as the visitor leaving.
let movingFocus = false;

// True from a press that starts inside the confirmation group until the press ends. Safari does not focus a button on
// click, so the focusout of that press reports no new focus target; the button must still receive its click.
let pressInsideGroup = false;

// Duck-typed element check: `instanceof Element` fails when the page belongs to another window (happy-dom tests).
/** @param {unknown} node @returns {node is HTMLElement} */
function isElement(node) {
  if (node === null || typeof node !== "object") return false;
  /** @type {any} */
  const candidate = node;
  return typeof candidate.closest === "function";
}

/** @param {ParentNode} root */
function confirmationOf(root) {
  return root.querySelector("[data-role='clear-chat-confirm']");
}

/**
 * @param {ParentNode} root
 * @param {boolean} open
 */
function setConfirmation(root, open) {
  const confirmation = confirmationOf(root);
  const trigger = root.querySelector("[data-role='clear-chat']");
  if (!isElement(confirmation) || !isElement(trigger)) return;
  confirmation.hidden = !open;
  trigger.setAttribute("aria-expanded", String(open));
  movingFocus = true;
  try {
    if (open) {
      const cancel = root.querySelector("[data-role='clear-chat-cancel']");
      if (isElement(cancel)) cancel.focus();
    } else {
      trigger.focus();
    }
  } finally {
    movingFocus = false;
  }
}

/**
 * Hides an open confirmation and leaves focus where it is. A confirmation hidden while the visitor works elsewhere
 * must not take focus back.
 * @param {ParentNode} root
 */
function hideConfirmation(root) {
  const confirmation = confirmationOf(root);
  const trigger = root.querySelector("[data-role='clear-chat']");
  if (!isElement(confirmation) || confirmation.hidden) return;
  confirmation.hidden = true;
  if (isElement(trigger)) trigger.setAttribute("aria-expanded", "false");
}

/** @param {Document} document */
function optionsPanelOf(document) {
  return document.querySelector("[data-role='chat-options']");
}

/** @param {Document} document */
function optionsToggleOf(document) {
  return document.querySelector("[data-role='chat-options-toggle']");
}

/**
 * @param {Document} document
 * @param {boolean} open
 */
function setOptions(document, open) {
  const panel = optionsPanelOf(document);
  if (!isElement(panel)) return;
  panel.classList.toggle(OPEN_CLASS, open);
  const toggle = optionsToggleOf(document);
  if (isElement(toggle)) toggle.setAttribute("aria-expanded", String(open));
  // The confirmation belongs to the panel: closing the panel closes it too, so reopening never shows a stale question.
  if (!open) hideConfirmation(document);
}

/** @param {Document} document */
function optionsAreOpen(document) {
  const panel = optionsPanelOf(document);
  return isElement(panel) && panel.classList.contains(OPEN_CLASS);
}

/**
 * A tap on the page outside the open panel and its toggle closes the panel. The tap still reaches its own target, so a
 * tap on a message or on Clear chat keeps working.
 * @param {Document} document
 * @param {HTMLElement} target
 */
function closeOptionsOnOutsideTap(document, target) {
  if (!optionsAreOpen(document)) return;
  const panel = optionsPanelOf(document);
  if (!isElement(panel) || panel.contains(target)) return;
  if (target.closest("[data-role='chat-options-toggle']")) return;
  setOptions(document, false);
}

/**
 * Opens or closes the Options panel. `setOptions` also writes the toggle's aria-expanded.
 * @param {Document} document
 */
function toggleOptions(document) {
  setOptions(document, !optionsAreOpen(document));
}

/**
 * LiveView LiveSocket `dom.onBeforeElUpdated` hook: carries the open Options panel and its toggle's aria-expanded from
 * the element LiveView replaces to the new one, so a server patch does not close the panel. Returns nothing, so the
 * patch continues.
 * @param {Element} from
 * @param {Element} to
 */
export function keepOptionsState(from, to) {
  if (!isElement(from) || !isElement(to)) return;
  const role = from.dataset["role"];
  if (role === "chat-options") {
    to.classList.toggle(OPEN_CLASS, from.classList.contains(OPEN_CLASS));
  } else if (role === "chat-options-toggle") {
    const expanded = from.getAttribute("aria-expanded");
    if (expanded !== null) to.setAttribute("aria-expanded", expanded);
  }
}

/** @param {HTMLElement} message */
function toggleRaw(message) {
  message.dataset["view"] =
    message.dataset["view"] === "raw" ? "rendered" : "raw";
}

/**
 * @param {MouseEvent} event
 * @param {Document} document
 */
function handleClick(event, document) {
  const target = event.target;
  if (!isElement(target)) return;

  closeOptionsOnOutsideTap(document, target);

  const options = target.closest("[data-role='chat-options-toggle']");
  if (isElement(options)) {
    toggleOptions(document);
    return;
  }

  const clear = target.closest("[data-role='clear-chat']");
  if (isElement(clear)) {
    setConfirmation(
      clear.closest("[data-role='clear-chat-group']") ?? document,
      true,
    );
    return;
  }

  const cancel = target.closest("[data-role='clear-chat-cancel']");
  if (isElement(cancel)) {
    setConfirmation(
      cancel.closest("[data-role='clear-chat-group']") ?? document,
      false,
    );
    return;
  }

  // "Yes, delete" also sends the LiveView clear event: this click reaches LiveView after the confirmation closes.
  const yes = target.closest("[data-role='clear-chat-yes']");
  if (isElement(yes)) {
    setConfirmation(
      yes.closest("[data-role='clear-chat-group']") ?? document,
      false,
    );
    return;
  }

  const raw = target.closest("[data-role='raw-toggle']");
  if (isElement(raw)) {
    const message = raw.closest("[data-role='own-message']");
    if (isElement(message)) toggleRaw(message);
  }
}

/**
 * Escape closes the innermost open thing: the Clear chat confirmation first, then the options panel. When focus was in
 * the panel, it goes back to the Options toggle, so a keyboard user is not left in a closed panel.
 * @param {KeyboardEvent} event
 * @param {Document} document
 */
function handleEscape(event, document) {
  if (event.key !== "Escape") return;
  const target = event.target;
  if (!isElement(target)) return;
  const confirmation = confirmationOf(document);
  if (isElement(confirmation) && !confirmation.hidden) {
    // Escape closes the confirmation and keeps the conversation, like Cancel. Focus returns to Clear chat only when it
    // was inside the confirmation; otherwise the visitor's place stays where it is.
    event.preventDefault();
    const group =
      confirmation.closest("[data-role='clear-chat-group']") ?? document;
    if (group.contains(target)) {
      setConfirmation(group, false);
    } else {
      hideConfirmation(group);
    }
    return;
  }
  if (!optionsAreOpen(document)) return;
  event.preventDefault();
  setOptions(document, false);
  // Focus goes back to the toggle only when the visitor was working in the panel or on the toggle. From the message box
  // (or anywhere else) the visitor's place stays where it is.
  const panel = optionsPanelOf(document);
  const toggle = optionsToggleOf(document);
  const inPanel = isElement(panel) && panel.contains(target);
  if (isElement(toggle) && (inPanel || target === toggle)) toggle.focus();
}

/**
 * Focus leaving the confirmation's group closes it, so Tab cannot leave a question open behind the page. Focus moves that
 * the confirmation makes itself are skipped.
 * @param {FocusEvent} event
 */
function handleFocusOut(event) {
  if (movingFocus || pressInsideGroup) return;
  const target = event.target;
  const next = event.relatedTarget;
  if (!isElement(target)) return;
  const group = target.closest("[data-role='clear-chat-group']");
  if (!isElement(group)) return;
  if (isElement(next) && group.contains(next)) return;
  hideConfirmation(group);
}

/** @param {PointerEvent} event */
function handlePointerDown(event) {
  const target = event.target;
  pressInsideGroup =
    isElement(target) &&
    target.closest("[data-role='clear-chat-group']") !== null;
}

function endPress() {
  pressInsideGroup = false;
}

/**
 * Installs the Codex page controls on a document. Safe to call once per page load.
 * @param {Document} document
 */
export function installChatControls(document) {
  document.addEventListener("click", (event) => handleClick(event, document));
  document.addEventListener("keydown", (event) =>
    handleEscape(event, document),
  );
  document.addEventListener("focusout", handleFocusOut);
  document.addEventListener("pointerdown", handlePointerDown);
  document.addEventListener("pointerup", endPress);
  document.addEventListener("pointercancel", endPress);
}
