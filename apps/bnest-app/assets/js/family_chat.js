// Family Chat room entry point (tech-doc 005/007/008). Wires the
// DOM-independent modules under `family_chat/` to the real browser (fetch, a
// real `phoenix` socket, and the shipped `room.html.heex` DOM) when one
// exists, and to deterministic in-memory/test collaborators otherwise.
// `assets/test/behaviour/family_chat.steps.ts` (Vitest, `environment:
// "node"`) is the only caller that never has a `document`; the shipped
// `app.js` (real browser) is the only caller that always does.
//
// Split into several `family_chat/*.js` modules purely to stay under this
// project's max-lines/max-lines-per-function lint budget -- `initRoom`
// below is the only export other files need to know about.
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

import { createOutbox } from "./family_chat/outbox.js";
import { createReconnect } from "./family_chat/reconnect.js";
import { createStore } from "./family_chat/store.js";
import { createPush } from "./family_chat/push.js";
import { createSystemClock } from "./family_chat/clock.js";
import { createSubscriptionClient } from "./family_chat/graphql.js";
import {
  createRealTransport,
  createTestTransport,
} from "./family_chat/transport.js";
import { detectDevicePushState } from "./family_chat/push_ux.js";
import { findElements } from "./family_chat/elements.js";
import { createRealStore } from "./family_chat/real_store.js";
import { mountBrowser } from "./family_chat/mount_browser.js";

const CANONICAL_ROOM_SLUG = "ruang-keluarga";

/** @param {string} path @returns {string} */
function parseRoomSlug(path) {
  const match = /\/family-chat\/([^/?#]+)/u.exec(path);
  return match?.[1] ?? CANONICAL_ROOM_SLUG;
}

/**
 * @param {string} roomSlug
 * @param {boolean} hasDocument
 * @param {import("./family_chat/elements.js").FamilyChatElements | null} elements
 * @param {{user?: {id: string}, activePushSubscription?: boolean, devicePushState?: string}} options
 * @param {import("./family_chat/clock.js").Clock} clock
 * @param {{remediationMessage: string | null}} composerState
 */
function createRoomPushAndOutbox(
  roomSlug,
  hasDocument,
  elements,
  options,
  clock,
  composerState,
) {
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
    userId: options.user?.id ?? "anonymous",
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
      if (elements?.room)
        elements.room.dataset["connectionState"] = "auth-expired";
    },
  });

  return { push, outbox };
}

/**
 * @param {string} roomSlug
 * @param {boolean} hasDocument
 * @param {import("./family_chat/elements.js").FamilyChatElements | null} elements
 * @param {{user?: {id: string}, scrolledToOlderMessage?: boolean, focusInComposer?: boolean}} options
 * @param {import("./family_chat/clock.js").Clock} clock
 */
function createRoomStoreAndReconnect(
  roomSlug,
  hasDocument,
  elements,
  options,
  clock,
) {
  // `hasDocument` and `elements` are always both-true or both-false together
  // (`elements` is set from `findElements()` exactly when `hasDocument`
  // is), but TS tracks them as two independent variables; the `elements`
  // check alone is what narrows the branch below, `hasDocument` is kept for
  // readability at the call site.
  const store =
    hasDocument && elements
      ? createRealStore({
          roomSlug,
          elements,
          currentUserId: options.user?.id ?? null,
        })
      : createStore({
          scrolledToOlderMessage: options.scrolledToOlderMessage,
          focusInComposer: options.focusInComposer,
        });

  const subscriptionClient = hasDocument ? createSubscriptionClient() : null;
  // `store`/`roomSlug` are deliberately not passed here: `createReconnect`
  // (see `family_chat/reconnect.js`) only ever reads `clock`/`socketClient`
  // from its options; the real store/room wiring happens later, through
  // `bindBrowserCallbacks` in `mount_browser.js`.
  const reconnect = createReconnect({
    clock,
    socketClient: subscriptionClient,
  });

  return { store, subscriptionClient, reconnect };
}

/**
 * `accessibility.js` reads the shipped template/stylesheet from disk via
 * `node:fs` -- meaningful only for FE_UNIT's Vitest (Node) process, never
 * for a real browser (no such module exists there, and no browser code path
 * ever calls it -- see `family_chat.steps.ts`, its only caller).
 * Dynamically importing it only on this branch (never reached with a real
 * `document`) keeps that Node-only dependency out of the browser bundle
 * entirely, rather than a top-level import that esbuild would otherwise
 * have to resolve for every page.
 * @param {boolean} hasDocument
 * @param {{viewport?: string}} options
 */
async function createRoomAccessibility(hasDocument, options) {
  if (hasDocument) return;
  const { createAccessibility } =
    await import("./family_chat/accessibility.js");
  return createAccessibility({ viewport: options.viewport });
}

/**
 * The one call site that needs both the constructed `room` and its DOM
 * `elements` together, isolated purely so `initRoom` itself stays under this
 * project's max-lines-per-function lint budget.
 * `store`/`subscriptionClient` are guaranteed the real (non-null, browser)
 * variants whenever this runs -- both were assigned from the same
 * `hasDocument`-gated ternaries in `initRoom` -- but TS tracks each of those
 * independently, so the casts below just assert what that construction
 * already guarantees.
 * @param {object} room
 * @param {import("./family_chat/elements.js").FamilyChatElements} elements
 * @param {ReturnType<typeof createSubscriptionClient> | null} subscriptionClient
 */
async function mountRoomInBrowser(room, elements, subscriptionClient) {
  await mountBrowser(
    /** @type {import("./family_chat/mount_browser.js").MountableRoom} */
    (room),
    elements,
    {
      subscriptionClient:
        /** @type {ReturnType<typeof createSubscriptionClient>} */
        (subscriptionClient),
    },
  );
}

/**
 * @param {string} path e.g. "/family-chat/ruang-keluarga"
 * @param {{
 *   user?: {id: string},
 *   clock?: import("./family_chat/clock.js").Clock,
 *   viewport?: string,
 *   devicePushState?: string,
 *   activePushSubscription?: boolean,
 *   scrolledToOlderMessage?: boolean,
 *   focusInComposer?: boolean,
 * }} options
 */
export async function initRoom(path, options = {}) {
  const roomSlug = parseRoomSlug(path);
  const hasDocument = typeof document !== "undefined";
  const clock = options.clock ?? createSystemClock();

  /** @type {{remediationMessage: string | null}} */
  const composerState = { remediationMessage: null };
  const elements = hasDocument ? findElements() : null;

  const { push, outbox } = createRoomPushAndOutbox(
    roomSlug,
    hasDocument,
    elements,
    options,
    clock,
    composerState,
  );
  const { store, subscriptionClient, reconnect } = createRoomStoreAndReconnect(
    roomSlug,
    hasDocument,
    elements,
    options,
    clock,
  );
  const accessibility = await createRoomAccessibility(hasDocument, options);

  const room = {
    roomSlug,
    userId: options.user?.id ?? "anonymous",
    outbox,
    store,
    push,
    reconnect,
    accessibility,
    composer: composerState,
  };

  if (hasDocument && elements) {
    await mountRoomInBrowser(room, elements, subscriptionClient);
  }

  return room;
}

/**
 * The real `app.js` entry point: detects the shipped `room.html.heex`
 * template's DOM shell and, when present, boots `initRoom` with the
 * authenticated visitor's own ID read from that same shell's
 * `data-current-user-id` attribute -- the only way the real browser build
 * (as opposed to the Vitest+Gherkin harness, which passes `options.user`
 * directly) ever learns which sender is "own" for `real_store.js`'s
 * left/right message split.
 */
export async function initRoomFromDocument() {
  const familyChatRoom =
    /** @type {HTMLElement | null} */
    (document.querySelector('[data-role="family-chat-room"]'));
  if (!familyChatRoom) return;

  const currentUserId = familyChatRoom.dataset["currentUserId"];
  await initRoom(
    window.location.pathname,
    currentUserId ? { user: { id: currentUserId } } : {},
  );
}
