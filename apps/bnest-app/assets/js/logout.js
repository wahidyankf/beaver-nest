// Logging out removes the member's queued family-chat messages from this
// device first (tech-doc 003: a queue is scoped to the member who wrote it,
// and a shared device must not send it later as anyone). The server ends the
// session and revokes push on its own; only the device's queue is ours.

import { createIndexedDbPersistence } from "./family_chat/persistence_indexeddb.js";

/** How long log-out waits for the device before going ahead regardless. */
const CLEAR_TIMEOUT_MS = 2000;

/**
 * @typedef {{ clearUser(userId: string): Promise<void> }} QueueClearing
 */

/**
 * @param {QueueClearing} persistence
 * @param {string} userId
 * @param {number} timeoutMs
 * @returns {Promise<void>}
 */
async function clearWithin(persistence, userId, timeoutMs) {
  const cleared = Promise.resolve()
    .then(() => persistence.clearUser(userId))
    .catch(() => {
      // A device that refuses storage has nothing queued to leak, and the
      // member must still be able to log out.
    });
  const timedOut = new Promise((resolve) => {
    setTimeout(resolve, timeoutMs);
  });
  await Promise.race([cleared, timedOut]);
}

/**
 * @param {{persistence?: QueueClearing, timeoutMs?: number}} [options]
 */
export function wireLogoutQueueClearing({
  persistence,
  timeoutMs = CLEAR_TIMEOUT_MS,
} = {}) {
  const form = document.querySelector('form[data-role="logout"]');
  if (!(form instanceof HTMLFormElement)) return;
  const userId = form.dataset["currentUserId"];
  if (!userId) return;

  let leaving = false;
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    if (leaving) return;
    leaving = true;
    // Opened only on a page that is logging out, never on every page load.
    const store = persistence ?? createIndexedDbPersistence();
    void clearWithin(store, userId, timeoutMs).then(() => form.submit());
  });
}
