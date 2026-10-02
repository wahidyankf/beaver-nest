import { expect, type Page, type WebSocketRoute } from "@playwright/test";

// The room's subscription socket, routed through the test so a scenario can
// really drop it: every connection the page opens is passed straight
// through to the server (`connectToServer`, which forwards every frame both
// ways), until `drop` closes the live one from the server side and refuses
// new ones -- the browser sees a genuine close and its own reconnect
// attempts genuinely fail -- and `restore` lets the next attempt through.
// `page.on("websocket")` (`watchSockets`) observes the same sockets without
// changing them.

const SOCKET_URL = /\/api\/graphql\/socket\/websocket/u;
// A server going away, as a cut-over slot does.
const GOING_AWAY = 1001;

export interface SocketGate {
  /** When each connection the gate let through was opened. */
  openedAt: number[];
  drop(): Promise<void>;
  restore(): void;
}

/** Must be installed before the page opens the socket it is to govern. */
export async function gateRoomSocket(page: Page): Promise<SocketGate> {
  let refusing = false;
  const live = new Map<WebSocketRoute, WebSocketRoute>();
  const openedAt: number[] = [];
  await page.routeWebSocket(SOCKET_URL, async (socket) => {
    if (refusing) {
      await socket.close({ code: GOING_AWAY, reason: "dropped" });
      return;
    }
    live.set(socket, socket.connectToServer());
    openedAt.push(Date.now());
    socket.onClose(() => live.delete(socket));
  });
  return {
    openedAt,
    async drop() {
      refusing = true;
      // Both halves: the browser's end sees the close, and the server's
      // end stops delivering to a socket nobody holds any more.
      await Promise.all(
        [...live].flatMap(([socket, server]) => [
          socket.close({ code: GOING_AWAY, reason: "dropped" }),
          server.close({ code: GOING_AWAY, reason: "dropped" }),
        ]),
      );
      live.clear();
    },
    restore() {
      refusing = false;
    },
  };
}

export interface SocketLog {
  opened: number[];
  closed: number[];
}

/** Every room socket the page opens from now on, and when each closed. */
export function watchSockets(page: Page): SocketLog {
  const log: SocketLog = { opened: [], closed: [] };
  page.on("websocket", (socket) => {
    if (!SOCKET_URL.test(socket.url())) return;
    log.opened.push(Date.now());
    socket.on("close", () => log.closed.push(Date.now()));
  });
  return log;
}

export interface SubscriptionLog {
  /** How many times the server has acknowledged the room's subscription. */
  acknowledged: number;
}

/**
 * Every subscription the server acknowledges to this page from now on: the
 * reply to the room's `doc` push, which carries the subscription's ID. Until
 * the first one arrives the room is not yet subscribed, so dropping the
 * socket earlier would test the first connect, not a reconnect.
 */
export function watchSubscriptions(page: Page): SubscriptionLog {
  const log: SubscriptionLog = { acknowledged: 0 };
  page.on("websocket", (socket) => {
    if (!SOCKET_URL.test(socket.url())) return;
    socket.on("framereceived", ({ payload }) => {
      if (String(payload).includes('"subscriptionId"')) log.acknowledged += 1;
    });
  });
  return log;
}

export interface CatchUp {
  answeredAt: number;
  ids: string[];
}

function isCatchUp(postData: string): boolean {
  if (!postData.includes("FamilyChatMessages")) return false;
  const { variables } = JSON.parse(postData) as {
    variables?: { afterId?: string | null };
  };
  return typeof variables?.afterId === "string";
}

/**
 * Every catch-up page the room receives from now on -- a
 * `familyChatMessages` query after a known message (`afterId`), which only
 * the reconnect sequence sends -- with the message IDs it was answered with.
 */
export function recordCatchUps(page: Page): CatchUp[] {
  const catchUps: CatchUp[] = [];
  page.on("response", async (response) => {
    if (!isCatchUp(response.request().postData() ?? "")) return;
    const answeredAt = Date.now();
    const payload = (await response.json().catch(() => ({}))) as {
      data?: { familyChatMessages?: { nodes?: Array<{ id: string }> } };
    };
    catchUps.push({
      answeredAt,
      ids: (payload.data?.familyChatMessages?.nodes ?? []).map(
        (node) => node.id,
      ),
    });
  });
  return catchUps;
}

/** Waits for the room to report a connected, subscribed socket again. */
export async function expectRoomConnected(page: Page): Promise<void> {
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
    { timeout: 15_000 },
  );
}
