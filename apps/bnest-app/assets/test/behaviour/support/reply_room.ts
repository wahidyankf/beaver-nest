// A browser-shaped Family Chat room for the reply scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature.
//
// `family_chat.steps.ts`'s own room is deliberately document-free: it opens
// the real `initRoom` in Node, where `typeof document === "undefined"` picks
// the in-memory store, transport, and page source. That is the right shape
// for queue and status scenarios and the wrong one for the reply scenarios,
// which are about markup, focus, and key events.
//
// So this module builds what the browser branch of `initRoom` builds -- the
// shipped template's DOM under happy-dom, `createRealStore`,
// `createHistory`, `createReplyTarget`, and the real `wire*` bindings from
// `mount_browser*.js` -- with one substitution: the network. The outbox gets
// a transport backed by the in-process server double below instead of
// `createRealTransport`'s fetch, and there is no socket. What a real browser
// and a real server do together is `bnest-app-fe-e2e`'s to prove; what this
// wiring decides is this harness's.
//
// The window is installed on `globalThis` (the production modules read the
// ambient `document`, `Element`, `CSS`, and `navigator`) and removed again
// by `closeBrowserRoom`, which `verify.ts` calls after every scenario.
// Leaving a document installed would silently flip `family_chat.steps.ts`'s
// own document-free scenarios onto the browser branch.

import { Window } from "happy-dom";
import { createComposer } from "../../../js/family_chat/composer.js";
import { findElements } from "../../../js/family_chat/elements.js";
import { createHistory } from "../../../js/family_chat/history.js";
import {
  wireMessageActions,
  wireReplyStrip,
} from "../../../js/family_chat/mount_browser_actions.js";
import { wireComposer } from "../../../js/family_chat/mount_browser_composer.js";
import { wireQuoteJump } from "../../../js/family_chat/mount_browser_jump.js";
import { createOutbox } from "../../../js/family_chat/outbox.js";
import { createTestPageSource } from "../../../js/family_chat/page_source.js";
import { resolvePersistence } from "../../../js/family_chat/persistence_indexeddb.js";
import { createReadMarker } from "../../../js/family_chat/read_marker.js";
import { createRealStore } from "../../../js/family_chat/real_store.js";
import { createReconnect } from "../../../js/family_chat/reconnect.js";
import { createReplyTarget } from "../../../js/family_chat/reply_target.js";
import { createFakeClock, type FakeClock } from "../../support/fake_clock";

type FamilyChatElements = ReturnType<typeof findElements>;

const ROOM_SLUG = "ruang-keluarga";

// A faithful copy of `room.html.heex`'s `data-role` shell -- every handle
// `elements.js` queries, in the nesting the bindings depend on (the list
// inside the history, the strip inside the composer). Only the roles are
// load-bearing here; the template's own copy, classes, and headings are
// `family_chat_room_page_test.exs`'s and FE_E2E's to assert.
const SHELL = `
<main data-role="family-chat-room" data-family-chat-reply-enabled="true">
  <button data-role="family-chat-push-control"></button>
  <button data-role="family-chat-push-disable" hidden></button>
  <p data-role="family-chat-offline-banner" hidden></p>
  <div data-role="family-chat-history">
    <button data-role="family-chat-load-older"></button>
    <p data-role="family-chat-empty"></p>
    <ol data-role="family-chat-message-list" role="log"></ol>
    <span data-role="family-chat-scroll-anchor" data-anchor-offset="0"></span>
  </div>
  <button data-role="family-chat-new-messages" hidden></button>
  <div data-role="family-chat-message-actions" role="menu" hidden></div>
  <p data-role="family-chat-live-region" role="status"></p>
  <form data-role="family-chat-composer">
    <div data-role="family-chat-reply-strip" hidden>
      <span data-role="family-chat-reply-strip-name"></span>
      <span data-role="family-chat-reply-strip-preview"></span>
      <button type="button" data-role="family-chat-reply-strip-cancel"></button>
    </div>
    <textarea data-role="family-chat-message-input"></textarea>
    <button type="submit" data-role="family-chat-send"></button>
    <p data-role="family-chat-remediation" hidden></p>
    <p data-role="family-chat-outbox-status"></p>
  </form>
</main>
`;

// Everything the production modules reach for on the ambient global rather
// than through an injected collaborator. `navigator` is not taken from the
// window: the clipboard is a scenario-controlled double.
const GLOBAL_KEYS = [
  "window",
  "document",
  "CSS",
  "Element",
  "Node",
  "HTMLElement",
  "HTMLButtonElement",
  "HTMLInputElement",
  "HTMLTextAreaElement",
  "Event",
  "MouseEvent",
  "KeyboardEvent",
  "CustomEvent",
  "getComputedStyle",
] as const;

export interface Quote {
  id: string;
  senderKind: string;
  senderDisplayName: string;
  bodyPreview: string;
}

export interface HarnessMessage {
  id: string;
  body: string;
  senderId: string;
  senderKind: string;
  senderDisplayName: string;
  replyTo: Quote | null;
}

export interface PostOptions {
  body: string;
  senderId?: string;
  senderDisplayName?: string;
  senderKind?: string;
  replyToMessageId?: string | undefined;
}

// The quote bound, restated rather than imported from the module under
// proof: this double stands in for `BnestApp.FamilyChat`'s server-side
// truncation, and a double that called the browser's own copy of the rule
// could never disagree with it.
const PREVIEW_BUDGET = 160;

function serverPreview(body: string): string {
  const collapsed = body.replace(/\s+/gu, " ").trim();
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  const graphemes = [...segmenter.segment(collapsed)];
  if (graphemes.length <= PREVIEW_BUDGET) return collapsed;
  const kept = graphemes
    .slice(0, PREVIEW_BUDGET)
    .map((part) => part.segment)
    .join("");
  return `${kept}…`;
}

export interface HarnessServer {
  post: (options: PostOptions) => HarnessMessage;
  byId: (id: string) => HarnessMessage | undefined;
  newest: () => HarnessMessage | undefined;
}

interface TransportMessage {
  clientMessageId: string;
  body: string;
  replyToMessageId?: string;
}

interface HarnessTransport {
  transport: (message: TransportMessage) => Promise<unknown>;
}

type PageSource = ReturnType<typeof createTestPageSource>;

function createServer(
  pageSource: PageSource,
  visitor: { id: string; displayName: string },
  connection: { online: boolean },
): HarnessServer & HarnessTransport {
  let nextId = 1000;
  const byId = new Map<string, HarnessMessage>();
  let newest: HarnessMessage | undefined;

  function post(options: PostOptions): HarnessMessage {
    nextId += 1;
    const quoted =
      options.replyToMessageId === undefined
        ? undefined
        : byId.get(options.replyToMessageId);
    const message: HarnessMessage = {
      id: String(nextId),
      body: options.body,
      senderId:
        options.senderId === "self"
          ? visitor.id
          : (options.senderId ?? visitor.id),
      senderKind: options.senderKind ?? "user",
      senderDisplayName: options.senderDisplayName ?? visitor.displayName,
      replyTo: quoted
        ? {
            id: quoted.id,
            senderKind: quoted.senderKind,
            senderDisplayName: quoted.senderDisplayName,
            bodyPreview: serverPreview(quoted.body),
          }
        : null,
    };
    byId.set(message.id, message);
    newest = message;
    pageSource.append([message as never]);
    return message;
  }

  return {
    post,
    byId: (id) => byId.get(id),
    newest: () => newest,
    // The outbox's only way to the "server": the same result shape
    // `createRealTransport` returns, so a committed reply carries the quote
    // the resolver would have built for it.
    // Settles on a macrotask, never within the turn that called it -- the
    // same reason `createTestTransport` resolves on a timer: `wireComposer`
    // registers its status watcher *after* awaiting the submit, so a
    // transport that resolved in the same turn would reach "Sent" with
    // nobody listening and the pending row would never be reconciled. A
    // real network response never arrives that fast either.
    async transport({ clientMessageId, body, replyToMessageId }) {
      await new Promise((resolve) => setTimeout(resolve, 0));
      if (!connection.online) return { ok: false, retryable: true };
      const committed = post({ body, replyToMessageId });
      return { ok: true, message: { ...committed, clientMessageId } };
    },
  };
}

export interface ClipboardDouble {
  writes: string[];
  refuse: boolean;
}

export interface PersistenceDouble {
  rows: Map<string, Record<string, unknown>>;
  loadAll: (namespace: string) => Promise<Record<string, unknown>[]>;
  save: (namespace: string, message: Record<string, unknown>) => void;
  remove: (namespace: string, clientMessageId: string) => void;
  clear: (namespace: string) => void;
}

/**
 * The write-through double `resolvePersistence` hydrates from on every
 * open. Unlike `family_chat.steps.ts`'s own fake it keeps the whole queued
 * record, because the reply scenarios are about a field that record either
 * carries or does not.
 */
function createPersistence(): PersistenceDouble {
  const rows = new Map<string, Record<string, unknown>>();
  return {
    rows,
    async loadAll() {
      await Promise.resolve();
      return [...rows.values()].map((row) => ({ ...row }));
    },
    save(_namespace, message) {
      rows.set(message["clientMessageId"] as string, { ...message });
    },
    remove(_namespace, clientMessageId) {
      rows.delete(clientMessageId);
    },
    clear() {
      rows.clear();
    },
  };
}

export interface BrowserRoom {
  elements: FamilyChatElements;
  clock: FakeClock;
  clipboard: ClipboardDouble;
  persistence: PersistenceDouble;
  server: HarnessServer;
  pageSource: PageSource;
  room: Record<string, unknown>;
  visitor: { id: string; displayName: string };
  scrolledTo: string[];
  fetchCalls: { count: number };
  connection: { online: boolean };
  announcement: () => string;
  /** What a sighted reader is shown, as opposed to what is announced. */
  visibleRemediation: () => string;
}

interface SavedGlobal {
  key: string;
  present: boolean;
  value: unknown;
}

function installGlobals(win: Window, clipboard: ClipboardDouble): () => void {
  const source = win as unknown as Record<string, unknown>;
  const target = globalThis as unknown as Record<string, unknown>;
  const saved: SavedGlobal[] = [];

  function define(key: string, value: unknown): void {
    saved.push({ key, present: key in target, value: target[key] });
    Object.defineProperty(globalThis, key, {
      value,
      configurable: true,
      writable: true,
    });
  }

  for (const key of GLOBAL_KEYS) define(key, source[key]);
  define("navigator", {
    onLine: true,
    clipboard: {
      writeText: async (text: string): Promise<void> => {
        await Promise.resolve();
        if (clipboard.refuse) throw new Error("clipboard write refused");
        clipboard.writes.push(text);
      },
    },
  });

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

/**
 * happy-dom has no layout, so `scrollIntoView` is a no-op there. Recording
 * which element it was called on is the only observation of "the history
 * scrolled to it" available without a browser; whether the message is then
 * genuinely on screen is FE_E2E's `toBeInViewport`.
 */
function recordScrolls(win: Window, into: string[]): void {
  const prototype = (
    win as unknown as { HTMLElement: { prototype: Record<string, unknown> } }
  ).HTMLElement.prototype;
  prototype["scrollIntoView"] = function scrollIntoView(
    this: HTMLElement,
  ): void {
    into.push(this.dataset["messageId"] ?? "");
  };
}

function createReadStorage(): {
  getItem: (key: string) => string | null;
  setItem: (key: string, value: string) => void;
  removeItem: (key: string) => void;
} {
  const rows = new Map<string, string>();
  return {
    getItem: (key) => rows.get(key) ?? null,
    setItem: (key, value) => void rows.set(key, value),
    removeItem: (key) => void rows.delete(key),
  };
}

interface RoomConfig {
  visitor: { id: string; displayName: string };
  pageSource: PageSource;
  server: HarnessServer & HarnessTransport;
  persistence: PersistenceDouble;
  clipboard: ClipboardDouble;
  connection: { online: boolean };
  replies: boolean;
}

let active: {
  room: BrowserRoom;
  restore: () => void;
  config: RoomConfig;
} | null = null;

let visitorSequence = 0;

async function build(config: RoomConfig): Promise<BrowserRoom> {
  const win = new Window({
    url: `https://bnest.test/family-chat/${ROOM_SLUG}`,
  });
  const restore = installGlobals(win, config.clipboard);
  try {
    return await assemble(config, win, restore);
  } catch (error) {
    // A half-built room must not leave a `document` on `globalThis`: the
    // next scenario would silently open `initRoom`'s browser branch.
    restore();
    throw error;
  }
}

async function assemble(
  config: RoomConfig,
  win: Window,
  restore: () => void,
): Promise<BrowserRoom> {
  const scrolledTo: string[] = [];
  recordScrolls(win, scrolledTo);
  document.body.innerHTML = SHELL;

  const elements = findElements();
  const clock = createFakeClock();
  const fetchCalls = { count: 0 };
  const fetchPage: PageSource["fetchPage"] = (cursor) => {
    fetchCalls.count += 1;
    return config.pageSource.fetchPage(cursor);
  };

  const store = createRealStore({
    roomSlug: ROOM_SLUG,
    elements,
    currentUserId: config.visitor.id,
  });
  const replyTarget = createReplyTarget({
    announce: (message: string) => {
      elements.liveRegion.textContent = message;
    },
  });
  // The same order `initRoom` uses: hydrate the queue from storage before
  // constructing the outbox, so its own `resumeOnOpen` sees what a closed
  // tab left behind.
  const persistence = await resolvePersistence(
    true,
    config.visitor.id,
    ROOM_SLUG,
    config.persistence as never,
  );
  const outbox = createOutbox({
    userId: config.visitor.id,
    roomSlug: ROOM_SLUG,
    clock: clock as never,
    transport: config.server.transport as never,
    persistence: persistence as never,
  });
  if (!config.connection.online) outbox.reportBrowserEvent("offline");

  const history = createHistory({
    fetchPage,
    store,
    readMarker: createReadMarker({
      userId: config.visitor.id,
      roomSlug: ROOM_SLUG,
      storage: createReadStorage(),
    }),
  });
  const composerState: { remediationMessage: string | null } = {
    remediationMessage: null,
  };
  const composer = createComposer({
    outbox,
    state: composerState,
    focused: false,
    replyTarget,
    onQueued: (message: { clientMessageId: string; body: string }) =>
      store.renderPending({
        ...message,
        senderKind: "user",
        senderDisplayName: config.visitor.displayName,
        status: outbox.status(message.clientMessageId),
      } as never),
  });

  const room: Record<string, unknown> = {
    roomSlug: ROOM_SLUG,
    userId: config.visitor.id,
    clock,
    outbox,
    store,
    history,
    composer,
    replyTarget,
    reconnect: createReconnect({ clock: clock as never, socketClient: null }),
    replies: config.replies,
  };

  // Exactly the bindings `mount_browser.js` attaches for a reply-enabled
  // room, in the same order, minus the push/socket/scroll wiring no reply
  // scenario exercises.
  wireComposer(room as never, elements);
  if (config.replies) {
    wireMessageActions(room as never, elements, clock as never);
    wireReplyStrip(room as never, elements);
    wireQuoteJump(room as never, elements);
  }

  await history.loadInitial();
  elements.input.disabled = false;
  elements.send.disabled = false;

  const opened: BrowserRoom = {
    elements,
    clock,
    clipboard: config.clipboard,
    persistence: config.persistence,
    server: config.server,
    pageSource: config.pageSource,
    room,
    visitor: config.visitor,
    scrolledTo,
    fetchCalls,
    connection: config.connection,
    announcement: () => elements.liveRegion.textContent ?? "",
    visibleRemediation: () =>
      elements.remediation.hidden
        ? ""
        : (elements.remediation.textContent ?? ""),
  };
  active = { room: opened, restore, config };
  return opened;
}

/**
 * Opens the room. `seed` is the conversation the server already holds when
 * the visitor arrives; `replies` gates exactly what `mount_browser.js` gates
 * with it, so a scenario can open the room with the feature off.
 */
export async function openBrowserRoom(
  options: { seed?: PostOptions[]; replies?: boolean } = {},
): Promise<BrowserRoom> {
  closeBrowserRoom();

  visitorSequence += 1;
  // A distinct synthetic identity per scenario (never a production user):
  // `outbox.js` keys its queue namespace by user and room, so scenarios
  // sharing one identity would inherit each other's queued messages.
  const visitor = {
    id: `test-user-family-chat-reply-${visitorSequence}`,
    displayName: "You",
  };
  const pageSource = createTestPageSource([]);
  const connection = { online: true };
  const server = createServer(pageSource, visitor, connection);
  const config: RoomConfig = {
    visitor,
    pageSource,
    server,
    persistence: createPersistence(),
    clipboard: { writes: [], refuse: false },
    connection,
    replies: options.replies ?? true,
  };
  for (const seeded of options.seed ?? []) server.post(seeded);
  return build(config);
}

/**
 * What a reload is: the same server, the same device storage, the same
 * identity, and a brand new JS process. Every in-memory collaborator is
 * rebuilt, so anything that survives did so through the queue's own
 * persistence rather than a variable that happened to still be in scope.
 */
export async function reopenBrowserRoom(
  options: { offline?: boolean } = {},
): Promise<BrowserRoom> {
  if (!active) throw new Error("no browser-shaped room to reopen");
  const { config, restore } = active;
  active = null;
  restore();
  if (options.offline !== undefined)
    config.connection.online = !options.offline;
  return build(config);
}

export function currentBrowserRoom(): BrowserRoom {
  if (!active) {
    throw new Error("no browser-shaped room is open in this scenario");
  }
  return active.room;
}

export function hasBrowserRoom(): boolean {
  return active !== null;
}

export function closeBrowserRoom(): void {
  if (!active) return;
  const { restore } = active;
  active = null;
  restore();
}
