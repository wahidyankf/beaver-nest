// Wires a mounted room's DOM/outbox/store/reconnect collaborators to the
// real browser -- split out of `family_chat.js`, and split further into
// several small functions, purely to stay under this project's
// max-lines/max-lines-per-function lint budget. `mountBrowser` below is the
// only export `family_chat.js` needs to know about.

import { STATUS } from "./outbox.js";
import { CONTROL_TEXT } from "./push.js";
import { promoteSlot } from "./reconnect.js";
import { request as graphqlRequest } from "./graphql.js";
import { FAMILY_CHAT_MESSAGES_QUERY } from "./operations.js";
import {
  attemptPushSubscribe,
  attemptPushDisable,
  fetchCurrentSubscriptionActive,
} from "./push_ux.js";
import {
  bindReconnectCallbacks,
  loadInitialMessages,
  attemptInitialSubscribe,
} from "./mount_browser_sync.js";

/**
 * Only the fields `mountBrowser` itself reads/writes -- `store` is narrowed
 * to the real (browser) store specifically, since this function only ever
 * runs on the `hasDocument` branch in `initRoom`. Every collaborator type
 * below is referenced through an inline `import(...)` (rather than a
 * top-level static import of the factory) since this module never
 * constructs any of them itself -- `family_chat.js` does -- and a plain
 * type-only reference to a statically imported name is invisible to
 * oxlint's own (comment-blind) `no-unused-vars` check.
 * @typedef {object} MountableRoom
 * @property {string} roomSlug
 * @property {string} userId
 * @property {ReturnType<typeof import("./outbox.js").createOutbox>} outbox
 * @property {ReturnType<typeof import("./real_store.js").createRealStore>} store
 * @property {ReturnType<typeof import("./push.js").createPush>} push
 * @property {ReturnType<typeof import("./reconnect.js").createReconnect>} reconnect
 * @property {{remediationMessage: string | null}} composer
 */

/** @typedef {ReturnType<typeof import("./graphql.js").createSubscriptionClient>} SubscriptionClient */

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wirePushControls(room, elements) {
  function renderPushControl() {
    const text = room.push.controlText();
    elements.pushControl.textContent = text;
    elements.pushControl.disabled = text !== CONTROL_TEXT.OFF;
    elements.pushDisable.hidden = text !== CONTROL_TEXT.ON;
  }

  elements.pushControl.addEventListener("click", () => {
    // Informational states never re-prompt.
    if (room.push.controlText() !== CONTROL_TEXT.OFF) return;
    void attemptPushSubscribe().then((enabled) => {
      if (enabled) room.push.enable();
      renderPushControl();
    });
  });

  elements.pushDisable.addEventListener("click", () => {
    void room.push.select("Turn off").then(() => {
      renderPushControl();
      void attemptPushDisable();
    });
  });

  renderPushControl();
  void fetchCurrentSubscriptionActive().then((active) => {
    if (active) {
      room.push.enable();
      renderPushControl();
    }
  });
}

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireOnlineOfflineBanner(room, elements) {
  window.addEventListener("online", () => {
    elements.offlineBanner.hidden = true;
    room.outbox.reportBrowserEvent("online");
  });
  window.addEventListener("offline", () => {
    elements.offlineBanner.hidden = false;
  });
  if (typeof navigator !== "undefined" && navigator.onLine === false) {
    elements.offlineBanner.hidden = false;
  }
}

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
      if (committedMessage)
        room.store.reconcile(
          clientMessageId,
          /** @type {import("./real_store.js").RenderableMessage} */
          (committedMessage),
        );
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
  const body = elements.input.value.trim();
  elements.remediation.hidden = true;
  if (!body) {
    elements.remediation.hidden = false;
    elements.remediation.textContent = "Write a message first.";
    return;
  }
  if (body.length > 4_000) {
    elements.remediation.hidden = false;
    elements.remediation.textContent = "Keep messages under 4,000 characters.";
    return;
  }

  const clientMessageId = await room.outbox.send(body);
  if (clientMessageId === null) {
    elements.remediation.hidden = false;
    elements.remediation.textContent =
      room.composer.remediationMessage ?? "Couldn't queue this message.";
    return;
  }

  elements.input.value = "";
  room.store.renderPending({
    clientMessageId,
    body,
    status: room.outbox.status(clientMessageId),
    senderKind: "user",
    senderDisplayName: "You",
  });
  watchPendingMessage(room, elements, clientMessageId);
}

/** @param {MountableRoom} room */
async function loadOlderHistory(room) {
  const oldestId = room.store.oldestId();
  const result = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
    roomSlug: room.roomSlug,
    beforeId: oldestId,
    limit: 50,
  });
  const nodes = result.data?.familyChatMessages?.nodes ?? [];
  room.store.prependOlder(nodes, result.data?.familyChatMessages?.hasOlder);
}

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireComposerAndHistory(room, elements) {
  elements.loadOlder.addEventListener("click", () => {
    void loadOlderHistory(room);
  });
  elements.composer.addEventListener("submit", (event) => {
    event.preventDefault();
    void submitComposer(room, elements);
  });
}

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {{subscriptionClient: SubscriptionClient}} context
 */
export async function mountBrowser(room, elements, { subscriptionClient }) {
  // Not the family chat route; nothing to mount.
  if (!elements.room) return;
  const roomElement = elements.room;
  roomElement.dataset["connectionState"] = "booting";

  wirePushControls(room, elements);
  wireComposerAndHistory(room, elements);
  wireOnlineOfflineBanner(room, elements);
  bindReconnectCallbacks(room, subscriptionClient);

  await loadInitialMessages(room);
  elements.input.disabled = false;
  elements.send.disabled = false;
  roomElement.dataset["connectionState"] = "ready";

  await attemptInitialSubscribe(room, roomElement, subscriptionClient);

  // A real socket reconnect (Caddy having cut over to a replacement slot, or
  // any transient drop) re-runs the full ordered promotion sequence --
  // subscribe first, catch up any gap, merge, only then resume the outbox
  // drain (tech-doc 003) -- rather than silently missing messages or racing
  // a send ahead of the gap-fill.
  subscriptionClient.onReconnect(() => {
    void promoteSlot(room.reconnect);
  });
}
