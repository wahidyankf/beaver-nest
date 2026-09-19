// Shared namespace storage and small pure utilities for `outbox.js`/
// `outbox_send.js` (split out purely to stay under this project's
// max-lines/max-lines-per-function lint budget -- `outbox.js` is still the
// one file feature code imports from).
//
// State is kept in one module-scoped, namespace-keyed store (namespace =
// `${userId}:${roomSlug}`), which survives across `initRoom` calls within
// the same browser session/process (a live tab, or one Vitest process).
// Cross-reload durability (a real closed/reopened tab) is `hydrateNamespace`
// below's job: `family_chat.js` calls it once per namespace, before
// constructing the outbox, to repopulate this in-memory store from real
// IndexedDB (`persistence_indexeddb.js`) -- see that file and `outbox.js`'s
// own header comment for the write-through half of this design.

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
 * @property {boolean} hydrated
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
    record = { messages: new Map(), cleared: false, hydrated: false };
    namespaces.set(key, record);
  }
  return record;
}

/**
 * Loads a namespace's queue from real persistence into the shared in-memory
 * store, exactly once per namespace per process. A second call for the same
 * key (a second `initRoom` within the same tab -- e.g. a LiveView-driven
 * remount) must never re-hydrate: that would silently resurrect a message a
 * live send has already deleted from memory but not yet removed from
 * IndexedDB (deletion there is its own best-effort async write, see
 * `persistence_indexeddb.js`).
 * @param {string} key
 * @param {import("./outbox_send.js").Persistence} persistence
 * @returns {Promise<NamespaceRecord>}
 */
export async function hydrateNamespace(key, persistence) {
  const record = getOrCreateNamespace(key);
  if (record.hydrated) return record;
  record.hydrated = true;

  const rows = await persistence.loadAll(key);
  for (const row of rows) {
    if (!record.messages.has(row.clientMessageId)) {
      record.messages.set(row.clientMessageId, row);
    }
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
