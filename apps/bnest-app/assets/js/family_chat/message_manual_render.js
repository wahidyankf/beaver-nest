// The Retry and Discard controls a row shows once its message has stopped
// at "Couldn't send" (tech-doc 005: "Couldn't send persists with Retry and
// Discard"). They are added the moment the row reaches that state and taken
// out the moment it leaves it, so a row never offers an action its state
// does not have.

import { DISCARD_LABEL, RETRY_LABEL } from "./message_actions.js";
import { STATUS } from "./outbox_namespace.js";

export const RETRY_ROLE = "family-chat-message-retry";
export const DISCARD_ROLE = "family-chat-message-discard";
export const MANUAL_ACTIONS_SELECTOR =
  '[data-role="family-chat-message-manual"]';

/**
 * @param {string} role
 * @param {string} label
 * @param {string} statusId
 */
function manualButton(role, label, statusId) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = role;
  button.dataset["role"] = role;
  // The history keeps one tab stop (`roving_focus.js`), so nothing inside a
  // message is tabbable; the keyboard reaches both actions through the
  // message's own menu instead (`menuItemsFor`).
  button.tabIndex = -1;
  button.textContent = label;
  // Which message it acts on is said by the status it sits under, never by
  // repeating the message body.
  button.setAttribute("aria-describedby", statusId);
  return button;
}

/**
 * @param {HTMLElement} row a pending message row.
 * @param {string} status the status the row now shows.
 */
export function syncManualActions(row, status) {
  const existing = row.querySelector(MANUAL_ACTIONS_SELECTOR);
  if (status !== STATUS.FAILED) {
    existing?.remove();
    return;
  }
  if (existing) return;
  const statusId =
    row.querySelector('[data-role="family-chat-message-status"]')?.id ?? "";
  const group = document.createElement("div");
  group.className = "family-chat-message-manual";
  group.dataset["role"] = "family-chat-message-manual";
  group.append(
    manualButton(RETRY_ROLE, RETRY_LABEL, statusId),
    manualButton(DISCARD_ROLE, DISCARD_LABEL, statusId),
  );
  row.append(group);
}
