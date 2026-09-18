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
 * @property {string} [senderDisplayName]
 * @property {string} [committedAt]
 */

/** @param {string} value */
function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value;
  return div.innerHTML;
}

/**
 * @param {RenderableMessage} message
 * @param {{pending: boolean}} state
 */
export function messageNode(message, { pending }) {
  const li = document.createElement("li");
  li.className = "family-chat-message";
  li.dataset["role"] = "family-chat-message";
  li.dataset["deliveryState"] = pending ? (message.status ?? "") : "committed";
  if (message.senderKind === "system")
    li.classList.add("family-chat-message--system");

  const meta = document.createElement("p");
  meta.className = "family-chat-message-meta";
  const senderLabel =
    message.senderKind === "system" ? "System" : message.senderDisplayName;
  const time = message.committedAt
    ? `<time datetime="${message.committedAt}">${new Date(message.committedAt).toLocaleString()}</time>`
    : "";
  meta.innerHTML = `<strong>${escapeHtml(senderLabel ?? "")}</strong> ${time}`;

  const body = document.createElement("p");
  body.className = "family-chat-message-body";
  body.textContent = message.body;

  li.append(meta, body);

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
