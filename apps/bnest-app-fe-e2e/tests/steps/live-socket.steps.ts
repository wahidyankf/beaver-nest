import { expect, type WebSocketRoute } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Before, When } = createBdd();

// The LiveView socket of each @live-socket-drop scenario's browser context, from the first page on. The socket is
// routed through Playwright, so the test can close it and LiveView reconnects to the same server by itself.
const liveSockets = new WeakMap<object, WebSocketRoute[]>();

Before("@live-socket-drop", ({ context }) => {
  const sockets: WebSocketRoute[] = [];
  liveSockets.set(context, sockets);
  void context.routeWebSocket(/\/live\/websocket/u, (socket) => {
    sockets.push(socket);
    socket.connectToServer();
  });
});

// Closes the page's LiveView socket. LiveView reconnects by itself: the page's new socket is the same server's
// new mount of the saved chat, so a turn in progress resumes there without a reload.
When(
  "the visitor's live connection drops and returns",
  async ({ page, context }) => {
    // The server has taken the message once its reply element exists. A drop before that would lose the submit:
    // LiveView does not resend it, and the text would only come back as an unsent draft in the composer.
    await expect(
      page.locator("[data-role=assistant-message]").last(),
    ).toBeAttached();
    const sockets = liveSockets.get(context) ?? [];
    const opened = sockets.length;
    await Promise.all(sockets.map((socket) => socket.close()));
    await expect.poll(() => sockets.length).toBeGreaterThan(opened);
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  },
);
