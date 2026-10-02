// Family Chat room entry point (tech-doc 005/007/008). Wires the modules
// under `family_chat/` to the shipped `room.html.heex` DOM and to the real
// browser's collaborators: GraphQL over `fetch`, a real `phoenix` socket,
// IndexedDB for the outbox, `localStorage` for the read position, and the
// system clock.
//
// Each of those collaborators is a parameter with the real browser one as
// its default, so a caller can hand the room a different one without the
// room knowing: `assets/test/behaviour/` opens this same entry point under
// happy-dom with an in-process server, socket, storage, and clock. The room
// itself has no test branch.
//
// Split into several `family_chat/*.js` modules purely to stay under this
// project's max-lines/max-lines-per-function lint budget -- `initRoom`
// below is the only export other files need to know about.

import { createComposer } from "./family_chat/composer.js";
import { createHistory } from "./family_chat/history.js";
import { createReadMarker } from "./family_chat/read_marker.js";
import { createReplyTarget } from "./family_chat/reply_target.js";
import { createSystemClock } from "./family_chat/clock.js";
import { findElements } from "./family_chat/elements.js";
import { mountBrowser } from "./family_chat/mount_browser.js";
import { request as graphqlRequest } from "./family_chat/graphql.js";
import { createRealPageSource } from "./family_chat/page_source.js";
import {
  createRoomPushAndOutbox,
  createRoomStoreAndReconnect,
} from "./family_chat/room_parts.js";

/** @typedef {import("./family_chat/graphql.js").GraphqlRequest} GraphqlRequest */
/** @typedef {import("./family_chat/graphql.js").ConnectSocket} ConnectSocket */

/**
 * The collaborators a room reaches the outside world through. Every one
 * defaults to the real browser's.
 * @typedef {{
 *   clock?: import("./family_chat/clock.js").Clock,
 *   persistence?: import("./family_chat/outbox_send.js").Persistence | undefined,
 *   readStorage?: import("./family_chat/read_marker.js").ReadMarkerStorage | undefined,
 *   request?: GraphqlRequest,
 *   connectSocket?: ConnectSocket,
 * }} RoomCollaborators
 */

/**
 * @typedef {RoomCollaborators & {
 *   user?: {id: string},
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
 * The room's one live region (`role="status"`), as a function: every
 * deliberate one-off announcement goes through it.
 * @param {import("./family_chat/elements.js").FamilyChatElements} elements
 * @returns {(message: string) => void}
 */
function createAnnouncer(elements) {
  return (message) => {
    elements.liveRegion.textContent = message;
  };
}

/**
 * Where this member resumes reading, and what they type into: the stored read
 * position, the page source `history` walks around it, and the composer that
 * sends into the same outbox. Isolated purely so `initRoom` stays under this
 * project's max-lines-per-function lint budget.
 * @param {{
 *   roomSlug: string,
 *   userId: string,
 *   request: GraphqlRequest,
 *   store: Parameters<typeof createHistory>[0]["store"] & {
 *     renderPending: (
 *       message: import("./family_chat/real_store.js").RenderableMessage,
 *     ) => void,
 *   },
 *   outbox: Parameters<typeof createComposer>[0]["outbox"] & {
 *     status: (clientMessageId: string) => string,
 *   },
 *   composerState: {remediationMessage: string | null},
 *   announce: (message: string) => void,
 * }} context
 * @param {RoomOptions} options
 */
function createRoomResume(context, options) {
  const { roomSlug, userId, request, store, outbox, composerState, announce } =
    context;
  const readMarker = createReadMarker({
    userId,
    roomSlug,
    storage: options.readStorage,
  });
  const pageSource = createRealPageSource(roomSlug, {
    replies: options.replies ?? false,
    request,
  });
  const history = createHistory({
    fetchPage: pageSource.fetchPage,
    store,
    readMarker,
  });
  // One reply target per room, shared by the composer that sends it and the
  // action menu that sets it. Deliberately not part of the composer's own
  // draft state: a refused send keeps both, but they are cleared by
  // different things.
  const replyTarget = createReplyTarget({ announce });
  const composer = createComposer({
    outbox,
    state: composerState,
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
 * @param {string} path e.g. "/family-chat/ruang-keluarga"
 * @param {RoomOptions} options
 */
export async function initRoom(path, options = {}) {
  const elements = findElements();
  // Not the family chat route; nothing to build.
  if (!elements.room) return null;

  const roomSlug = parseRoomSlug(path);
  const clock = options.clock ?? createSystemClock();
  const request = options.request ?? graphqlRequest;
  const userId = options.user?.id ?? "anonymous";

  /** @type {{remediationMessage: string | null}} */
  const composerState = { remediationMessage: null };

  const { push, outbox } = await createRoomPushAndOutbox(
    roomSlug,
    elements,
    { ...options, request },
    clock,
    composerState,
  );
  const { store, subscriptionClient, reconnect } = createRoomStoreAndReconnect(
    roomSlug,
    elements,
    options,
  );

  const announce = createAnnouncer(elements);
  const resume = createRoomResume(
    { roomSlug, userId, request, store, outbox, composerState, announce },
    options,
  );
  const room = {
    roomSlug,
    userId,
    clock,
    request,
    outbox,
    store,
    push,
    reconnect,
    // Gates the requested GraphQL fields, the action menu, and the composer
    // strip together -- so the browser never asks for a field it will not
    // render, or renders a quote it did not ask for.
    replies: options.replies ?? false,
    ...resume,
  };

  await mountBrowser(room, elements, { subscriptionClient });
  return room;
}

/**
 * The real `app.js` entry point: detects the shipped `room.html.heex`
 * template's DOM shell and, when present, boots `initRoom` with the
 * authenticated visitor's own ID and the reply flag read from that same
 * shell -- the only way the browser ever learns which sender is "own" for
 * `real_store.js`'s left/right message split.
 * @param {RoomCollaborators} [collaborators] the real browser's by default.
 */
export function initRoomFromDocument(collaborators = {}) {
  const familyChatRoom =
    /** @type {HTMLElement | null} */
    (document.querySelector('[data-role="family-chat-room"]'));
  if (!familyChatRoom) return Promise.resolve(null);

  const currentUserId = familyChatRoom.dataset["currentUserId"];
  const replies = familyChatRoom.dataset["familyChatReplyEnabled"] === "true";
  return initRoom(window.location.pathname, {
    ...collaborators,
    replies,
    ...(currentUserId ? { user: { id: currentUserId } } : {}),
  });
}
