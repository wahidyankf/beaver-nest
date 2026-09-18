// The real browser transport: `fetch`-based query/mutation over
// `/api/graphql`, and GraphQL subscriptions over Absinthe's control-topic
// protocol on the bare `phoenix` channel client (tech-doc 008; `@absinthe/
// socket` is abandoned upstream -- see Phase 0/3 -- so this implements the
// documented Absinthe.Phoenix wire protocol directly):
//
//   1. Join the `__absinthe__:control` channel once per socket.
//   2. Push a `"doc"` event with `{query, variables}`; the reply carries
//      `{subscriptionId}`.
//   3. Join a channel named after that `subscriptionId`; every commit is
//      pushed to it as a `"subscription:data"` event with `{result}`.
//
// Only constructed by `family_chat.js` when a real browser (`document`)
// exists -- FE_UNIT (Vitest, `environment: "node"`) never imports this
// module's socket path, matching this codebase's established "optional
// real-DOM binding only when `document` exists" pattern.

const GRAPHQL_PATH = "/api/graphql";
const SOCKET_PATH = "/api/graphql/socket";
const CONTROL_TOPIC = "__absinthe__:control";

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content ?? "";
}

/** Real HTTP query/mutation transport used by the outbox and room load. */
export async function request(query, variables) {
  const response = await fetch(GRAPHQL_PATH, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    body: JSON.stringify({ query, variables }),
  });
  return response.json();
}

/**
 * Lazily builds one `phoenix` Socket and one control-channel join per page,
 * shared by every subscription this room opens.
 */
export function createSubscriptionClient() {
  let socket = null;
  let controlChannel = null;
  let hasOpenedBefore = false;
  const reconnectListeners = new Set();

  async function ensureControlChannel() {
    if (controlChannel) return controlChannel;

    const { Socket } = await import("phoenix");
    socket = new Socket(SOCKET_PATH);
    // `phoenix`'s own exponential-backoff reconnect fires `onOpen` again
    // after any drop (including a Caddy cutover to a replacement slot) --
    // every open after the first is exactly the "promoted slot" signal
    // tech-doc 003's reconnect sequence needs to trigger on.
    socket.onOpen(() => {
      if (hasOpenedBefore) {
        for (const listener of reconnectListeners) listener();
      }
      hasOpenedBefore = true;
    });
    socket.connect();

    controlChannel = socket.channel(CONTROL_TOPIC, {});
    await new Promise((resolve, reject) => {
      controlChannel.join().receive("ok", resolve).receive("error", reject);
    });
    return controlChannel;
  }

  return {
    /**
     * @param {string} query a GraphQL subscription document.
     * @param {Record<string, unknown>} variables
     * @param {(result: unknown) => void} onData
     * @returns {Promise<{unsubscribe: () => void}>}
     */
    async subscribe(query, variables, onData) {
      const channel = await ensureControlChannel();

      return new Promise((resolve, reject) => {
        channel
          .push("doc", { query, variables })
          .receive("ok", ({ subscriptionId }) => {
            const dataChannel = socket.channel(subscriptionId, {});
            dataChannel.on("subscription:data", ({ result }) => onData(result));
            dataChannel
              .join()
              .receive("ok", () =>
                resolve({ unsubscribe: () => dataChannel.leave() }),
              )
              .receive("error", reject);
          })
          .receive("error", reject);
      });
    },

    /** @param {() => void} callback @returns {() => void} unsubscribe */
    onReconnect(callback) {
      reconnectListeners.add(callback);
      return () => reconnectListeners.delete(callback);
    },

    close() {
      socket?.disconnect();
      socket = null;
      controlChannel = null;
      // A fresh socket's very next open is a genuine first connect, not a
      // reconnect -- closing must not leave a stale "already open once"
      // memory behind for it.
      hasOpenedBefore = false;
    },
  };
}
