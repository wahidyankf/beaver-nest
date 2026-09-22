// Real (browser) message-rendering primitives shared by `real_store.js`'s
// several method factories -- split into its own file purely to stay under
// this project's max-lines lint budget. `real_store.js` is the only
// importer, and re-exports `RenderableMessage` under its own name so every
// other file's `import("./real_store.js").RenderableMessage` reference stays
// unchanged.

import { quoteNode } from "./message_quote_render.js";

const BOTTOM_THRESHOLD_PX = 80;

/**
 * Shape shared by every message this module renders, whether a pending
 * (outbox-owned, keyed by `clientMessageId`) or committed (server-owned,
 * keyed by `id`) row -- see `messageNode`'s own `pending` flag for which
 * fields a given call site actually has.
 * @typedef {object} RenderableMessage
 * @property {string} [id]
 * @property {string} [clientMessageId]
 * @property {string} body
 * @property {string} [status]
 * @property {string} [senderKind]
 * @property {string} [senderId]
 * @property {string} [senderDisplayName]
 * @property {string} [committedAt]
 * @property {import("./message_quote_render.js").MessageQuote | null} [replyTo] the message this one answers,
 *   resolved by the server. Absent on an ordinary message, and on every row
 *   written before replies existed -- the two are indistinguishable, by
 *   design.
 */

/** @param {string} value */
function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value;
  return div.innerHTML;
}

// tech-doc 005's hi-fi mockups color-code each sender's circular initial
// badge (teal/sun/coral, cycling); a message's own sender identity already
// determines its color deterministically, so no per-room color assignment
// state is needed -- the same sender always lands on the same color.
const AVATAR_PALETTE = ["#80c5b8", "#f7b84b", "#e5633d"];

/** @param {string} seed */
function avatarColorFor(seed) {
  let hash = 0;
  for (const codePoint of seed) {
    hash = Math.trunc(hash * 31 + (codePoint.codePointAt(0) ?? 0));
  }
  return AVATAR_PALETTE[Math.abs(hash) % AVATAR_PALETTE.length] ?? "#80c5b8";
}

/** @param {string} senderLabel */
function avatarNode(senderLabel) {
  const avatar = document.createElement("span");
  avatar.className = "family-chat-message-avatar";
  avatar.setAttribute("aria-hidden", "true");
  avatar.style.background = avatarColorFor(senderLabel || "?");
  avatar.textContent = (senderLabel || "?").charAt(0).toUpperCase();
  return avatar;
}

/**
 * @param {RenderableMessage} message
 * @param {string} senderLabel
 */
function bubbleNode(message, senderLabel) {
  const bubble = document.createElement("div");
  bubble.className = "family-chat-message-bubble";

  const meta = document.createElement("p");
  meta.className = "family-chat-message-meta";
  const time = message.committedAt
    ? `<time datetime="${message.committedAt}">${new Date(message.committedAt).toLocaleString()}</time>`
    : "";
  // Both carry a `data-role` because the action menu reads the sender and
  // the full body back out of the rendered row (see
  // `mount_browser_actions.js`), and a class name is a styling concern that
  // may legitimately change.
  meta.innerHTML =
    `<strong data-role="family-chat-message-sender">${escapeHtml(senderLabel)}</strong> ` +
    time;

  const body = document.createElement("p");
  body.className = "family-chat-message-body";
  body.dataset["role"] = "family-chat-message-body";
  body.textContent = message.body;

  bubble.append(meta);
  // Above the body, inside the bubble: the quote is context for what follows,
  // and a reader meeting it after the reply has already read the reply
  // without it.
  if (message.replyTo) bubble.append(quoteNode(message.replyTo));
  bubble.append(body);
  return bubble;
}

/**
 * The `⋯` trigger. Rendered for every message and hidden by `app.css` on
 * coarse pointers, where holding the message is the gesture and a
 * permanently visible control on every bubble would be noise.
 * @param {string} senderLabel
 */
function moreControlNode(senderLabel) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "family-chat-message-more";
  button.dataset["role"] = "family-chat-message-more";
  button.tabIndex = -1;
  button.setAttribute("aria-label", `Actions for ${senderLabel}'s message`);
  button.textContent = "⋯";
  return button;
}

/**
 * @param {RenderableMessage} message
 * @param {{pending: boolean, currentUserId?: string | null}} state
 */
export function messageNode(message, { pending, currentUserId }) {
  const li = document.createElement("li");
  const isSystem = message.senderKind === "system";
  // A pending row is always the visitor's own not-yet-committed draft --
  // `senderId` is a server-assigned field committed messages carry, never a
  // local outbox field, so there's nothing to compare it against yet.
  const isOwn =
    !isSystem &&
    (pending || (message.senderId ?? null) === (currentUserId ?? null));
  li.className = "family-chat-message";
  li.classList.add(
    isSystem
      ? "family-chat-message--system"
      : isOwn
        ? "family-chat-message--own"
        : "family-chat-message--other",
  );
  li.dataset["role"] = "family-chat-message";
  li.dataset["deliveryState"] = pending ? (message.status ?? "") : "committed";
  // The same key `real_store.js` files this row under: which message a
  // resumed room landed on, and which one the stored read position names,
  // are only observable from outside the page through this attribute.
  li.dataset["messageId"] = message.id ?? message.clientMessageId ?? "";
  // Skipped by Tab until `roving_focus.js` promotes exactly one item to the
  // history's single stop. Rendered here rather than left unset so a list
  // that is never refreshed is unreachable rather than fifty tab stops
  // deep -- the failure the roving invariant check catches.
  li.tabIndex = -1;

  const senderLabel = (isSystem ? "System" : message.senderDisplayName) ?? "";

  if (!isSystem) li.append(avatarNode(senderLabel));
  li.append(bubbleNode(message, senderLabel));
  li.append(moreControlNode(senderLabel));

  if (pending) {
    const status = document.createElement("p");
    status.className = "family-chat-message-status";
    status.dataset["role"] = "family-chat-message-status";
    status.textContent = message.status ?? "";
    li.append(status);
  }

  return li;
}

// How much already-read conversation stays visible above the unread marker
// when a room resumes. Landing with the marker flush against the top edge
// reads as "the history was cut off here"; a little context above it reads
// as "you were here", which is the whole point of resuming.
const RESUME_CONTEXT_PX = 72;

export const UNREAD_DIVIDER_LABEL = "New messages";

/**
 * The boundary between what this member has already read and what arrived
 * since. A real list item (not a decoration) so it sits in document order
 * inside the `role="log"` list and is announced in place, rather than being
 * hidden from the screen-reader rendering of the same conversation.
 */
export function unreadDividerNode() {
  const li = document.createElement("li");
  li.className = "family-chat-unread-divider";
  li.dataset["role"] = "family-chat-unread-divider";
  const label = document.createElement("span");
  label.textContent = UNREAD_DIVIDER_LABEL;
  li.append(label);
  return li;
}

/** @param {import("./elements.js").FamilyChatElements} elements */
export function scrollToBottom(elements) {
  if (!elements.history) return;
  elements.history.scrollTop = elements.history.scrollHeight;
}

/**
 * Places `target` just below the top edge of the history viewport. Uses
 * `offsetTop` differences rather than `scrollIntoView` so the position is
 * computed relative to the scrolling history container alone and never
 * scrolls the page itself (which on mobile would push the sticky header or
 * composer out of view).
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {HTMLElement} target
 */
export function scrollToResumeAnchor(elements, target) {
  const history = elements.history;
  if (!history) return;
  function place() {
    const offset =
      target.getBoundingClientRect().top -
      history.getBoundingClientRect().top +
      history.scrollTop -
      RESUME_CONTEXT_PX;
    history.scrollTop = Math.max(0, offset);
  }
  place();
  // Every message above the marker changes height again when the web fonts
  // arrive and when the first frame finishes laying out, which drags the
  // marker far from the edge it was just placed at -- a resumed room that
  // visibly jumps away from where the visitor left off. Re-anchoring on
  // both settlement points is what keeps the placement the one they see.
  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(place);
  }
  const fonts = globalThis.document?.fonts;
  if (fonts) void fonts.ready.then(place);
}

/**
 * The room is showing a window that stops short of the newest message, so
 * the indicator doubles as the way back to it.
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {boolean} pending
 */
export function setNewMessagesIndicator(elements, pending) {
  if (!elements.newMessages) return;
  elements.newMessages.hidden = !pending;
}

/** @param {import("./elements.js").FamilyChatElements} elements */
export function isNearBottom(elements) {
  const history = elements.history;
  if (!history) return true;
  return (
    history.scrollHeight - history.scrollTop - history.clientHeight <=
    BOTTOM_THRESHOLD_PX
  );
}

// tech-doc 005's History copy inventory names three distinct strings:
// "Beginning of family chat", "Load older messages", and "New messages
// below" -- the first replaces the second, and the button stops being
// actionable, once the server reports no earlier page (`hasOlder: false`).
/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {boolean} hasOlder
 */
export function setHasOlder(elements, hasOlder) {
  if (!elements.loadOlder) return;
  elements.loadOlder.disabled = !hasOlder;
  elements.loadOlder.textContent = hasOlder
    ? "Load older messages"
    : "Beginning of family chat";
}
