// Real-browser IndexedDB binding for `outbox.js`'s write-through
// `Persistence` contract (`outbox_send.js`'s own typedef) -- the piece this
// plan's Phase 4 learnings.md and `family_chat.js`'s former "KNOWN GAP"
// comment both flagged as never actually implemented. `family_chat.js` is
// the only caller, and only on its `hasDocument` branch: this module touches
// the global `indexedDB`, which does not exist in FE_UNIT's Node/Vitest
// process, so nothing here may be imported eagerly by anything that also
// runs there without a real `document`.
//
// Split into several small functions purely to stay under this project's
// max-lines-per-function lint budget -- `resolvePersistence` below is the
// only export `family_chat.js` needs to know about.

import { namespaceKey, hydrateNamespace } from "./outbox.js";

const DB_NAME = "bnest-family-chat-outbox";
const DB_VERSION = 1;
const STORE_NAME = "queuedMessages";
const NAMESPACE_INDEX = "namespace";

/** @param {string} namespace @param {string} clientMessageId */
function rowKey(namespace, clientMessageId) {
  return `${namespace}::${clientMessageId}`;
}

/**
 * @typedef {{
 *   clientMessageId: string,
 *   body: string,
 *   replyToMessageId?: string,
 *   status: string,
 *   attempt: number,
 *   retryCount: number,
 *   createdAt: number,
 *   nextRetryAt: number,
 *   neverSucceed: boolean,
 * }} PersistedRow
 */

/**
 * @param {string} namespace
 * @param {import("./outbox_namespace.js").QueuedMessage} message
 */
function toRow(namespace, message) {
  return {
    key: rowKey(namespace, message.clientMessageId),
    namespace,
    clientMessageId: message.clientMessageId,
    body: message.body,
    // Written only when there is a target, so a stored row for an ordinary
    // message is byte-for-byte what it was before replies existed -- which
    // is why `DB_VERSION` stays at 1 and no migration is needed in either
    // direction.
    ...(message.replyToMessageId === undefined
      ? {}
      : { replyToMessageId: message.replyToMessageId }),
    status: message.status,
    attempt: message.attempt,
    retryCount: message.retryCount,
    createdAt: message.createdAt,
    nextRetryAt: message.nextRetryAt,
    neverSucceed: message.neverSucceed,
  };
}

/** @param {IDBRequest} request */
function requestPromise(request) {
  return new Promise((resolve, reject) => {
    request.addEventListener("success", () => resolve(request.result));
    request.addEventListener("error", () => reject(request.error));
  });
}

/** @param {IDBDatabase} db */
function ensureStore(db) {
  if (db.objectStoreNames.contains(STORE_NAME)) return;
  const store = db.createObjectStore(STORE_NAME, { keyPath: "key" });
  store.createIndex(NAMESPACE_INDEX, "namespace", { unique: false });
}

/** @returns {Promise<IDBDatabase>} */
function openDb() {
  const request = indexedDB.open(DB_NAME, DB_VERSION);
  request.addEventListener("upgradeneeded", () => ensureStore(request.result));
  return requestPromise(request);
}

/**
 * @param {IDBDatabase} database
 * @param {"readonly"|"readwrite"} mode
 * @param {(store: IDBObjectStore) => void} run
 * @returns {Promise<void>}
 */
function withStore(database, mode, run) {
  return new Promise((resolve, reject) => {
    const tx = database.transaction(STORE_NAME, mode);
    run(tx.objectStore(STORE_NAME));
    tx.addEventListener("complete", () => resolve());
    tx.addEventListener("error", () => reject(tx.error));
  });
}

/**
 * Kicks off a cursor walk deleting every row for `namespace`, synchronously,
 * within an already-open transaction -- the cursor's own pending requests
 * keep that transaction alive, so `withStore`'s own `complete` event is the
 * real completion signal here, not this function's return.
 * @param {IDBObjectStore} store
 * @param {string} namespace
 */
function deleteAllForNamespace(store, namespace) {
  const request = store
    .index(NAMESPACE_INDEX)
    .openKeyCursor(IDBKeyRange.only(namespace));
  request.addEventListener("success", () => {
    const cursor = request.result;
    if (!cursor) return;
    store.delete(cursor.primaryKey);
    cursor.continue();
  });
}

/**
 * @param {PersistedRow} row
 * @returns {import("./outbox_namespace.js").QueuedMessage}
 */
function toQueuedMessage(row) {
  return { ...row, timerHandle: undefined };
}

/**
 * Every write below is best-effort: a browser that refuses IndexedDB
 * (private mode, storage disabled by policy) degrades to this session's
 * existing in-memory-only behavior rather than breaking the room, matching
 * `app.js`'s own established try/catch-and-continue pattern for
 * `sessionStorage`/`localStorage`.
 * @param {() => Promise<IDBDatabase>} db
 * @param {string} namespace
 */
async function loadAllRows(db, namespace) {
  try {
    const database = await db();
    const tx = database.transaction(STORE_NAME, "readonly");
    const index = tx.objectStore(STORE_NAME).index(NAMESPACE_INDEX);
    /** @type {PersistedRow[]} */
    const rows = await requestPromise(index.getAll(namespace));
    return rows.map((row) => toQueuedMessage(row));
  } catch {
    return [];
  }
}

/**
 * @param {() => Promise<IDBDatabase>} db
 * @param {(store: IDBObjectStore) => void} run
 */
function writeThrough(db, run) {
  void db()
    .then((database) => withStore(database, "readwrite", run))
    .catch(() => {
      // Best-effort; see `loadAllRows`'s own header comment.
    });
}

/**
 * Real-browser-only persistence adapter (requires a global `indexedDB`);
 * `family_chat.js` only ever constructs this on its `hasDocument` branch.
 * @returns {import("./outbox_send.js").Persistence}
 */
export function createIndexedDbPersistence() {
  /** @type {Promise<IDBDatabase> | null} */
  let dbPromise = null;
  const db = () => (dbPromise ??= openDb());

  return {
    loadAll: (namespace) => loadAllRows(db, namespace),
    save: (namespace, message) =>
      writeThrough(db, (store) => store.put(toRow(namespace, message))),
    remove: (namespace, clientMessageId) =>
      writeThrough(db, (store) =>
        store.delete(rowKey(namespace, clientMessageId)),
      ),
    clear: (namespace) =>
      writeThrough(db, (store) => deleteAllForNamespace(store, namespace)),
  };
}

/**
 * `family_chat.js`'s own persistence-resolution seam (tech-doc 003 /
 * `outbox.js`'s header comment's "attached separately by `family_chat.js`"
 * design): in the real browser this is always real IndexedDB, unless a test
 * explicitly injects its own (useful for a real-browser E2E harness too); in
 * FE_UNIT's Node process it stays whatever the caller passed (usually
 * undefined -- pure in-memory, exactly as before this fix -- unless a test
 * explicitly opts into proving the write-through contract with a fake; see
 * `family_chat.steps.ts`'s own comment). Hydrating before `createOutbox`
 * (rather than after) means its own `resumeOnOpen` sees any resumed message
 * immediately, with zero special-casing on its part.
 * @param {boolean} hasDocument
 * @param {string} userId
 * @param {string} roomSlug
 * @param {import("./outbox_send.js").Persistence | undefined} injected
 */
export async function resolvePersistence(
  hasDocument,
  userId,
  roomSlug,
  injected,
) {
  const persistence = hasDocument
    ? (injected ?? createIndexedDbPersistence())
    : injected;
  if (persistence) {
    await hydrateNamespace(namespaceKey(userId, roomSlug), persistence);
  }
  return persistence;
}
