// Shared namespace storage and small pure utilities for `outbox.js`/
// `outbox_send.js` (split out purely to stay under this project's
// max-lines/max-lines-per-function lint budget -- `outbox.js` is still the
// one file feature code imports from).
//
// State is kept in one module-scoped, namespace-keyed store (namespace =
// `${userId}:${roomSlug}`), which survives across `initRoom` calls within
// the same browser session/process (a live tab, or one Vitest process) but
// NOT a real tab close/reopen -- no real IndexedDB binding exists yet (see
// `family_chat.js`'s header comment's "KNOWN GAP" note).

export const STATUS = Object.freeze({
  WAITING: "Waiting for connection",
  SENDING: "Sending",
  RETRYING: "Retrying in …",
  SENT: "Sent",
  FAILED: "Couldn't send",
});

/** @type {Map<string, NamespaceRecord>} */
const namespaces = new Map();

/**
 * @typedef {object} NamespaceRecord
 * @property {Map<string, QueuedMessage>} messages
 * @property {boolean} cleared
 */

/**
 * @typedef {object} QueuedMessage
 * @property {string} clientMessageId
 * @property {string} body
 * @property {string} status
 * @property {number} attempt
 * @property {number} retryCount
 * @property {number} createdAt
 * @property {number} nextRetryAt
 * @property {boolean} neverSucceed
 * @property {unknown} timerHandle
 */

/** @param {string} userId @param {string} roomSlug */
export function namespaceKey(userId, roomSlug) {
  return `${userId}:${roomSlug}`;
}

/** @param {string} key */
export function getOrCreateNamespace(key) {
  let record = namespaces.get(key);
  if (!record) {
    record = { messages: new Map(), cleared: false };
    namespaces.set(key, record);
  }
  return record;
}

/** @param {() => number} random */
export function generateClientMessageId(random) {
  const hex = () => Math.floor(random() * 16).toString(16);
  /** @param {number} length */
  const block = (length) => Array.from({ length }, hex).join("");
  return `${block(8)}-${block(4)}-4${block(3)}-${(8 + Math.floor(random() * 4)).toString(16)}${block(3)}-${block(12)}`;
}
