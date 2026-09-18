// Family Chat room entry point (tech-doc 005/007/008). Wires the
// DOM-independent modules under `family_chat/` to the real browser (fetch, a
// real `phoenix` socket, and the shipped `room.html.heex` DOM) when one
// exists, and to deterministic in-memory/test collaborators otherwise.
// `assets/test/behaviour/family_chat.steps.ts` (Vitest, `environment:
// "node"`) is the only caller that never has a `document`; the shipped
// `app.js` (real browser) is the only caller that always does.
//
// KNOWN GAP (see this plan's Phase 4 learnings.md): `outbox.js`'s own
// header comment describes a real IndexedDB binding "attached separately by
// `family_chat.js`" for cross-reload queue durability; no such binding is
// actually implemented anywhere in this directory (verified: no
// `indexedDB.*` call exists in `assets/js/` at all). The outbox is
// currently in-memory only (`outbox.js`'s module-scoped `namespaces` Map)
// and does not survive a real browser tab close/reopen. This is consistent
// with tech-doc 007's Release Invariants table, which marks IndexedDB
// "Active for authenticated room" only once the Experience stage (nav/route
// enabled) begins -- the room stays nav-dormant/flag-off through Phase 4 --
// but it must be closed before that flag flips, not assumed already done.

import { createOutbox, STATUS } from "./family_chat/outbox.js";
import { createReconnect, promoteSlot } from "./family_chat/reconnect.js";
import { createStore } from "./family_chat/store.js";
import {
  CONTROL_TEXT,
  createPush,
  urlBase64ToUint8Array,
} from "./family_chat/push.js";
import { createSystemClock } from "./family_chat/clock.js";
import {
  request as graphqlRequest,
  createSubscriptionClient,
} from "./family_chat/graphql.js";
import {
  FAMILY_CHAT_ROOM_QUERY,
  FAMILY_CHAT_MESSAGES_QUERY,
  SEND_FAMILY_CHAT_MESSAGE_MUTATION,
  FAMILY_CHAT_MESSAGE_COMMITTED_SUBSCRIPTION,
  WEB_PUSH_CONFIGURATION_QUERY,
  CURRENT_WEB_PUSH_SUBSCRIPTION_QUERY,
  UPSERT_WEB_PUSH_SUBSCRIPTION_MUTATION,
  DISABLE_CURRENT_WEB_PUSH_SUBSCRIPTION_MUTATION,
  NON_RETRYABLE_CODES,
} from "./family_chat/operations.js";

const CANONICAL_ROOM_SLUG = "ruang-keluarga";
const BOTTOM_THRESHOLD_PX = 80;

function parseRoomSlug(path) {
  const match = /\/family-chat\/([^/?#]+)/u.exec(path);
  return match ? match[1] : CANONICAL_ROOM_SLUG;
}

// --- transport -------------------------------------------------------------

/** Real GraphQL-backed transport: the only path a production message ever
 * takes to actually reach the server. */
function createRealTransport(roomSlug) {
  return async function realTransport({ clientMessageId, body }) {
    let response;
    try {
      response = await graphqlRequest(SEND_FAMILY_CHAT_MESSAGE_MUTATION, {
        roomSlug,
        clientMessageId,
        body,
      });
    } catch {
      return { ok: false, retryable: true };
    }

    if (response.errors?.length) {
      const code = response.errors[0]?.extensions?.code;
      if (code === "UNAUTHENTICATED") return { ok: false, authExpired: true };
      return { ok: false, retryable: !NON_RETRYABLE_CODES.has(code) };
    }

    const message = response.data?.sendFamilyChatMessage;
    return message ? { ok: true, message } : { ok: false, retryable: true };
  };
}

/**
 * FE_UNIT's default transport (tech-doc 006 Proof Matrix: the outbox's
 * queue/status-transition logic is a `@fe-vitest-unit`/`@e2e-exempt` proof,
 * deliberately without a browser or a real server -- see the feature file's
 * own exemption comments). Every scenario that needs a *specific* outcome
 * passes `simulateNetworkFailure` instead, which `outbox.js` intercepts
 * before this transport is ever called; this only has to stand in for "the
 * server accepted it" on the happy path.
 *
 * Resolves on the injected clock's timer (a real macrotask via
 * `createSystemClock`, i.e. never synchronously/via a microtask alone) so a
 * scenario's very next Gherkin step -- checked with no `await` of its own --
 * can still observe the intermediate "Sending" status `attemptSend` sets
 * before this settles, the same way a real network response never resolves
 * within the same turn as the request that triggered it.
 */
function createTestTransport(clock) {
  return function testTransport({ clientMessageId, body }) {
    return new Promise((resolve) => {
      clock.setTimer(
        () => resolve({ ok: true, message: { id: clientMessageId, body } }),
        0,
      );
    });
  };
}

// --- push permission UX (real browser only; never reached by FE_UNIT, which
// injects `devicePushState`/`activePushSubscription` directly instead) -----

/**
 * Feature-detects which of `push.js`'s five device states currently applies.
 * iOS/iPadOS Safari lacks `Notification`/`PushManager` entirely until
 * installed as a Home Screen web app (tech-doc 004, citing WebKit's "Web
 * Push for Web Apps on iOS and iPadOS"), so a non-standalone session on that
 * platform is asked to install first -- installing resolves the gap --
 * rather than told push is simply unsupported.
 */
function detectDevicePushState() {
  const supported =
    typeof Notification !== "undefined" &&
    typeof navigator !== "undefined" &&
    "serviceWorker" in navigator &&
    typeof PushManager !== "undefined";

  if (!supported) {
    const isIOSDevice = /iPad|iPhone|iPod/u.test(navigator.userAgent ?? "");
    // `navigator.standalone` is a non-standard iOS Safari extension absent
    // from the DOM lib's `Navigator` type; read it through a narrow cast
    // rather than widening the whole function to `any`.
    const iosNavigator = /** @type {{standalone?: boolean}} */ (
      /** @type {unknown} */ (navigator)
    );
    const isStandalone =
      iosNavigator.standalone === true ||
      (typeof window.matchMedia === "function" &&
        window.matchMedia("(display-mode: standalone)").matches);
    return isIOSDevice && !isStandalone
      ? "requires installation"
      : "unsupported";
  }

  if (Notification.permission === "denied") return "permission denied";
  return "available, not yet decided";
}

/** Real read of whether this authenticated session already has a binding,
 * used only to set the control's initial rendered state on room load. */
async function fetchCurrentSubscriptionActive() {
  try {
    const result = await graphqlRequest(
      CURRENT_WEB_PUSH_SUBSCRIPTION_QUERY,
      {},
    );
    return Boolean(result.data?.currentWebPushSubscription?.enabled);
  } catch {
    return false;
  }
}

/**
 * The one real subscribe attempt: reads the public VAPID key, requests
 * permission (must run inside this function's own caller, a click handler,
 * so the browser recognizes the required user gesture -- page load never
 * calls this), subscribes through the real Push API, and binds the result
 * server-side. Returns whether the session ends up genuinely enabled.
 */
async function attemptPushSubscribe() {
  const configResult = await graphqlRequest(WEB_PUSH_CONFIGURATION_QUERY, {});
  const config = configResult.data?.webPushConfiguration;
  if (!config?.available || !config.publicKey) return false;

  const permission = await Notification.requestPermission();
  if (permission !== "granted") return false;

  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(config.publicKey),
  });
  const keys = subscription.toJSON().keys ?? {};
  if (!keys["p256dh"] || !keys["auth"]) return false;

  const upsertResult = await graphqlRequest(
    UPSERT_WEB_PUSH_SUBSCRIPTION_MUTATION,
    {
      endpoint: subscription.endpoint,
      p256dh: keys["p256dh"],
      auth: keys["auth"],
    },
  );
  return Boolean(upsertResult.data?.upsertWebPushSubscription?.enabled);
}

/** The one real disable attempt: server-side first (the source of truth for
 * whether delivery continues), then a best-effort browser-side unsubscribe
 * so a stale local subscription is not left registered either. */
async function attemptPushDisable() {
  try {
    await graphqlRequest(DISABLE_CURRENT_WEB_PUSH_SUBSCRIPTION_MUTATION, {});
  } finally {
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) await subscription.unsubscribe();
    } catch {
      // Best-effort only; the server-side disable above already governs
      // whether delivery continues regardless of local cleanup success.
    }
  }
}

// --- real (browser) store: message list + scroll anchor + live region -----

function createRealStore({ roomSlug, elements }) {
  const rendered = new Map(); // clientMessageId|serverId -> <li>
  let lastAnnouncement = null;
  let newMessagesLabel = null;
  let oldestKnownId = null;
  let atBottom = true;

  function isNearBottom() {
    const history = elements.history;
    if (!history) return true;
    return (
      history.scrollHeight - history.scrollTop - history.clientHeight <=
      BOTTOM_THRESHOLD_PX
    );
  }

  function messageNode(message, { pending }) {
    const li = document.createElement("li");
    li.className = "family-chat-message";
    li.dataset.role = "family-chat-message";
    li.dataset.deliveryState = pending ? message.status : "committed";
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
      status.dataset.role = "family-chat-message-status";
      status.textContent = message.status;
      li.append(status);
    }

    return li;
  }

  function escapeHtml(value) {
    const div = document.createElement("div");
    div.textContent = value;
    return div.innerHTML;
  }

  // tech-doc 005's History copy inventory names three distinct strings:
  // "Beginning of family chat", "Load older messages", and "New messages
  // below" -- the first replaces the second, and the button stops being
  // actionable, once the server reports no earlier page (`hasOlder: false`).
  function setHasOlder(hasOlder) {
    if (!elements.loadOlder) return;
    elements.loadOlder.disabled = !hasOlder;
    elements.loadOlder.textContent = hasOlder
      ? "Load older messages"
      : "Beginning of family chat";
  }

  return {
    empty() {
      return rendered.size === 0;
    },

    renderInitial(messages, hasOlder) {
      elements.list.replaceChildren();
      rendered.clear();
      for (const message of messages) {
        const node = messageNode(message, { pending: false });
        elements.list.append(node);
        rendered.set(message.id, node);
        oldestKnownId = oldestKnownId === null ? message.id : oldestKnownId;
      }
      elements.empty.hidden = messages.length > 0;
      // An empty room has nothing earlier to load regardless of what the
      // query reported; otherwise trust the server's own `hasOlder` flag,
      // defaulting to true (safe: still offers the button) if a caller ever
      // omits it.
      setHasOlder(messages.length === 0 ? false : (hasOlder ?? true));
    },

    prependOlder(messages, hasOlder) {
      setHasOlder(Boolean(hasOlder));
      if (messages.length === 0) return;
      const anchor = elements.list.firstElementChild;
      const anchorOffset = anchor ? anchor.getBoundingClientRect().top : 0;

      const fragment = document.createDocumentFragment();
      for (const message of messages) {
        const node = messageNode(message, { pending: false });
        fragment.append(node);
        rendered.set(message.id, node);
      }
      elements.list.prepend(fragment);
      oldestKnownId = messages[0].id;

      if (anchor) {
        const newOffset = anchor.getBoundingClientRect().top;
        elements.history.scrollTop += newOffset - anchorOffset;
      }
    },

    scrollAnchorPreserved() {
      return true;
    },

    renderPending(message) {
      const node = messageNode(message, { pending: true });
      elements.list.append(node);
      rendered.set(message.clientMessageId, node);
      if (isNearBottom())
        elements.history.scrollTop = elements.history.scrollHeight;
    },

    updatePendingStatus(clientMessageId, status) {
      const node = rendered.get(clientMessageId);
      const statusNode = node?.querySelector(
        '[data-role="family-chat-message-status"]',
      );
      if (statusNode) statusNode.textContent = status;
      if (node) node.dataset.deliveryState = status;
    },

    reconcile(clientMessageId, committedMessage) {
      const pendingNode = rendered.get(clientMessageId);
      const existingCommittedNode = rendered.get(committedMessage.id);

      if (existingCommittedNode) {
        // The subscription push for this same message already rendered it
        // (a race against this send's own mutation response, since tech-doc
        // 008's subscription payload never carries the client-chosen ID) --
        // the committed row is already correct on screen, so just drop the
        // now-redundant pending row instead of creating a second copy of it.
        if (pendingNode && pendingNode !== existingCommittedNode)
          pendingNode.remove();
        rendered.delete(clientMessageId);
        return;
      }

      const node = messageNode(committedMessage, { pending: false });
      if (pendingNode) {
        pendingNode.replaceWith(node);
      } else {
        elements.list.append(node);
      }
      rendered.delete(clientMessageId);
      rendered.set(committedMessage.id, node);
    },

    async receiveRemoteMessage(message) {
      if (rendered.has(message.id)) return; // already reconciled from our own send
      const wasNearBottom = isNearBottom();
      const node = messageNode(message, { pending: false });
      elements.list.append(node);
      rendered.set(message.id, node);

      if (wasNearBottom) {
        atBottom = true;
        newMessagesLabel = null;
        elements.newMessages.hidden = true;
        elements.history.scrollTop = elements.history.scrollHeight;
      } else {
        atBottom = false;
        newMessagesLabel = "New messages below";
        elements.newMessages.hidden = false;
      }

      const senderLabel =
        message.senderKind === "system" ? "System" : message.senderDisplayName;
      lastAnnouncement = `New message from ${senderLabel}: ${message.body}`;
      elements.liveRegion.textContent = lastAnnouncement;
    },

    lastLiveRegionAnnouncement() {
      return lastAnnouncement;
    },

    focusMovedFromComposer() {
      return false;
    },

    newMessagesIndicatorLabel() {
      return newMessagesLabel;
    },

    isAtBottom() {
      return atBottom;
    },

    oldestId() {
      return oldestKnownId;
    },

    hasRendered(id) {
      return rendered.has(id);
    },
  };
}

// --- room assembly -----------------------------------------------------

/**
 * @param {string} path e.g. "/family-chat/ruang-keluarga"
 * @param {{user?: {id: string}, clock?: import("./family_chat/clock.js").Clock, viewport?: string, devicePushState?: string, activePushSubscription?: boolean}} options
 */
export async function initRoom(path, options = {}) {
  const roomSlug = parseRoomSlug(path);
  const hasDocument = typeof document !== "undefined";
  const userId = options.user?.id ?? "anonymous";
  const clock = options.clock ?? createSystemClock();

  const composerState = { remediationMessage: null };
  const elements = hasDocument ? findElements() : null;

  const transport = hasDocument
    ? createRealTransport(roomSlug)
    : createTestTransport(clock);

  const push = createPush({
    devicePushState: hasDocument
      ? detectDevicePushState()
      : options.devicePushState,
    activePushSubscription: options.activePushSubscription,
    onDisable: () => {},
  });

  const outbox = createOutbox({
    userId,
    roomSlug,
    clock,
    transport,
    onQueueFull: () => {
      composerState.remediationMessage =
        "Keep waiting messages under 100, or retry/discard one first.";
      if (elements) {
        elements.remediation.hidden = false;
        elements.remediation.textContent = composerState.remediationMessage;
      }
    },
    onLogout: () => {
      push.disable();
    },
    onAuthExpired: () => {
      if (elements) elements.room.dataset.connectionState = "auth-expired";
    },
  });

  const store = hasDocument
    ? createRealStore({ roomSlug, elements })
    : createStore({
        scrolledToOlderMessage: options.scrolledToOlderMessage,
        focusInComposer: options.focusInComposer,
      });

  const subscriptionClient = hasDocument ? createSubscriptionClient() : null;
  const reconnect = createReconnect({
    clock,
    socketClient: subscriptionClient,
    store,
    roomSlug,
  });
  // `accessibility.js` reads the shipped template/stylesheet from disk via
  // `node:fs` -- meaningful only for FE_UNIT's Vitest (Node) process, never
  // for a real browser (no such module exists there, and no browser code
  // path ever calls it -- see `family_chat.steps.ts`, its only caller).
  // Dynamically importing it only on this branch (never reached with a real
  // `document`) keeps that Node-only dependency out of the browser bundle
  // entirely, rather than a top-level import that esbuild would otherwise
  // have to resolve for every page.
  const accessibility = hasDocument
    ? undefined
    : (await import("./family_chat/accessibility.js")).createAccessibility({
        viewport: options.viewport,
      });

  const room = {
    roomSlug,
    userId,
    outbox,
    store,
    push,
    reconnect,
    accessibility,
    composer: composerState,
  };

  if (hasDocument && elements) {
    await mountBrowser(room, elements, { roomSlug, subscriptionClient });
  }

  return room;
}

function findElements() {
  return {
    room: document.querySelector('[data-role="family-chat-room"]'),
    offlineBanner: document.querySelector(
      '[data-role="family-chat-offline-banner"]',
    ),
    history: document.querySelector('[data-role="family-chat-history"]'),
    loadOlder: document.querySelector('[data-role="family-chat-load-older"]'),
    empty: document.querySelector('[data-role="family-chat-empty"]'),
    list: document.querySelector('[data-role="family-chat-message-list"]'),
    newMessages: document.querySelector(
      '[data-role="family-chat-new-messages"]',
    ),
    liveRegion: document.querySelector('[data-role="family-chat-live-region"]'),
    composer: document.querySelector('[data-role="family-chat-composer"]'),
    input: document.querySelector('[data-role="family-chat-message-input"]'),
    send: document.querySelector('[data-role="family-chat-send"]'),
    remediation: document.querySelector(
      '[data-role="family-chat-remediation"]',
    ),
    outboxStatus: document.querySelector(
      '[data-role="family-chat-outbox-status"]',
    ),
    pushControl: document.querySelector(
      '[data-role="family-chat-push-control"]',
    ),
    pushDisable: document.querySelector(
      '[data-role="family-chat-push-disable"]',
    ),
  };
}

async function mountBrowser(room, elements, { roomSlug, subscriptionClient }) {
  if (!elements.room) return; // not the family chat route; nothing to mount

  elements.room.dataset.connectionState = "booting";

  function renderPushControl() {
    const text = room.push.controlText();
    elements.pushControl.textContent = text;
    elements.pushControl.disabled = text !== CONTROL_TEXT.OFF;
    elements.pushDisable.hidden = text !== CONTROL_TEXT.ON;
  }

  elements.pushControl.addEventListener("click", () => {
    if (room.push.controlText() !== CONTROL_TEXT.OFF) return; // informational states never re-prompt
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

  elements.loadOlder.addEventListener("click", () => loadOlder());
  elements.composer.addEventListener("submit", (event) => {
    event.preventDefault();
    void submitComposer();
  });
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

  async function submitComposer() {
    const body = elements.input.value.trim();
    elements.remediation.hidden = true;
    if (!body) {
      elements.remediation.hidden = false;
      elements.remediation.textContent = "Write a message first.";
      return;
    }
    if (body.length > 4_000) {
      elements.remediation.hidden = false;
      elements.remediation.textContent =
        "Keep messages under 4,000 characters.";
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
    watchPending(clientMessageId);
  }

  function watchPending(clientMessageId) {
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
        if (committedMessage)
          room.store.reconcile(clientMessageId, committedMessage);
        unsubscribe();
      } else if (status === STATUS.FAILED) {
        unsubscribe();
      }
    });
  }

  async function loadOlder() {
    const oldestId = room.store.oldestId();
    const result = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
      roomSlug,
      beforeId: oldestId,
      limit: 50,
    });
    const nodes = result.data?.familyChatMessages?.nodes ?? [];
    room.store.prependOlder(nodes, result.data?.familyChatMessages?.hasOlder);
  }

  function handleSubscriptionData(result) {
    const message = result?.data?.familyChatMessageCommitted;
    if (!message) return;
    room.reconnect.setHighestCommittedId(message.id);

    // `watchPending`'s `onChange` listener is the sole authoritative
    // reconciliation point for our *own* sends (keyed by this send's own
    // mutation response -- tech-doc 008's subscription payload never
    // carries the client-chosen ID, so it cannot be matched here). This
    // handler only ever renders a genuinely new arrival; `hasRendered` also
    // absorbs the rare race where this push beats our own mutation response
    // (see `reconcile`'s matching guard in `createRealStore` for that race).
    if (room.store.hasRendered(message.id)) return;
    void room.store.receiveRemoteMessage(message);
  }

  async function subscribeToRoom() {
    await subscriptionClient.subscribe(
      FAMILY_CHAT_MESSAGE_COMMITTED_SUBSCRIPTION,
      { roomSlug },
      handleSubscriptionData,
    );
  }

  /** Real gap-fill query for `reconnect.js`'s catch-up step: every message
   * committed after the last one this room saw. */
  async function fetchMissedMessages(afterId) {
    const result = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
      roomSlug,
      afterId: afterId ?? undefined,
      limit: 200,
    });
    return result.data?.familyChatMessages?.nodes ?? [];
  }

  /** Real merge-by-server-ID step: dedupes against whatever is already
   * rendered (including anything the live subscription already delivered
   * while the catch-up query was in flight) before appending the rest. */
  function mergeMissedMessages(messages) {
    for (const message of messages) {
      room.reconnect.setHighestCommittedId(message.id);
      if (!room.store.hasRendered(message.id))
        void room.store.receiveRemoteMessage(message);
    }
  }

  room.reconnect._bindBrowserCallbacks({
    resubscribe: subscribeToRoom,
    fetchMissed: fetchMissedMessages,
    mergeMessages: mergeMissedMessages,
    // Pausing/resuming the outbox's own drain (not just reconnect's internal
    // flag) is what actually stops a send from racing ahead of the catch-up
    // gap-fill (tech-doc 003).
    onPause: () => room.outbox.pauseDrain(),
    onResume: () => room.outbox.resumeDrain(),
  });

  // Initial load: room identity (canonical route already resolved server
  // side; this only needs the message page) then latest messages.
  const initial = await graphqlRequest(FAMILY_CHAT_MESSAGES_QUERY, {
    roomSlug,
    limit: 50,
  });
  const nodes = initial.data?.familyChatMessages?.nodes ?? [];
  room.store.renderInitial(nodes, initial.data?.familyChatMessages?.hasOlder);
  if (nodes.length > 0)
    room.reconnect.setHighestCommittedId(nodes[nodes.length - 1].id);

  elements.input.disabled = false;
  elements.send.disabled = false;
  elements.room.dataset.connectionState = "ready";

  try {
    await subscribeToRoom();
  } catch {
    // Subscription join failure never blocks the already-loaded room; the
    // browser still functions for read/send, just without live push until a
    // future reconnect attempt succeeds.
    elements.room.dataset.connectionState = "ready";
  }

  // A real socket reconnect (Caddy having cut over to a replacement slot, or
  // any transient drop) re-runs the full ordered promotion sequence --
  // subscribe first, catch up any gap, merge, only then resume the outbox
  // drain (tech-doc 003) -- rather than silently missing messages or racing
  // a send ahead of the gap-fill.
  subscriptionClient.onReconnect(() => {
    void promoteSlot(room.reconnect);
  });
}
