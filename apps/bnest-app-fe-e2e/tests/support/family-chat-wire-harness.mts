import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { register } from "node:module";
import path from "node:path";
import type { Page } from "@playwright/test";

// The harness for the earlier-revision wire tests, which drive the wire without a browser: the page is a fake whose route
// handlers are captured, so the socket and HTTP handlers run against scripted frames.

// The wire imports extensionless TypeScript siblings, and this package is commonjs, so node --test needs a loader that
// resolves those names and loads the app's TypeScript as modules. The judge test has the narrower form of this hook.
const TS_MODULE_HOOK = `export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (error) {
    if (error.code !== "ERR_MODULE_NOT_FOUND" || !specifier.startsWith(".")) throw error;
    for (const extension of [".ts", ".mts"]) {
      try {
        return await nextResolve(specifier + extension, context);
      } catch {
        // Not this extension: try the next one.
      }
    }
    throw error;
  }
}
export async function load(url, context, nextLoad) {
  if (/\\/apps\\/bnest-app-fe-e2e\\/.*\\.m?ts$/u.test(url))
    return nextLoad(url, { ...context, format: "module-typescript" });
  return nextLoad(url, context);
}`;
register(`data:text/javascript,${encodeURIComponent(TS_MODULE_HOOK)}`);
export const wire = await import("./family-chat-previous-revision.ts");

// The frozen previous bundle's documents: the wire replays these in place of what the page sends.
const FIXTURE = path.resolve(
  import.meta.dirname,
  "../../../bnest-app/assets/test/support/family_chat_previous_revision.json",
);
const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as {
  previousClient: { documents: Record<string, { document: string }> };
};
export const documentOf = (operation: string): string => {
  const entry = fixture.previousClient.documents[operation];
  assert.ok(entry, `the frozen bundle has no ${operation} document`);
  return entry.document;
};

export const CONTROL_TOPIC = "__absinthe__:control";
export const ROOM = "ruang-keluarga";
export const frame = (...parts: unknown[]): string => JSON.stringify(parts);

export type Message = string | Buffer;
type Handler = (message: Message) => void;

/** A socket the wire takes over: its page side, and the server side it connects to. */
export function fakeSocket() {
  const handlers: { fromPage?: Handler; fromServer?: Handler } = {};
  const sent = { toServer: [] as Message[], toPage: [] as Message[] };
  const socket = {
    onMessage: (handler: Handler) => {
      handlers.fromPage = handler;
    },
    connectToServer: () => ({
      onMessage: (handler: Handler) => {
        handlers.fromServer = handler;
      },
      send: (message: Message) => {
        sent.toServer.push(message);
      },
    }),
    send: (message: Message) => {
      sent.toPage.push(message);
    },
  };
  return {
    socket,
    sent,
    fromPage: (message: Message) => handlers.fromPage?.(message),
    fromServer: (message: Message) => handlers.fromServer?.(message),
  };
}
export type FakeWebSocket = ReturnType<typeof fakeSocket>["socket"];

export type FakeLive = {
  ok(): boolean;
  status(): number;
  text(): Promise<string>;
};
export type FakeRoute = {
  request(): { postData(): string };
  fetch(options: { postData: string }): Promise<FakeLive>;
  fulfill(options: { response: FakeLive }): string;
  continue(options?: { postData: string }): string;
  abort(): string;
};

/** A page that keeps the handlers the wire registers, so a test can call them as the browser would. */
export function fakePage() {
  const routes: {
    http?: (route: FakeRoute) => unknown;
    socket?: (socket: FakeWebSocket) => unknown;
  } = {};
  const page = {
    route: (_pattern: string, handler: (route: FakeRoute) => unknown) => {
      routes.http = handler;
      return Promise.resolve();
    },
    routeWebSocket: (
      _pattern: RegExp,
      handler: (socket: FakeWebSocket) => unknown,
    ) => {
      routes.socket = handler;
      return Promise.resolve();
    },
  };
  return { page: page as unknown as Page, routes };
}

/** A page armed as the rollback floor arms it: the previous bundle's documents replayed, and every document judged. */
export async function armedPage() {
  const { page, routes } = fakePage();
  await wire.sendPreviousBundleDocuments(page);
  wire.judgeAgainstRolledBackSlot(page);
  const ws = fakeSocket();
  assert.ok(routes.socket, "the socket route was not registered");
  await routes.socket(ws.socket);
  return { routes, ws };
}
