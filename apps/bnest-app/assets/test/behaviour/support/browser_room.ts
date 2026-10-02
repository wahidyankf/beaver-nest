// The browser the frontend Gherkin scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature run in.
//
// A scenario opens the production room exactly the way `app.js` does: the
// shipped `room.html.heex` shell is rendered into a happy-dom page, a fresh
// copy of `js/family_chat.js` is imported (`vi.resetModules`, so nothing a
// previous page load kept in module state survives -- a reload here is a
// reload), and `initRoomFromDocument` boots it. What a scenario cannot hand
// a browser, it hands the room as the collaborators `initRoom` already takes
// as parameters, each one a stand-in for something outside the browser tab:
//
// - `request` and `connectSocket` reach `graphql_server.ts`, an in-process
//   server that answers with the server's own contracts;
// - `persistence` and `readStorage` are this device's IndexedDB and
//   localStorage, which outlive every page load;
// - `clock` is the page's timers, advanced only when a scenario says time
//   passes.
//
// Everything else is the browser's, modelled here rather than in the room:
// layout (a fixed row height and history viewport, so scroll positions and
// "is it on screen" are arithmetic), the default actions of key and pointer
// input (Tab moves focus, Enter in a textarea inserts a newline, a press on
// a button focuses it unless the press was cancelled), the network going
// away, and a tab being backgrounded.
//
// Several pages can be open at once (two members, or one member's room and
// home page), but only one is the active tab: production modules read the
// ambient `window`/`document`, so the active page's are installed on
// `globalThis`. A page that is not active is frozen -- whatever reaches it
// (a socket push, a request's answer) waits until it is activated again --
// which is also what keeps one page's rendering out of another's document.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Window } from "happy-dom";
import { vi } from "vitest";
import { findElements } from "../../../js/family_chat/elements.js";
import { createFakeClock, type FakeClock } from "../../support/fake_clock";
import {
  createGraphqlServer,
  type FakeSocket,
  type GraphqlServer,
  type Member,
  type PostOptions,
  type ServerMessage,
} from "../../support/graphql_server";
import type { WorkerHarness } from "../../support/service_worker";

export type { Member, PostOptions, ServerMessage };
export type FamilyChatElements = ReturnType<typeof findElements>;

const here = path.dirname(fileURLToPath(import.meta.url));
const ASSETS = path.resolve(here, "../../..");
const ROOM_TEMPLATE = path.resolve(
  ASSETS,
  "../lib/bnest_app_web/controllers/family_chat_html/room.html.heex",
);
const HOME_TEMPLATE = path.resolve(
  ASSETS,
  "../lib/bnest_app_web/controllers/page_html/home.html.heex",
);
const APP_CSS = path.resolve(ASSETS, "css/app.css");
const ROOM_MODULE = new URL("../../../js/family_chat.js", import.meta.url).href;
const LOGOUT_MODULE = new URL("../../../js/logout.js", import.meta.url).href;

export const ORIGIN = "https://bnest.test";
export const ROOM_SLUG = "ruang-keluarga";
export const ROOM_PATH = `/family-chat/${ROOM_SLUG}`;
/** The seeded room's name (`BnestApp.FamilyChat`'s canonical room). */
export const ROOM_NAME = "Ruang Keluarga";

// --- Layout model ----------------------------------------------------------
//
// happy-dom has no layout engine, so the history's geometry is modelled:
// every list item is one fixed-height row, stacked under the "Load older"
// control, inside a history viewport of fixed height. `scrollTop` clamps the
// way a browser's does, and `getBoundingClientRect` reports where a row is
// for the scroll position the room set -- so "the message is in view" and
// "the anchor stayed put" are measured from the positions production code
// produced, never read back from anything it reports about itself.

export const HISTORY_TOP_PX = 100;
export const HISTORY_HEIGHT_PX = 400;
export const ROW_HEIGHT_PX = 40;
const LOAD_OLDER_HEIGHT_PX = 40;

interface Layout {
  page: Page;
  history: HTMLElement;
  list: HTMLElement;
  scrollTop: number;
  scrollEventQueued: boolean;
}

const layouts = new WeakMap<object, Layout>();
const patchedPrototypes = new WeakSet<object>();

function rowOf(layout: Layout, element: Element): Element | null {
  for (let node: Element | null = element; node; node = node.parentElement) {
    if (node.parentElement === layout.list) return node;
  }
  return null;
}

function scrollHeightOf(layout: Layout): number {
  return LOAD_OLDER_HEIGHT_PX + layout.list.children.length * ROW_HEIGHT_PX;
}

/** A row's top edge inside the scrollable content, before scrolling. */
function rowOffset(layout: Layout, row: Element): number {
  const index = Array.prototype.indexOf.call(layout.list.children, row);
  return LOAD_OLDER_HEIGHT_PX + index * ROW_HEIGHT_PX;
}

function rect(top: number, height: number, width: number) {
  return {
    top,
    bottom: top + height,
    left: 0,
    right: width,
    width,
    height,
    x: 0,
    y: top,
    toJSON: () => ({ top, height, width }),
  };
}

function layoutRect(layout: Layout, element: Element) {
  const width = layout.page.device.viewport.width;
  if (element === layout.history) {
    return rect(HISTORY_TOP_PX, HISTORY_HEIGHT_PX, width);
  }
  const row = rowOf(layout, element);
  if (!row) return null;
  return rect(
    HISTORY_TOP_PX + rowOffset(layout, row) - layout.scrollTop,
    ROW_HEIGHT_PX,
    width,
  );
}

function setScrollTop(layout: Layout, value: number): void {
  const max = Math.max(0, scrollHeightOf(layout) - HISTORY_HEIGHT_PX);
  const next = Math.min(Math.max(0, Number(value) || 0), max);
  if (next === layout.scrollTop) return;
  layout.scrollTop = next;
  // A browser reports a scroll position change on a later task, never
  // within the script that made it.
  if (layout.scrollEventQueued) return;
  layout.scrollEventQueued = true;
  setTimeout(() => {
    layout.scrollEventQueued = false;
    whenActive(layout.page, () =>
      layout.history.dispatchEvent(
        new layout.page.window.Event("scroll") as unknown as Event,
      ),
    );
  }, 0);
}

function patchLayoutPrototype(win: Window): void {
  const prototype = (
    win as unknown as { HTMLElement: { prototype: Record<string, unknown> } }
  ).HTMLElement.prototype;
  if (patchedPrototypes.has(prototype)) return;
  patchedPrototypes.add(prototype);
  const original = prototype["getBoundingClientRect"] as (
    this: Element,
  ) => unknown;
  prototype["getBoundingClientRect"] = function getBoundingClientRect(
    this: Element,
  ) {
    const layout = layouts.get(this.ownerDocument);
    return (layout && layoutRect(layout, this)) ?? original.call(this);
  };
  prototype["scrollIntoView"] = function scrollIntoView(
    this: HTMLElement,
    options?: { block?: string },
  ): void {
    const layout = layouts.get(this.ownerDocument);
    if (!layout) return;
    const row = rowOf(layout, this);
    if (!row) return;
    layout.page.scrolledTo.push(
      (row as HTMLElement).dataset["messageId"] ?? "",
    );
    const offset = rowOffset(layout, row);
    const block = options?.block ?? "start";
    const target =
      block === "center"
        ? offset - (HISTORY_HEIGHT_PX - ROW_HEIGHT_PX) / 2
        : block === "end"
          ? offset - HISTORY_HEIGHT_PX + ROW_HEIGHT_PX
          : offset;
    setScrollTop(layout, target);
  };
}

function installLayout(page: Page): void {
  const document = page.document;
  const history = document.querySelector<HTMLElement>(
    '[data-role="family-chat-history"]',
  );
  const list = document.querySelector<HTMLElement>(
    '[data-role="family-chat-message-list"]',
  );
  if (!history || !list) return;
  const layout: Layout = {
    page,
    history,
    list,
    scrollTop: 0,
    scrollEventQueued: false,
  };
  layouts.set(document, layout);
  patchLayoutPrototype(page.window);
  Object.defineProperty(history, "scrollTop", {
    configurable: true,
    get: () => layout.scrollTop,
    set: (value: number) => setScrollTop(layout, value),
  });
  Object.defineProperty(history, "scrollHeight", {
    configurable: true,
    get: () => scrollHeightOf(layout),
  });
  Object.defineProperty(history, "clientHeight", {
    configurable: true,
    get: () => HISTORY_HEIGHT_PX,
  });
}

/** Where a rendered row sits, relative to the top of the history viewport. */
export function offsetInHistory(element: Element): number {
  const layout = layouts.get(element.ownerDocument);
  if (!layout) throw new Error("this page has no history layout");
  return element.getBoundingClientRect().top - HISTORY_TOP_PX;
}

/** Whether the whole row is inside the history viewport. */
export function isInView(element: Element): boolean {
  const offset = offsetInHistory(element);
  return offset >= 0 && offset + ROW_HEIGHT_PX <= HISTORY_HEIGHT_PX;
}

/** What a member scrolling the history with a finger or wheel does. */
export function scrollHistoryTo(page: Page, scrollTop: number): void {
  const layout = layouts.get(page.document);
  if (!layout) throw new Error("this page has no history layout");
  setScrollTop(layout, scrollTop);
}

// --- Templates ---------------------------------------------------------------

function escapeAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;");
}

/**
 * Replaces each HEEx expression with what the controller renders for it,
 * and refuses to render if the template holds one this list does not know:
 * a harness that silently left `{@...}` in the markup would test a page no
 * visitor ever sees.
 */
function renderHeex(
  template: string,
  substitutions: [string, string][],
  name: string,
): string {
  let html = template;
  for (const [expression, value] of substitutions) {
    if (!html.includes(expression)) {
      throw new Error(`${name} no longer contains ${expression}`);
    }
    html = html.replaceAll(expression, value);
  }
  const withoutComments = html.replaceAll(/<!--[\s\S]*?-->/gu, "");
  const leftover = /\{[^}]*\}|<\.|<%|<Layouts/u.exec(withoutComments);
  if (leftover) {
    throw new Error(
      `${name} holds ${leftover[0]}, which the harness cannot render`,
    );
  }
  return html;
}

function renderRoom(member: Member, replies: boolean): string {
  return renderHeex(
    readFileSync(ROOM_TEMPLATE, "utf8"),
    [
      ["<Layouts.flash_group flash={@flash} />", ""],
      [
        'data-current-user-id={@current_user["userId"]}',
        `data-current-user-id="${escapeAttribute(member.id)}"`,
      ],
      [
        "data-family-chat-reply-enabled={to_string(assigns[:reply_enabled] == true)}",
        `data-family-chat-reply-enabled="${String(replies)}"`,
      ],
      [
        'aria-label={"Conversation in " <> @room.name}',
        `aria-label="Conversation in ${ROOM_NAME}"`,
      ],
      ["{@room.name}", ROOM_NAME],
    ],
    "room.html.heex",
  );
}

/** The home page's log-out form, as `home.html.heex` renders it. */
function renderLogoutForm(member: Member): string {
  const template = readFileSync(HOME_TEMPLATE, "utf8");
  const form = /<form\s+action="\/logout"[\s\S]*?<\/form>/u.exec(template);
  if (!form) throw new Error("home.html.heex no longer renders a log-out form");
  return renderHeex(
    form[0],
    [
      ["{get_csrf_token()}", "test-csrf-token"],
      [
        'data-current-user-id={@current_user["userId"]}',
        `data-current-user-id="${escapeAttribute(member.id)}"`,
      ],
    ],
    "home.html.heex's log-out form",
  );
}

const APP_CSS_TEXT = readFileSync(APP_CSS, "utf8");

// --- Device ------------------------------------------------------------------

export interface PersistedRow extends Record<string, unknown> {
  namespace: string;
  clientMessageId: string;
}

/**
 * The device's IndexedDB outbox store, holding rows in the shape
 * `persistence_indexeddb.js` writes them (`toRow`: no timer handle, no
 * `replyToMessageId` key unless there is a target), for every user who has
 * used this device.
 */
export function createDevicePersistence() {
  const rows = new Map<string, PersistedRow>();
  const keyOf = (namespace: string, clientMessageId: string) =>
    `${namespace}::${clientMessageId}`;
  return {
    rows,
    rowsFor: (namespace: string): PersistedRow[] =>
      [...rows.values()].filter((row) => row.namespace === namespace),
    /** What a tab closed earlier left behind. */
    seed(namespace: string, row: Record<string, unknown>): void {
      const stored = JSON.parse(
        JSON.stringify({ ...row, namespace }),
      ) as PersistedRow;
      rows.set(keyOf(namespace, stored.clientMessageId), stored);
    },
    async loadAll(namespace: string) {
      await Promise.resolve();
      return [...rows.values()]
        .filter((row) => row.namespace === namespace)
        .map((row) => ({ ...row, timerHandle: undefined }));
    },
    save(namespace: string, message: Record<string, unknown>): void {
      const { timerHandle: _timer, ...row } = message;
      const stored = JSON.parse(
        JSON.stringify({ ...row, namespace }),
      ) as PersistedRow;
      rows.set(keyOf(namespace, stored.clientMessageId), stored);
    },
    remove(namespace: string, clientMessageId: string): void {
      rows.delete(keyOf(namespace, clientMessageId));
    },
    clear(namespace: string): void {
      for (const [key, row] of rows) {
        if (row.namespace === namespace) rows.delete(key);
      }
    },
    async clearUser(userId: string): Promise<void> {
      await Promise.resolve();
      for (const [key, row] of rows) {
        if (row.namespace.startsWith(`${userId}:`)) rows.delete(key);
      }
    },
  };
}

export type DevicePersistence = ReturnType<typeof createDevicePersistence>;

export type DevicePushState =
  | "unsupported"
  | "requires installation"
  | "available, not yet decided"
  | "permission denied"
  | "subscription active";

export interface Viewport {
  width: number;
  height: number;
  deviceScaleFactor: number;
}

export interface Device {
  persistence: DevicePersistence;
  readStorage: Map<string, string>;
  clipboard: { writes: string[]; refuse: boolean };
  push: DevicePushState;
  /** Browser-side push unsubscribes, as `attemptPushDisable` makes them. */
  pushUnsubscribes: number;
  reducedMotion: boolean;
  viewport: Viewport;
  online: boolean;
  serviceWorker: WorkerHarness | null;
  /** Wall-clock time on this device, carried from one page load to the next. */
  now: number;
}

const DESKTOP_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36";
const IPHONE_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";

export function createDevice(): Device {
  return {
    persistence: createDevicePersistence(),
    readStorage: new Map(),
    clipboard: { writes: [], refuse: false },
    push: "unsupported",
    pushUnsubscribes: 0,
    reducedMotion: false,
    viewport: { width: 1280, height: 800, deviceScaleFactor: 1 },
    online: true,
    serviceWorker: null,
    now: 1_767_225_600_000,
  };
}

function storageOf(map: Map<string, string>) {
  return {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => void map.set(key, value),
    removeItem: (key: string) => void map.delete(key),
  };
}

// --- Pages -------------------------------------------------------------------

export interface Page {
  id: number;
  kind: "room" | "home";
  member: Member;
  device: Device;
  window: Window;
  document: Document;
  clock: FakeClock;
  /** What `initRoomFromDocument` returned. */
  room: Record<string, unknown> | null;
  elements: FamilyChatElements;
  sockets: FakeSocket[];
  scrolledTo: string[];
  visibility: "visible" | "hidden";
  inflight: number;
  closed: boolean;
  /** Where a submitted form sent this page, if anywhere. */
  navigatedTo: string | null;
  /** Every `confirm()` dialog the page raised, in order. */
  dialogs: string[];
  /** What the member answers the next `confirm()` dialog with. */
  confirmAnswer: boolean;
  pending: (() => void)[];
  activationWaiters: (() => void)[];
  restoreGlobals: (() => void) | null;
}

interface World {
  server: GraphqlServer;
  visitor: Member;
  device: Device;
  pages: Page[];
  active: Page | null;
  replies: boolean;
  sequence: number;
}

let world: World | null = null;
let pageSequence = 0;
let worldSequence = 0;

export function startWorld(): World {
  if (world) throw new Error("a previous scenario's world is still open");
  worldSequence += 1;
  const created: World = {
    server: createGraphqlServer({
      now: () => world?.active?.clock.now() ?? 0,
      roomSlug: ROOM_SLUG,
    }),
    // Synthetic, per scenario (test-identities.md): never a real account,
    // and never the same one twice, so no scenario inherits another's queue.
    visitor: {
      id: `test-user-family-chat-${worldSequence}`,
      displayName: "You",
    },
    device: createDevice(),
    pages: [],
    active: null,
    replies: true,
    sequence: worldSequence,
  };
  world = created;
  return created;
}

export function requireWorld(): World {
  if (!world) throw new Error("no scenario world: the Background did not run");
  return world;
}

/** Who "the visitor" is for the rest of the scenario. */
export function useVisitor(member: Member): void {
  requireWorld().visitor = member;
}

/** Another synthetic member of the family. */
export function otherMember(name: string): Member {
  const current = requireWorld();
  return {
    id: `test-user-family-chat-${name.toLowerCase()}-${current.sequence}`,
    displayName: name,
  };
}

export function activePage(): Page {
  const page = requireWorld().active;
  if (!page) throw new Error("no page is open in this scenario");
  return page;
}

export function hasActivePage(): boolean {
  return world?.active !== null && world?.active !== undefined;
}

function whenActive(page: Page, task: () => void): void {
  if (page.closed) return;
  if (world?.active === page) task();
  else page.pending.push(task);
}

function untilActive(page: Page): Promise<void> {
  if (world?.active === page) return Promise.resolve();
  return new Promise((resolve) => page.activationWaiters.push(resolve));
}

// Everything production modules reach for on the ambient global rather than
// through an injected collaborator.
const WINDOW_GLOBALS = [
  "window",
  "document",
  "location",
  "CSS",
  "Element",
  "Node",
  "Text",
  "DocumentFragment",
  "HTMLElement",
  "HTMLButtonElement",
  "HTMLInputElement",
  "HTMLTextAreaElement",
  "HTMLFormElement",
  "HTMLMetaElement",
  "HTMLLIElement",
  "Event",
  "MouseEvent",
  "PointerEvent",
  "KeyboardEvent",
  "FocusEvent",
  "InputEvent",
  "CustomEvent",
  "getComputedStyle",
  "matchMedia",
  "requestAnimationFrame",
  "cancelAnimationFrame",
] as const;

function pushGlobals(page: Page): Record<string, unknown> {
  const device = page.device;
  const subscription = {
    endpoint: `https://push.example.test/${page.member.id}`,
    toJSON: () => ({ keys: { p256dh: "test-p256dh", auth: "test-auth" } }),
    unsubscribe: async () => {
      device.pushUnsubscribes += 1;
      return true;
    },
  };
  const registration = {
    pushManager: {
      subscribe: async () => subscription,
      getSubscription: async () => subscription,
    },
  };
  const supported =
    device.push === "available, not yet decided" ||
    device.push === "permission denied" ||
    device.push === "subscription active";
  const permission =
    device.push === "permission denied"
      ? "denied"
      : device.push === "subscription active"
        ? "granted"
        : "default";
  const navigator: Record<string, unknown> = {
    userAgent:
      device.push === "requires installation"
        ? IPHONE_USER_AGENT
        : DESKTOP_USER_AGENT,
    clipboard: {
      writeText: async (text: string): Promise<void> => {
        await Promise.resolve();
        if (device.clipboard.refuse) {
          throw new Error("clipboard write refused");
        }
        device.clipboard.writes.push(text);
      },
    },
  };
  Object.defineProperty(navigator, "onLine", {
    enumerable: true,
    get: () => device.online,
  });
  if (supported) {
    navigator["serviceWorker"] = { ready: Promise.resolve(registration) };
  }
  return {
    navigator,
    ...(supported
      ? {
          Notification: {
            permission,
            requestPermission: async () => "granted",
          },
          PushManager: class PushManager {},
        }
      : {}),
  };
}

function installGlobals(page: Page): () => void {
  const source = page.window as unknown as Record<string, unknown>;
  const target = globalThis as unknown as Record<string, unknown>;
  const saved: { key: string; present: boolean; value: unknown }[] = [];

  function define(key: string, value: unknown): void {
    saved.push({ key, present: key in target, value: target[key] });
    Object.defineProperty(globalThis, key, {
      value,
      configurable: true,
      writable: true,
    });
  }

  for (const key of WINDOW_GLOBALS) {
    const value = source[key];
    define(
      key,
      typeof value === "function" && /^[a-z]/u.test(key)
        ? (value as (...args: unknown[]) => unknown).bind(page.window)
        : value,
    );
  }
  const push = pushGlobals(page);
  for (const [key, value] of Object.entries(push)) {
    define(key, value);
  }
  // `Notification`/`PushManager` must be absent, not undefined, on a device
  // without them: `detectDevicePushState` asks with `typeof`.
  for (const key of ["Notification", "PushManager"]) {
    if (!(key in push)) {
      saved.push({ key, present: key in target, value: target[key] });
      delete target[key];
    }
  }

  return () => {
    for (const entry of saved.reverse()) {
      if (entry.present) {
        Object.defineProperty(globalThis, entry.key, {
          value: entry.value,
          configurable: true,
          writable: true,
        });
      } else {
        delete target[entry.key];
      }
    }
  };
}

/** Makes `page` the tab the member is looking at. */
export function activate(page: Page): void {
  const current = requireWorld();
  if (page.closed) throw new Error("that page has been closed");
  if (current.active === page) return;
  if (current.active) {
    current.active.restoreGlobals?.();
    current.active.restoreGlobals = null;
  }
  page.restoreGlobals = installGlobals(page);
  current.active = page;
  for (const waiter of page.activationWaiters.splice(0)) waiter();
  for (const task of page.pending.splice(0)) task();
}

function createWindow(device: Device, pathname: string): Window {
  return new Window({
    url: `${ORIGIN}${pathname}`,
    settings: {
      disableJavaScriptEvaluation: true,
      disableJavaScriptFileLoading: true,
      disableCSSFileLoading: true,
      navigation: { disableMainFrameNavigation: true },
      device: {
        prefersReducedMotion: device.reducedMotion ? "reduce" : "no-preference",
      },
      viewport: {
        width: device.viewport.width,
        height: device.viewport.height,
        devicePixelRatio: device.viewport.deviceScaleFactor,
      },
    },
  });
}

/**
 * Time passes only when a scenario says so, but a zero-delay timer is not
 * "time passing": a browser runs `setTimeout(fn, 0)` on its next task
 * whatever the scenario is doing, so this clock does too.
 */
function runZeroDelayTimers(page: Page): void {
  const schedule = page.clock.setTimer;
  page.clock.setTimer = (fn, delayMs) => {
    const handle = schedule(fn, delayMs);
    if (delayMs <= 0) {
      setTimeout(() => whenActive(page, () => page.clock.advance(0)), 0);
    }
    return handle;
  };
}

function newPage(
  kind: Page["kind"],
  member: Member,
  device: Device,
  pathname: string,
  body: string,
): Page {
  pageSequence += 1;
  const win = createWindow(device, pathname);
  const document = win.document as unknown as Document;
  const style = document.createElement("style");
  style.textContent = APP_CSS_TEXT;
  document.head.append(style);
  document.body.innerHTML = body;
  const page: Page = {
    id: pageSequence,
    kind,
    member,
    device,
    window: win,
    document,
    clock: createFakeClock(pageSequence, device.now),
    room: null,
    elements: undefined as unknown as FamilyChatElements,
    sockets: [],
    scrolledTo: [],
    visibility: "visible",
    inflight: 0,
    closed: false,
    navigatedTo: null,
    dialogs: [],
    confirmAnswer: true,
    pending: [],
    activationWaiters: [],
    restoreGlobals: null,
  };
  runZeroDelayTimers(page);
  // The browser's modal dialog, answered by the member: the page sees only
  // the answer, as it would in a browser.
  Object.defineProperty(win, "confirm", {
    configurable: true,
    value: (message: string) => {
      page.dialogs.push(String(message));
      return page.confirmAnswer;
    },
  });
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => page.visibility,
  });
  Object.defineProperty(document, "hidden", {
    configurable: true,
    get: () => page.visibility === "hidden",
  });
  requireWorld().pages.push(page);
  return page;
}

/** The room's way to the server, as this page's network carries it. */
function requestFor(page: Page) {
  const client = requireWorld().server.clientFor(page.member);
  return async (query: string, variables: Record<string, unknown>) => {
    page.inflight += 1;
    try {
      const worker = page.device.serviceWorker;
      if (worker) {
        const answered = await worker.fetch("/api/graphql", { method: "POST" });
        if (answered !== null) {
          throw new Error("the service worker answered a GraphQL request");
        }
      }
      // Offline, nothing the member sends gets anywhere; what the page
      // already loaded (and loads from the same document) still renders.
      if (!page.device.online && query.includes("mutation")) {
        await new Promise((resolve) => setTimeout(resolve, 0));
        throw new TypeError("Failed to fetch");
      }
      const answer = await client.request(query, variables);
      await untilActive(page);
      return answer;
    } finally {
      page.inflight -= 1;
    }
  };
}

interface RawChannel {
  join: () => unknown;
  push: (event: string, payload: Record<string, unknown>) => unknown;
  on: (
    event: string,
    handler: (payload: Record<string, unknown>) => void,
  ) => void;
  off: (event: string) => void;
}

/**
 * phoenix's `Socket`, as far as the room uses it, over the server's socket:
 * frames for a frozen page wait for it, and a socket the network dropped
 * reconnects when the network returns -- which is what phoenix's own
 * reconnect timer does.
 */
/** Sockets the room still wants connected: phoenix keeps retrying those. */
const wantsConnection = new WeakSet<FakeSocket>();

function socketFor(page: Page) {
  const client = requireWorld().server.clientFor(page.member);
  return async (socketPath: string) => {
    const raw = (await client.connectSocket(socketPath)) as FakeSocket;
    page.sockets.push(raw);
    function connect(): void {
      wantsConnection.add(raw);
      if (page.device.online) raw.connect();
    }
    return {
      onOpen: (callback: () => void) =>
        raw.onOpen(() => whenActive(page, callback)),
      connect,
      disconnect: (callback?: () => void) => {
        wantsConnection.delete(raw);
        raw.disconnect(callback);
      },
      channel: (topic: string, params: unknown) => {
        const channel = raw.channel(topic, params) as unknown as RawChannel;
        return {
          join: () => channel.join(),
          push: (event: string, payload: Record<string, unknown>) =>
            channel.push(event, payload),
          on: (
            event: string,
            handler: (payload: Record<string, unknown>) => void,
          ) =>
            channel.on(event, (payload) =>
              whenActive(page, () => handler(payload)),
            ),
          off: (event: string) => channel.off(event),
        };
      },
    };
  };
}

/** Waits until nothing this page asked for is still on the wire. */
export async function settle(page: Page = activePage()): Promise<void> {
  const server = requireWorld().server;
  let quietTurns = 0;
  for (let turn = 0; turn < 2000; turn += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1));
    const busy = page.inflight - server.heldFor(page.member.id) > 0;
    quietTurns = busy ? 0 : quietTurns + 1;
    if (quietTurns >= 3) return;
  }
  throw new Error("the page never settled");
}

/**
 * Polls rather than awaiting a fixed number of turns: the paths under proof
 * chain several promises each, and a fixed `await` count is the kind of
 * assertion that passes until one more link is added to the chain.
 */
export async function waitFor(
  predicate: () => boolean,
  describe: string,
  attempts = 500,
): Promise<void> {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  throw new Error(`timed out waiting for ${describe}`);
}

/**
 * Loads `pathname` for `member` on `device`, the way a browser navigation
 * and `app.js` do. The reply flag is the routed revision's.
 */
export async function openRoomPage(
  options: { member?: Member; device?: Device; pathname?: string } = {},
): Promise<Page> {
  const current = requireWorld();
  const member = options.member ?? current.visitor;
  const device = options.device ?? current.device;
  const pathname = options.pathname ?? ROOM_PATH;
  const worker = device.serviceWorker;
  if (worker) {
    await worker.fetch(pathname, { mode: "navigate" });
    await worker.fetch("/assets/css/app.css");
    await worker.fetch("/assets/js/app.js");
  }
  const page = newPage(
    "room",
    member,
    device,
    pathname,
    renderRoom(member, current.replies),
  );
  activate(page);
  installLayout(page);
  page.elements = findElements();
  vi.resetModules();
  const { initRoomFromDocument } = (await import(
    /* @vite-ignore */ ROOM_MODULE
  )) as {
    initRoomFromDocument: (
      collaborators: Record<string, unknown>,
    ) => Promise<Record<string, unknown> | null>;
  };
  page.room = await initRoomFromDocument({
    clock: page.clock,
    persistence: device.persistence,
    readStorage: storageOf(device.readStorage),
    request: requestFor(page),
    connectSocket: socketFor(page),
  });
  if (!page.room)
    throw new Error("the rendered room shell did not boot a room");
  await settle(page);
  return page;
}

/**
 * What already reached the page before the member left it (a socket frame
 * mid-render, say) finishes first, as it would in the browser's event loop
 * before the navigation runs; nothing that arrives later is processed.
 */
async function drainEventLoop(page: Page): Promise<void> {
  if (world?.active !== page) return;
  for (let turn = 0; turn < 3; turn += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

/** Leaves the page: its sockets close and its timers die with it. */
export async function closePage(page: Page): Promise<void> {
  if (page.closed) return;
  const current = requireWorld();
  await drainEventLoop(page);
  page.device.now = Math.max(page.device.now, page.clock.now());
  page.closed = true;
  for (const socket of page.sockets) {
    wantsConnection.delete(socket);
    socket.disconnect();
  }
  if (current.active === page) {
    page.restoreGlobals?.();
    page.restoreGlobals = null;
    current.active = null;
  }
  await page.window.happyDOM.close();
}

/** A reload: the same device and member, and a brand new JS runtime. */
export async function reloadPage(page: Page = activePage()): Promise<Page> {
  await closePage(page);
  return openRoomPage({
    member: page.member,
    device: page.device,
    pathname: new URL(page.window.location.href).pathname,
  });
}

/**
 * The home page's log-out form, wired the way `app.js` wires it, with this
 * device's outbox store. Submitting it ends the session on the server.
 */
export async function openHomePage(
  options: { member?: Member; device?: Device } = {},
): Promise<Page> {
  const current = requireWorld();
  const member = options.member ?? current.visitor;
  const device = options.device ?? current.device;
  const page = newPage(
    "home",
    member,
    device,
    "/",
    `<main class="home-shell">${renderLogoutForm(member)}</main>`,
  );
  activate(page);
  const form = page.document.querySelector("form");
  if (!form) throw new Error("the home page rendered no log-out form");
  // A form submission is a navigation: the browser carries it to the
  // server, which is the boundary this harness stands in for.
  Object.defineProperty(form, "submit", {
    configurable: true,
    value: () => {
      current.server.logout(member.id);
      page.navigatedTo = "/login";
    },
  });
  vi.resetModules();
  const { wireLogoutQueueClearing } = (await import(
    /* @vite-ignore */ LOGOUT_MODULE
  )) as {
    wireLogoutQueueClearing: (collaborators: Record<string, unknown>) => void;
  };
  wireLogoutQueueClearing({ persistence: device.persistence });
  return page;
}

export async function closeWorld(): Promise<void> {
  if (!world) return;
  const current = world;
  if (current.active) await drainEventLoop(current.active);
  for (const page of current.pages) {
    if (!page.closed) {
      page.closed = true;
      page.restoreGlobals?.();
      page.restoreGlobals = null;
      await page.window.happyDOM.close();
    }
  }
  current.active = null;
  world = null;
}

// --- The network -------------------------------------------------------------

/**
 * The device loses (or regains) its network. The browser says so, every
 * socket on it drops without a close frame, and on the way back phoenix's
 * own reconnect opens each one again.
 */
export function setDeviceOnline(device: Device, online: boolean): void {
  const current = requireWorld();
  device.online = online;
  for (const page of current.pages) {
    if (page.closed || page.device !== device) continue;
    whenActive(page, () =>
      page.window.dispatchEvent(
        new page.window.Event(online ? "online" : "offline"),
      ),
    );
    if (online) whenActive(page, () => reconnectSockets(page));
    else dropSockets(page);
  }
}

/** The server side of every socket on the page goes away, silently. */
export function dropSockets(page: Page): void {
  for (const socket of page.sockets) socket.sever();
}

/** phoenix's reconnect timer firing for every dropped socket on the page. */
export function reconnectSockets(page: Page): void {
  for (const socket of page.sockets) {
    if (wantsConnection.has(socket) && !socket.record.open) socket.connect();
  }
}

/** The tab is backgrounded or foregrounded. */
export function setVisibility(
  page: Page,
  visibility: "visible" | "hidden",
): void {
  page.visibility = visibility;
  whenActive(page, () =>
    page.document.dispatchEvent(
      new page.window.Event("visibilitychange") as unknown as Event,
    ),
  );
}

// --- Input ---------------------------------------------------------------------

const FOCUSABLE =
  "a[href], button, input, select, textarea, [tabindex], [contenteditable]";

function isDisabled(element: Element): boolean {
  return (element as HTMLButtonElement).disabled === true;
}

/**
 * The element's computed style as of now. happy-dom caches computed styles
 * until the DOM mutates, and a focus change is not a mutation, so a style
 * read before Tab would otherwise be returned after it -- without the
 * `:focus-visible` ring. Touching an attribute nothing in the room reads
 * clears that cache.
 */
export function computedStyleOf(element: Element): CSSStyleDeclaration {
  element.setAttribute("data-harness-restyle", "");
  element.removeAttribute("data-harness-restyle");
  const win = element.ownerDocument.defaultView;
  if (!win) throw new Error("the element is not in a page");
  return win.getComputedStyle(element);
}

/** Whether a browser would render the element at all. */
export function isRendered(element: Element): boolean {
  const win = element.ownerDocument.defaultView;
  for (let node: Element | null = element; node; node = node.parentElement) {
    if ((node as HTMLElement).hidden) return false;
    const style = win?.getComputedStyle(node);
    if (style?.display === "none" || style?.visibility === "hidden") {
      return false;
    }
  }
  return true;
}

function focusableAncestor(element: Element | null): HTMLElement | null {
  for (let node = element; node; node = node.parentElement) {
    if (node.matches(FOCUSABLE) && !isDisabled(node))
      return node as HTMLElement;
  }
  return null;
}

/** The sequential focus navigation order a browser computes for Tab. */
export function tabOrder(document: Document): HTMLElement[] {
  const candidates = [
    ...document.querySelectorAll<HTMLElement>(FOCUSABLE),
  ].filter(
    (element) =>
      element.tabIndex >= 0 && !isDisabled(element) && isRendered(element),
  );
  const positive = candidates
    .filter((element) => element.tabIndex > 0)
    .sort((a, b) => a.tabIndex - b.tabIndex);
  return [
    ...positive,
    ...candidates.filter((element) => element.tabIndex === 0),
  ];
}

function moveFocusByTab(document: Document, backwards: boolean): void {
  const order = tabOrder(document);
  if (order.length === 0) return;
  const active = document.activeElement;
  let index = order.indexOf(active as HTMLElement);
  if (index === -1 && active && active !== document.body) {
    // Focus sits on something Tab would skip (a roving item that is not
    // the stop, say): continue from where it is in the document.
    const following = order.findIndex(
      (element) => (active.compareDocumentPosition(element) & 4) !== 0,
    );
    index = backwards
      ? following === -1
        ? order.length
        : following
      : (following === -1 ? order.length : following) - 1;
  }
  const next = backwards
    ? order[(index <= 0 ? order.length : index) - 1]
    : order[(index + 1) % order.length];
  next?.focus();
}

function keyboardEvent(
  page: Page,
  type: string,
  key: string,
  shiftKey: boolean,
) {
  return new page.window.KeyboardEvent(type, {
    key,
    shiftKey,
    bubbles: true,
    cancelable: true,
  });
}

/**
 * A key press on whatever holds focus, with the browser's default action
 * for it unless the page cancelled the keydown.
 */
export async function pressKey(
  key: string,
  options: { shiftKey?: boolean } = {},
): Promise<void> {
  const page = activePage();
  const document = page.document;
  const target = (document.activeElement ?? document.body) as HTMLElement;
  const shiftKey = options.shiftKey ?? false;
  const down = keyboardEvent(page, "keydown", key, shiftKey);
  target.dispatchEvent(down as unknown as Event);
  if (!down.defaultPrevented) {
    if (key === "Tab") {
      moveFocusByTab(document, shiftKey);
    } else if (key === "Enter" && target.tagName === "TEXTAREA") {
      (target as HTMLTextAreaElement).value += "\n";
      target.dispatchEvent(
        new page.window.Event("input", { bubbles: true }) as unknown as Event,
      );
    } else if (
      (key === "Enter" || key === " ") &&
      target.matches("button, a[href]") &&
      !isDisabled(target)
    ) {
      target.click();
    }
  }
  target.dispatchEvent(
    keyboardEvent(page, "keyup", key, shiftKey) as unknown as Event,
  );
  await new Promise((resolve) => setTimeout(resolve, 1));
}

/** Typing into whatever holds focus. */
export function typeText(text: string): void {
  const page = activePage();
  const target = page.document.activeElement as HTMLTextAreaElement | null;
  if (!target || !("value" in target)) {
    throw new Error("nothing that takes text holds focus");
  }
  target.value += text;
  target.dispatchEvent(
    new page.window.Event("input", { bubbles: true }) as unknown as Event,
  );
}

function pointerEvent(
  page: Page,
  type: string,
  init: { clientX?: number; clientY?: number } = {},
) {
  return new page.window.PointerEvent(type, {
    bubbles: true,
    cancelable: true,
    pointerId: 1,
    isPrimary: true,
    clientX: init.clientX ?? 40,
    clientY: init.clientY ?? 80,
  });
}

/**
 * A primary pointer goes down on `target`. A browser follows an uncancelled
 * `pointerdown` with `mousedown`, and an uncancelled `mousedown` with moving
 * focus to the nearest focusable ancestor of the target.
 */
export function pointerDown(
  target: Element,
  init: { clientX?: number; clientY?: number } = {},
): { focusMoved: boolean } {
  const page = activePage();
  const down = pointerEvent(page, "pointerdown", init);
  target.dispatchEvent(down as unknown as Event);
  if (down.defaultPrevented) return { focusMoved: false };
  const mouse = new page.window.MouseEvent("mousedown", {
    bubbles: true,
    cancelable: true,
    clientX: init.clientX ?? 40,
    clientY: init.clientY ?? 80,
  });
  target.dispatchEvent(mouse as unknown as Event);
  if (mouse.defaultPrevented) return { focusMoved: false };
  const before = page.document.activeElement;
  const focusable = focusableAncestor(target);
  if (focusable) focusable.focus();
  else (page.document.activeElement as HTMLElement | null)?.blur?.();
  return { focusMoved: page.document.activeElement !== before };
}

export function pointerMove(
  target: Element,
  init: { clientX?: number; clientY?: number },
): void {
  const page = activePage();
  target.dispatchEvent(
    pointerEvent(page, "pointermove", init) as unknown as Event,
  );
}

export function pointerUp(target: Element): void {
  const page = activePage();
  target.dispatchEvent(pointerEvent(page, "pointerup") as unknown as Event);
  target.dispatchEvent(
    new page.window.MouseEvent("mouseup", {
      bubbles: true,
    }) as unknown as Event,
  );
}

/** A complete click: press, release, and the activation that follows. */
export async function clickOn(
  target: Element,
): Promise<{ focusMoved: boolean }> {
  const pressed = pointerDown(target);
  pointerUp(target);
  (target as HTMLElement).click();
  await new Promise((resolve) => setTimeout(resolve, 1));
  return pressed;
}

// --- Reading the page ------------------------------------------------------------

export function messageRows(page: Page = activePage()): HTMLElement[] {
  return [
    ...page.elements.list.querySelectorAll<HTMLElement>(
      '[data-role="family-chat-message"]',
    ),
  ];
}

export function rowFor(
  id: string,
  page: Page = activePage(),
): HTMLElement | null {
  return (
    messageRows(page).find((row) => row.dataset["messageId"] === id) ?? null
  );
}

export function requireRow(id: string, page: Page = activePage()): HTMLElement {
  const row = rowFor(id, page);
  if (!row) throw new Error(`message ${id} is not rendered`);
  return row;
}

/** The delivery status a pending row shows its reader. */
export function shownStatus(row: HTMLElement): string {
  return (
    row.querySelector('[data-role="family-chat-message-status"]')
      ?.textContent ?? ""
  );
}

export function announcement(page: Page = activePage()): string {
  return page.elements.liveRegion.textContent ?? "";
}

export function visibleRemediation(page: Page = activePage()): string {
  const element = page.elements.remediation;
  return element.hidden ? "" : (element.textContent ?? "");
}

export function hidden(element: HTMLElement): boolean {
  return element.hidden !== false;
}

export function server(): GraphqlServer {
  return requireWorld().server;
}

export function visitor(): Member {
  return requireWorld().visitor;
}

export function device(): Device {
  return requireWorld().device;
}

/** Which revision Caddy routes decides whether the room it serves has replies. */
export function routeRevision(replies: boolean): void {
  requireWorld().replies = replies;
}

export function namespaceOf(member: Member): string {
  return `${member.id}:${ROOM_SLUG}`;
}

/**
 * Records every pending row the room renders from here on, by the client
 * id it carries -- a pending row can be reconciled away before anyone
 * looks for it.
 */
export function watchPendingRows(page: Page = activePage()): string[] {
  const seen: string[] = [];
  const observer = new page.window.MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        const row = node as unknown as HTMLElement;
        if (
          row.dataset?.["role"] === "family-chat-message" &&
          row.dataset["deliveryState"] !== "committed"
        ) {
          seen.push(row.dataset["messageId"] ?? "");
        }
      }
    }
  });
  observer.observe(page.elements.list as unknown as never, { childList: true });
  return seen;
}

/**
 * Composes and sends a message the way a member does: focus the input,
 * type, press Send. Returns the client id of the row it queued, or `null`
 * when the room refused it.
 */
export async function sendThroughComposer(
  body: string,
  page: Page = activePage(),
): Promise<string | null> {
  const queued = watchPendingRows(page);
  page.elements.input.focus();
  page.elements.input.value = "";
  typeText(body);
  await clickOn(page.elements.send);
  await waitFor(
    () => queued.length > 0 || visibleRemediation(page) !== "",
    "the composed message to be queued or refused",
  );
  return queued[0] ?? null;
}

/** What the visitor's send of `clientMessageId` committed as, if it did. */
export function committedFor(
  clientMessageId: string,
  member: Member = visitor(),
): ServerMessage | undefined {
  return server().committedFor(member.id, clientMessageId);
}

export function post(options: PostOptions): ServerMessage {
  return server().post(options);
}
