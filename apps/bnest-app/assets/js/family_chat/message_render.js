// Real (browser) message-rendering primitives shared by `real_store.js`'s
// several method factories -- split into its own file purely to stay under
// this project's max-lines lint budget. `real_store.js` is the only
// importer, and re-exports `RenderableMessage` under its own name so every
// other file's `import("./real_store.js").RenderableMessage` reference stays
// unchanged.

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
  meta.innerHTML = `<strong>${escapeHtml(senderLabel)}</strong> ${time}`;

  const body = document.createElement("p");
  body.className = "family-chat-message-body";
  body.textContent = message.body;

  bubble.append(meta, body);
  return bubble;
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

  const senderLabel = (isSystem ? "System" : message.senderDisplayName) ?? "";

  if (!isSystem) li.append(avatarNode(senderLabel));
  li.append(bubbleNode(message, senderLabel));

  if (pending) {
    const status = document.createElement("p");
    status.className = "family-chat-message-status";
    status.dataset["role"] = "family-chat-message-status";
    status.textContent = message.status ?? "";
    li.append(status);
  }

  return li;
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
