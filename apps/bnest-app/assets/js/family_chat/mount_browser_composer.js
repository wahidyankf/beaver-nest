// The composer half of `mount_browser.js`: binding the real `<textarea>`,
// Send button, and key events to `composer.js`'s DOM-independent decisions,
// plus the pending-row lifecycle a queued send drives. Split into its own
// file purely to stay under this project's max-lines lint budget;
// `mount_browser.js` is the only importer.

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
    } else if (status === STATUS.FAILED) {
      unsubscribe();
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

/**
 * Keeps the on-screen keyboard up across a send. Activating the Send button
 * would otherwise blur the textarea, and a mobile keyboard dismissed by a
 * blur does not come back without a fresh user gesture -- which is exactly
 * the "hard to keep typing" this fixes. Preventing the pointer/mouse press
 * default suppresses only the focus change; the `click` that submits the
 * form still fires.
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireComposerFocus(room, elements) {
  /** @param {Event} event */
  function keepFocus(event) {
    if (!room.composer.focusFollowsSendControl()) event.preventDefault();
  }
  elements.send.addEventListener("pointerdown", keepFocus);
  elements.send.addEventListener("mousedown", keepFocus);

  elements.input.addEventListener("focus", () => room.composer.focus());
  elements.input.addEventListener("blur", () => room.composer.blur());

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
}

export { renderResumedPendingMessages };
