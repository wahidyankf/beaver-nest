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
// Real IndexedDB binding (tech-doc 003's promised cross-reload queue
// durability, and tech-doc 007's Release Invariants table, which marks
// IndexedDB "Active for authenticated room" once the Experience stage
// begins): `createRoomPushAndOutbox` below is the "attached separately by
// `family_chat.js`" seam `outbox.js`'s own header comment describes --
// see `persistence_indexeddb.js` for the real implementation, only ever
// constructed on this file's `hasDocument` branch (Phase 9 fix; see
// learnings.md for the reproduction/root-cause evidence of the gap this
// closed).

import { createComposer } from "./family_chat/composer.js";
import { createHistory } from "./family_chat/history.js";
import { createReadMarker } from "./family_chat/read_marker.js";
import { createReplyTarget } from "./family_chat/reply_target.js";
import { createSystemClock } from "./family_chat/clock.js";
import { findElements } from "./family_chat/elements.js";
import { mountBrowser } from "./family_chat/mount_browser.js";
import {
  createRoomAccessibility,
  createRoomPushAndOutbox,
  createRoomStoreAndReconnect,
  resolvePageSource,
} from "./family_chat/room_parts.js";

/** @typedef {ReturnType<typeof import("./family_chat/graphql.js").createSubscriptionClient>} SubscriptionClient */
/** @typedef {ReturnType<typeof import("./family_chat/page_source.js").createTestPageSource>} TestPageSource */

/**
 * @typedef {{
 *   user?: {id: string},
 *   clock?: import("./family_chat/clock.js").Clock,
 *   viewport?: string,
 *   devicePushState?: string,
 *   activePushSubscription?: boolean,
 *   scrolledToOlderMessage?: boolean,
 *   focusInComposer?: boolean,
 *   persistence?: import("./family_chat/outbox_send.js").Persistence | undefined,
 *   readStorage?: import("./family_chat/read_marker.js").ReadMarkerStorage | undefined,
 *   pageSource?: TestPageSource | undefined,
 *   messages?: import("./family_chat/real_store.js").RenderableMessage[] | undefined,
 *   replies?: boolean,
 * }} RoomOptions
 */

const CANONICAL_ROOM_SLUG = "ruang-keluarga";

/** @param {string} path @returns {string} */
function parseRoomSlug(path) {
  const match = /\/family-chat\/([^/?#]+)/u.exec(path);
  return match?.[1] ?? CANONICAL_ROOM_SLUG;
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
 * @param {SubscriptionClient | null} subscriptionClient
 */
async function mountRoomInBrowser(room, elements, subscriptionClient) {
  await mountBrowser(
    /** @type {import("./family_chat/mount_browser.js").MountableRoom} */
    (room),
    elements,
    {
      subscriptionClient:
        /** @type {SubscriptionClient} */
        (subscriptionClient),
    },
  );
}

/**
 * Where this member resumes reading, and what they type into: the stored read
 * position, the page source `history` walks around it, and the composer that
 * sends into the same outbox. Isolated purely so `initRoom` stays under this
 * project's max-lines-per-function lint budget.
 * @param {{
 *   roomSlug: string,
 *   userId: string,
 *   hasDocument: boolean,
 *   store: Parameters<typeof createHistory>[0]["store"] & {
 *     renderPending: (
 *       message: import("./family_chat/real_store.js").RenderableMessage,
 *     ) => void,
 *   },
 *   outbox: Parameters<typeof createComposer>[0]["outbox"] & {
 *     status: (clientMessageId: string) => string,
 *   },
 *   composerState: {remediationMessage: string | null},
 * }} context
 * @param {RoomOptions} options
 */
/**
 * @param {import("./family_chat/elements.js").FamilyChatElements | null} elements
 * @returns {(message: string) => void}
 */
function createAnnouncer(elements) {
  if (!elements) return () => {};
  return (message) => {
    elements.liveRegion.textContent = message;
  };
}

function createRoomResume(context, options) {
  const {
    roomSlug,
    userId,
    hasDocument,
    store,
    outbox,
    composerState,
    announce,
  } = context;
  const readMarker = createReadMarker({
    userId,
    roomSlug,
    storage: options.readStorage,
  });
  const pageSource = resolvePageSource(roomSlug, hasDocument, options);
  const history = createHistory({
    fetchPage: pageSource.fetchPage,
    store,
    readMarker,
  });
  // One reply target per room, shared by the composer that sends it and (from
  // Phase 5) the action menu that sets it. Deliberately not part of the
  // composer's own draft state: a refused send keeps both, but they are
  // cleared by different things.
  const replyTarget = createReplyTarget({ announce });
  const composer = createComposer({
    outbox,
    state: composerState,
    focused: options.focusInComposer ?? false,
    replyTarget,
    onQueued: (message) =>
      store.renderPending({
        ...message,
        status: outbox.status(message.clientMessageId),
      }),
  });
  return { readMarker, pageSource, history, composer, replyTarget };
}

/**
 * @param {object} parts everything `initRoom` built for this room
 * @param {object} resume the resume/composer surface `createRoomResume` returns
 * @param {RoomOptions} options
 */
function assembleRoom(parts, resume, options) {
  return {
    ...parts,
    // Gates the requested GraphQL fields, and (from Phase 5) the action menu
    // and the composer strip, together -- so the browser never asks for a
    // field it will not render, or renders a quote it did not ask for.
    replies: options.replies ?? false,
    ...resume,
  };
}

/**
 * @param {string} path e.g. "/family-chat/ruang-keluarga"
 * @param {RoomOptions} options
 */
export async function initRoom(path, options = {}) {
  const roomSlug = parseRoomSlug(path);
  const hasDocument = typeof document !== "undefined";
  const clock = options.clock ?? createSystemClock();

  /** @type {{remediationMessage: string | null}} */
  const composerState = { remediationMessage: null };
  const elements = hasDocument ? findElements() : null;

  const { push, outbox } = await createRoomPushAndOutbox(
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

  const userId = options.user?.id ?? "anonymous";
  // The room's one live region (`role="status"`), which every deliberate
  // one-off announcement goes through -- selecting a reply target, a copy,
  // a refused jump. Outside a document there is nothing to announce to.
  const announce = createAnnouncer(elements);
  const resume = createRoomResume(
    { roomSlug, userId, hasDocument, store, outbox, composerState, announce },
    options,
  );
  const room = assembleRoom(
    { roomSlug, userId, clock, outbox, store, push, reconnect, accessibility },
    resume,
    options,
  );

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
