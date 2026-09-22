// The action-menu and reply-strip half of `mount_browser.js`: binding real
// pointer, context-menu, and key events to `message_actions.js`'s
// DOM-independent decisions, and rendering the one menu host and the one
// reply strip the shipped template provides. Split into its own file purely
// to stay under this project's max-lines lint budget.
//
// Every binding here is delegated from the message list rather than attached
// per message, because messages are created and replaced continuously
// (pending → committed, older pages prepended, reconnect catch-up merged)
// and a per-node listener would have to be re-attached on each of those
// paths -- one of which would eventually be forgotten.

import {
  createHoldGesture,
  createMenuState,
  menuItemsFor,
  runCopyAction,
} from "./message_actions.js";
import { anchorMenu, bindReanchor } from "./menu_anchor.js";
import { bodyPreview } from "./reply_target.js";

/** @typedef {import("./mount_browser.js").MountableRoom} MountableRoom */
/** @typedef {import("./elements.js").FamilyChatElements} FamilyChatElements */
/** @typedef {import("./message_actions.js").ActionableMessage} ActionableMessage */

const MESSAGE_SELECTOR = '[data-role="family-chat-message"]';

/**
 * @param {EventTarget | null} target
 * @returns {HTMLElement | null}
 */
function messageElementFrom(target) {
  if (!(target instanceof Element)) return null;
  return (
    /** @type {HTMLElement | null} */
    (target.closest(MESSAGE_SELECTOR))
  );
}

/**
 * Reads back what the renderer put in the DOM rather than consulting the
 * store: the rendered row is what the member is acting on, and a menu opened
 * on a row the store has since replaced should still describe that row.
 * @param {HTMLElement} element
 * @returns {ActionableMessage}
 */
function messageFrom(element) {
  const committed = element.dataset["deliveryState"] === "committed";
  const key = element.dataset["messageId"] ?? "";
  const body =
    element.querySelector('[data-role="family-chat-message-body"]')
      ?.textContent ?? "";
  const senderDisplayName =
    element.querySelector('[data-role="family-chat-message-sender"]')
      ?.textContent ?? "";
  return {
    clientMessageId: key,
    messageId: committed ? key : null,
    body,
    senderDisplayName,
  };
}

/**
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 * @param {import("./message_actions.js").MenuState} menu
 * @param {ActionableMessage} message
 * @param {import("./message_actions.js").MenuItem} item
 * @returns {boolean} whether the item placed keyboard focus itself.
 */
function runMenuItem(room, elements, menu, message, item) {
  menu.close();
  if (item.label === "Reply") {
    room.replyTarget?.select({
      messageId: message.messageId ?? null,
      // Bounded here, not in the strip's CSS: this target is built from the
      // full body of a bubble on screen, and a preview a screen reader reads
      // straight through is not a preview.
      bodyPreview: bodyPreview(message.body),
      senderDisplayName: message.senderDisplayName,
    });
    elements.input.focus({ preventScroll: true });
    // The one close path that does not send focus back to the message: the
    // member is about to type. Returning it would take the composer away
    // from them in the same gesture that opened it.
    return true;
  }
  void runCopyAction(message, {
    writeText: globalThis.navigator?.clipboard?.writeText?.bind(
      globalThis.navigator.clipboard,
    ),
    announce: (text) => {
      elements.liveRegion.textContent = text;
    },
  });
  return false;
}

/**
 * Renders the menu for one message into the single host element, replacing
 * whatever it held. An unavailable `Reply` stays focusable and keeps its
 * reason, so a screen-reader user hears why instead of finding an item that
 * silently is not there.
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 * @param {import("./message_actions.js").MenuState} menu
 * @param {ActionableMessage | null} message
 */
function renderMenu(room, elements, menu, message) {
  const host = elements.messageActions;
  host.replaceChildren();
  host.hidden = message === null;
  if (message === null) return;

  host.dataset["messageId"] = message.clientMessageId;
  for (const item of menuItemsFor(message)) {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("role", "menuitem");
    button.dataset["role"] = "family-chat-message-action";
    button.dataset["action"] = item.label;
    button.textContent = item.label;
    if (!item.available) {
      button.setAttribute("aria-disabled", "true");
      button.setAttribute("aria-description", item.reason ?? "");
    }
    button.addEventListener("click", (event) => {
      if (!item.available) return;
      // An item that placed focus itself keeps the click from reaching the
      // host's own "every close path restores focus" listener below.
      if (runMenuItem(room, elements, menu, message, item)) {
        event.stopPropagation();
      }
    });
    host.append(button);
  }
  // After the items exist, so the host has the height the placement needs.
  anchorMenu(host, elements.list, message.clientMessageId);
  /** @type {HTMLButtonElement | null} */
  (host.querySelector("button"))?.focus({ preventScroll: true });
}

/**
 * The four triggers of tech-doc 004's "One menu, four triggers", all calling
 * the same `menu.open`.
 * @param {FamilyChatElements} elements
 * @param {import("./message_actions.js").MenuState} menu
 * @param {import("./clock.js").Clock} clock
 */
function bindMenuTriggers(elements, menu, clock) {
  /** @type {HTMLElement | null} */
  let pressed = null;
  const gesture = createHoldGesture({
    clock,
    onHold: () => {
      if (pressed) menu.open(messageFrom(pressed));
    },
  });

  elements.list.addEventListener("pointerdown", (event) => {
    pressed = messageElementFrom(event.target);
    if (pressed) gesture.start({ x: event.clientX, y: event.clientY });
  });
  elements.list.addEventListener("pointermove", (event) => {
    gesture.move({ x: event.clientX, y: event.clientY });
  });
  elements.list.addEventListener("pointerup", () => gesture.end());
  elements.list.addEventListener("pointercancel", () => gesture.cancel());

  elements.list.addEventListener("contextmenu", (event) => {
    const element = messageElementFrom(event.target);
    if (!element) return;
    // Substituting our menu for the browser's own callout is the whole
    // point of handling this event at all.
    event.preventDefault();
    menu.open(messageFrom(element));
  });

  elements.list.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) return;
    if (!event.target.closest('[data-role="family-chat-message-more"]')) return;
    const element = messageElementFrom(event.target);
    if (element) menu.open(messageFrom(element));
  });

  elements.list.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    const element = messageElementFrom(event.target);
    if (!element) return;
    event.preventDefault();
    menu.open(messageFrom(element));
  });
}

/**
 * `ArrowUp`/`ArrowDown` move between messages, `Home`/`End` jump to the
 * oldest loaded and the newest. Tab is left alone: it enters the history
 * once and leaves it once, which is the whole reason the stop roves.
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
function bindRovingKeys(room, elements) {
  const ROVING_KEYS = new Set(["ArrowUp", "ArrowDown", "Home", "End"]);
  elements.list.addEventListener("keydown", (event) => {
    if (!ROVING_KEYS.has(event.key)) return;
    if (!messageElementFrom(event.target)) return;
    // Otherwise Arrow/Home/End scroll the history out from under the reader
    // at the same time as moving the stop.
    event.preventDefault();
    room.store.rovingMove(event.key);
  });
}

/**
 * Every close path returns focus to the message the menu was opened from --
 * Escape, choosing an item, and clicking outside alike.
 * @param {FamilyChatElements} elements
 * @param {import("./message_actions.js").MenuState} menu
 */
function bindMenuDismissal(elements, menu) {
  function restoreFocus() {
    const last = menu.returnFocusTo();
    if (!last) return;
    const selector = `${MESSAGE_SELECTOR}[data-message-id="${CSS.escape(last.clientMessageId)}"]`;
    /** @type {HTMLElement | null} */
    (elements.list.querySelector(selector))?.focus({ preventScroll: true });
  }

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || !menu.isOpen()) return;
    menu.close();
    restoreFocus();
  });

  document.addEventListener("pointerdown", (event) => {
    if (!menu.isOpen()) return;
    if (!(event.target instanceof Node)) return;
    if (elements.messageActions.contains(event.target)) return;
    menu.close();
  });

  elements.messageActions.addEventListener("click", () => restoreFocus());
}

/**
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 * @param {import("./clock.js").Clock} clock
 */
export function wireMessageActions(room, elements, clock) {
  const menu = createMenuState();
  menu.onChange((message) => renderMenu(room, elements, menu, message));
  bindMenuTriggers(elements, menu, clock);
  bindMenuDismissal(elements, menu);
  bindReanchor(elements.messageActions, elements.list);
  bindRovingKeys(room, elements);
}

/**
 * The strip is driven entirely by the reply target's own change
 * notifications, so there is no second place that decides whether it is
 * showing -- selecting, cancelling, sending, and a refused send all reach it
 * through the same one channel.
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
export function wireReplyStrip(room, elements) {
  const replyTarget = room.replyTarget;
  if (!replyTarget) return;

  replyTarget.onChange((selection) => {
    elements.replyStrip.hidden = selection === null;
    elements.replyStripName.textContent = selection
      ? `Replying to ${selection.senderDisplayName}`
      : "";
    elements.replyStripPreview.textContent = selection?.bodyPreview ?? "";
  });

  elements.replyStripCancel.addEventListener("click", () => {
    replyTarget.clear();
    elements.input.focus({ preventScroll: true });
  });

  elements.input.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || !replyTarget.isSet()) return;
    // Only when there is a target to cancel: Escape in a textarea otherwise
    // belongs to whatever the browser or the member expects it to do.
    event.preventDefault();
    replyTarget.clear();
  });
}
