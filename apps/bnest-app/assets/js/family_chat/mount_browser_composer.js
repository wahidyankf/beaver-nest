// The composer half of `mount_browser.js`: binding the real `<textarea>`,
// Send button, and key events to `composer.js`'s DOM-independent decisions,
// plus the pending-row lifecycle a queued send drives. Split into its own
// file purely to stay under this project's max-lines lint budget;
// `mount_browser.js` is the only importer.

import { DISCARD_ROLE, RETRY_ROLE } from "./message_manual_render.js";
import { STATUS } from "./outbox.js";

/** @typedef {import("./mount_browser.js").MountableRoom} MountableRoom */
/** @typedef {import("./elements.js").FamilyChatElements} FamilyChatElements */

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {string} clientMessageId
 */
function watchPendingMessage(room, elements, clientMessageId) {
  const unsubscribe = room.outbox.onChange(clientMessageId, (status) => {
    room.store.updatePendingStatus(clientMessageId, status);
    elements.outboxStatus.textContent = status === STATUS.SENT ? "" : status;

    if (status === STATUS.SENT) {
      // The one authoritative reconciliation point (tech-doc 005: replace
      // the pending row by its client UUID with the server-ID row, never a
      // second bubble) -- keyed from *this send's own* mutation response,
      // never guessed from a later subscription push, which never carries
      // the client-chosen ID at all (tech-doc 008).
      const committedMessage = room.outbox.committedMessage(clientMessageId);
      // `outbox.js` deliberately types this loosely (`object`) since it has
      // no knowledge of `RenderableMessage`'s shape; `family_chat.js` is
      // the layer that knows every real committed message has it.
      if (committedMessage) {
        room.store.reconcile(
          clientMessageId,
          /** @type {import("./real_store.js").RenderableMessage} */
          (committedMessage),
        );
        // Our own message, sent from the bottom of the conversation: the
        // member has by definition read everything up to it.
        room.history.noteArrival();
      }
      unsubscribe();
    }
    // Still listening at "Couldn't send": the member can retry it from
    // there, and the retry's statuses land on this same row. A discard
    // drops the listener with the message (`outbox.discard`).
  });
}

export const DISCARD_CONFIRMATION =
  "Discard this message? It hasn't been sent, and it will be removed from this device.";
export const DISCARDED_ANNOUNCEMENT = "Message discarded.";

/**
 * @param {MountableRoom} room
 * @param {string} clientMessageId
 */
export function retryFailedMessage(room, clientMessageId) {
  room.outbox.retry(clientMessageId);
}

/**
 * Discarding removes the only copy there is, so the member confirms first
 * (tech-doc 005). Focus goes to the message input: the row it came from is
 * gone.
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 * @param {string} clientMessageId
 * @returns {boolean} whether the message was discarded.
 */
export function discardFailedMessage(room, elements, clientMessageId) {
  if (!window.confirm(DISCARD_CONFIRMATION)) return false;
  if (!room.outbox.discard(clientMessageId)) return false;
  room.store.removePending(clientMessageId);
  elements.outboxStatus.textContent = "";
  elements.liveRegion.textContent = DISCARDED_ANNOUNCEMENT;
  elements.input.focus({ preventScroll: true });
  return true;
}

/**
 * The row's own Retry and Discard, delegated from the list like every
 * other per-message control (see `mount_browser_actions.js`'s header).
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
function wireManualActions(room, elements) {
  elements.list.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) return;
    const button = event.target.closest(
      `[data-role="${RETRY_ROLE}"], [data-role="${DISCARD_ROLE}"]`,
    );
    if (!(button instanceof HTMLElement)) return;
    const row = button.closest('[data-role="family-chat-message"]');
    const clientMessageId =
      row instanceof HTMLElement ? row.dataset["messageId"] : undefined;
    if (!clientMessageId) return;
    if (button.dataset["role"] === RETRY_ROLE) {
      retryFailedMessage(room, clientMessageId);
    } else {
      discardFailedMessage(room, elements, clientMessageId);
    }
  });
}

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
async function submitComposer(room, elements) {
  elements.remediation.hidden = true;
  room.composer.type(elements.input.value);
  // Cleared before the queue is awaited, and put back from the composer's own
  // draft if it refuses, so the input is usable again in the same frame the
  // member pressed send rather than one network round trip later.
  elements.input.value = "";

  const result = await room.composer.submit();
  elements.input.value = room.composer.draft();
  // The send control never takes focus (see `wireComposerFocus`); this only
  // restores it for a browser that moved it anyway, and is a no-op otherwise.
  elements.input.focus({ preventScroll: true });

  if (!result.queued || result.clientMessageId === null) {
    elements.remediation.hidden = false;
    elements.remediation.textContent = result.remediation ?? "";
    return;
  }

  // The row itself was already rendered by the composer's own `onQueued`
  // hook (see `family_chat.js`); only its delivery state still needs
  // following from here.
  watchPendingMessage(room, elements, result.clientMessageId);
}

/** @param {Event} event */
function keepFocus(event) {
  event.preventDefault();
}

/**
 * Keeps the on-screen keyboard up across a send. Activating the Send button
 * would otherwise blur the textarea, and a mobile keyboard dismissed by a
 * blur does not come back without a fresh user gesture -- which is exactly
 * the "hard to keep typing" this fixes. Refocusing the input *after* a send
 * would already be too late on iOS and Android. Preventing the pointer/mouse
 * press default suppresses only the focus change; the `click` that submits
 * the form still fires.
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireComposerFocus(room, elements) {
  elements.send.addEventListener("pointerdown", keepFocus);
  elements.send.addEventListener("mousedown", keepFocus);

  elements.input.addEventListener("keydown", (event) => {
    if (room.composer.keyIntent(event) !== "send") return;
    // Otherwise the newline this key would insert lands in the next message.
    event.preventDefault();
    void submitComposer(room, elements);
  });
}

/**
 * Renders whatever `resumeOnOpen` (`outbox_send.js`, run at `createOutbox`
 * construction) already resumed draining internally -- a message left over
 * from a closed tab (real IndexedDB) or an already-in-flight one from this
 * same session -- exactly like `submitComposer` renders a fresh send, so a
 * resumed message is visible and live-updating on screen, not just quietly
 * resumed in the outbox's own state.
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function renderResumedPendingMessages(room, elements) {
  for (const message of room.outbox.pendingMessages()) {
    room.store.renderPending({
      clientMessageId: message.clientMessageId,
      body: message.body,
      status: message.status,
      senderKind: "user",
      senderDisplayName: "You",
    });
    watchPendingMessage(room, elements, message.clientMessageId);
  }
  // A resumed send that committed after the history page was read is Sent, so
  // not pending above, and in no history page. `reconcile` appends it, or
  // leaves the row alone when the history already shows it.
  for (const [clientMessageId, committed] of room.outbox.committedMessages()) {
    room.store.reconcile(
      clientMessageId,
      /** @type {import("./real_store.js").RenderableMessage} */
      (committed),
    );
  }
}

/**
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
export function wireComposer(room, elements) {
  elements.composer.addEventListener("submit", (event) => {
    event.preventDefault();
    void submitComposer(room, elements);
  });
  wireComposerFocus(room, elements);
  wireManualActions(room, elements);
}

export { renderResumedPendingMessages };
