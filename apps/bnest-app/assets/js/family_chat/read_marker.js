// Where a member's own device left off in a room: the id of the newest
// message they have actually reached the bottom of. `history.js` reads it
// once when the room opens, to decide whether to land the visitor on their
// first unread message or on the newest one, and writes it back whenever the
// newest rendered message is at the bottom of the viewport.
//
// Deliberately browser-local (Web Storage, one small scalar per member and
// room) rather than a server record: it is convenience state, never
// authoritative, and losing it degrades to opening at the newest message --
// exactly what the room did before this existed. See the frontend
// architecture model's "Room read position" data store for the constraint
// this implements. It is *not* the IndexedDB outbox's namespace: that one
// holds unsent messages and has its own durability contract
// (`persistence_indexeddb.js`).

const KEY_PREFIX = "bnest.family-chat.last-read";

/**
 * The `Storage` subset this module needs -- `window.localStorage` satisfies
 * it structurally, and so does the in-memory fallback below.
 * @typedef {object} ReadMarkerStorage
 * @property {(key: string) => string | null} getItem
 * @property {(key: string, value: string) => void} setItem
 * @property {(key: string) => void} removeItem
 */

/** @returns {ReadMarkerStorage} */
export function createMemoryReadStorage() {
  /** @type {Map<string, string>} */
  const entries = new Map();
  return {
    getItem: (key) => entries.get(key) ?? null,
    setItem: (key, value) => {
      entries.set(key, value);
    },
    removeItem: (key) => {
      entries.delete(key);
    },
  };
}

/**
 * Real `localStorage` when this browser both has it and lets us touch it --
 * a private window, blocked site data, or a storage-partitioned embed can
 * make the property itself throw on access, not merely return null, so the
 * probe below is a genuine read rather than a truthiness check. Anything
 * short of a working store falls back to a per-session in-memory one: the
 * room then simply opens at the newest message every time, which is the
 * documented degradation.
 * @param {ReadMarkerStorage} [provided]
 * @returns {ReadMarkerStorage}
 */
export function resolveReadStorage(provided) {
  if (provided) return provided;
  try {
    const storage = globalThis.localStorage;
    if (!storage) return createMemoryReadStorage();
    storage.getItem(`${KEY_PREFIX}.probe`);
    return storage;
  } catch {
    return createMemoryReadStorage();
  }
}

/**
 * Message ids are the server's own autoincrement rowids, serialized as
 * GraphQL `ID` strings. Comparing them numerically (rather than
 * lexicographically, where "9" sorts after "10") is what keeps the stored
 * position monotonic: a late-arriving catch-up page must never drag the
 * marker backwards past messages the visitor already read.
 * @param {string | null} current
 * @param {string} candidate
 */
function furthest(current, candidate) {
  if (current === null) return candidate;
  const currentValue = Number(current);
  const candidateValue = Number(candidate);
  if (!Number.isFinite(currentValue) || !Number.isFinite(candidateValue)) {
    return candidate;
  }
  return candidateValue > currentValue ? candidate : current;
}

/**
 * @param {{
 *   userId: string,
 *   roomSlug: string,
 *   storage?: ReadMarkerStorage | undefined,
 * }} options
 */
export function createReadMarker({ userId, roomSlug, storage }) {
  const store = resolveReadStorage(storage);
  const key = `${KEY_PREFIX}.${userId}.${roomSlug}`;

  /** @returns {string | null} */
  function lastReadId() {
    try {
      const stored = store.getItem(key);
      return stored === null || stored === "" ? null : stored;
    } catch {
      return null;
    }
  }

  return {
    lastReadId,

    /** @param {string | null} messageId */
    remember(messageId) {
      if (messageId === null || messageId === "") return;
      const next = furthest(lastReadId(), messageId);
      try {
        store.setItem(key, next);
      } catch {
        // A full or read-only quota is not a reason to fail the room; the
        // visitor just resumes at the newest message next time.
      }
    },

    forget() {
      try {
        store.removeItem(key);
      } catch {
        // Same reasoning as `remember`.
      }
    },
  };
}
