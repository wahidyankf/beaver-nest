// The collaborators a Family Chat room is built from: the outbox and its
// transport and persistence, the push control, the message store, and the
// subscription client reconnect drives. Split out of `family_chat.js`
// purely to stay under this project's max-lines lint budget;
// `family_chat.js` is the only importer.
//
// Real IndexedDB binding (tech-doc 003's promised cross-reload queue
// durability): `createRoomPushAndOutbox` below is the "attached separately
// by `family_chat.js`" seam `outbox.js`'s own header comment describes --
// see `persistence_indexeddb.js` for the real implementation.

import { createOutbox } from "./outbox.js";
import { resolvePersistence } from "./persistence_indexeddb.js";
import { createReconnect } from "./reconnect.js";
import { createPush } from "./push.js";
import { createSubscriptionClient } from "./graphql.js";
import { createRealTransport } from "./transport.js";
import { detectDevicePushState } from "./push_ux.js";
import { createRealStore } from "./real_store.js";

/**
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {{remediationMessage: string | null}} composerState
 */
export function handleQueueFull(elements, composerState) {
  composerState.remediationMessage =
    "Keep waiting messages under 100, or retry/discard one first.";
  elements.remediation.hidden = false;
  elements.remediation.textContent = composerState.remediationMessage;
}

/**
 * @param {string} roomSlug
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {{
 *   user?: {id: string},
 *   persistence?: import("./outbox_send.js").Persistence | undefined,
 *   replies?: boolean,
 *   request: import("./graphql.js").GraphqlRequest,
 * }} options
 * @param {import("./clock.js").Clock} clock
 * @param {{remediationMessage: string | null}} composerState
 */
export async function createRoomPushAndOutbox(
  roomSlug,
  elements,
  options,
  clock,
  composerState,
) {
  const transport = createRealTransport(roomSlug, {
    replies: options.replies ?? false,
    request: options.request,
  });

  const push = createPush({ devicePushState: detectDevicePushState() });

  const userId = options.user?.id ?? "anonymous";
  const persistence = await resolvePersistence(
    userId,
    roomSlug,
    options.persistence,
  );

  const outbox = createOutbox({
    userId,
    roomSlug,
    clock,
    transport,
    persistence,
    onQueueFull: () => handleQueueFull(elements, composerState),
    onAuthExpired: () => {
      if (elements.room)
        elements.room.dataset["connectionState"] = "auth-expired";
    },
  });

  return { push, outbox };
}

/**
 * @param {string} roomSlug
 * @param {import("./elements.js").FamilyChatElements} elements
 * @param {{user?: {id: string}, connectSocket?: import("./graphql.js").ConnectSocket}} options
 */
export function createRoomStoreAndReconnect(roomSlug, elements, options) {
  const store = createRealStore({
    roomSlug,
    elements,
    currentUserId: options.user?.id ?? null,
  });

  const subscriptionClient = createSubscriptionClient(
    options.connectSocket ? { connectSocket: options.connectSocket } : {},
  );
  // `store`/`roomSlug` are deliberately not passed here: `createReconnect`
  // (see `family_chat/reconnect.js`) only ever reads `clock`/`socketClient`
  // from its options; the real store/room wiring happens later, through
  // `bindBrowserCallbacks` in `mount_browser.js`.
  const reconnect = createReconnect({ socketClient: subscriptionClient });

  return { store, subscriptionClient, reconnect };
}
