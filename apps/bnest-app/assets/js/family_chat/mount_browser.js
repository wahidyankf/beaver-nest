// Wires a mounted room's DOM/outbox/store/reconnect collaborators to the
// real browser -- split out of `family_chat.js`, and split further into
// several small functions, purely to stay under this project's
// max-lines/max-lines-per-function lint budget. `mountBrowser` below is the
// only export `family_chat.js` needs to know about.

import { CONTROL_TEXT } from "./push.js";
import { promoteSlot, resumeFromBackground } from "./reconnect.js";
import { isNearBottom } from "./message_render.js";
import {
  renderResumedPendingMessages,
  wireComposer,
} from "./mount_browser_composer.js";
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
import { wireMessageActions, wireReplyStrip } from "./mount_browser_actions.js";

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
 * @property {ReturnType<typeof import("./history.js").createHistory>} history
 * @property {ReturnType<typeof import("./composer.js").createComposer>} composer
 * @property {boolean} [replies]
 * @property {ReturnType<typeof import("./reply_target.js").createReplyTarget>} [replyTarget]
 * @property {import("./clock.js").Clock} clock
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
 * Reaching the end of the rendered window is what advances this member's
 * stored read position -- and, while the window deliberately stops short of
 * the newest committed message, what loads the next page instead. Guarded so
 * an ordinary scroll gesture (which fires this many times per second) does
 * no repeated work once the same newest message has already been recorded.
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireReadPosition(room, elements) {
  /** @type {string | null} */
  let recordedNewestId = null;
  elements.history.addEventListener(
    "scroll",
    () => {
      if (!isNearBottom(elements)) return;
      const newestId = room.store.newestId();
      if (newestId === recordedNewestId && !room.store.hasNewer()) return;
      recordedNewestId = newestId;
      void room.history.reportScrolledToBottom();
    },
    { passive: true },
  );
}

/**
 * @param {MountableRoom} room
 * @param {import("./elements.js").FamilyChatElements} elements
 */
function wireComposerAndHistory(room, elements) {
  elements.loadOlder.addEventListener("click", () => {
    void room.history.loadOlder();
  });
  // The indicator doubles as the way back to the newest message, whether it
  // is showing because an arrival landed off-screen or because the resumed
  // window stops short of the newest page.
  elements.newMessages.addEventListener("click", () => {
    void room.history.jumpToLatest();
  });
  wireComposer(room, elements);
  wireReadPosition(room, elements);
  // Gated together with the requested GraphQL fields: with the flag off the
  // room is exactly the shipped one -- no menu, no strip, and nothing bound
  // that could open either.
  if (room.replies) {
    wireMessageActions(room, elements, room.clock);
    wireReplyStrip(room, elements);
  }
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
  renderResumedPendingMessages(room, elements);
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

  // A backgrounded mobile PWA routinely freezes JS timers and silently
  // kills the socket without a clean close event, so waiting on phoenix's
  // own passive reconnect can leave the room stale well after the tab is
  // foregrounded again; check and force a fresh connection immediately
  // instead. The forced connection's own `onOpen` still runs the ordered
  // catch-up sequence above -- this only ever decides *whether* to force it.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      resumeFromBackground(subscriptionClient);
    }
  });
}
