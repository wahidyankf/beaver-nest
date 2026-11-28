// @vitest-environment happy-dom
//
// Unit coverage for the reconnect recovery behind the ten-visitor scenario:
// every visitor's draft reaches the browser store through the production
// `phx:persist-chat` wiring in `js/app.js`, and the reconnecting LiveSocket
// reads exactly that snapshot back through its `params`. Each visitor owns an
// isolated session store, the way a browser context owns one, so one
// visitor's reconnect can never pick up another visitor's draft.

import { beforeAll, describe, expect, it, vi } from "vitest";

const doubles = vi.hoisted(() => {
  const constructed: unknown[] = [];
  const connected: unknown[] = [];
  return {
    constructed,
    connected,
    Socket: class {
      constructor(...args: unknown[]) {
        constructed.push(args);
      }
    },
    LiveSocket: class {
      readonly args: unknown[];
      constructor(...args: unknown[]) {
        this.args = args;
        constructed.push(args);
      }
      connect(): void {
        connected.push(this);
      }
    },
    colocatedHooks: {},
    topbar: { config: vi.fn(), show: vi.fn(), hide: vi.fn() },
  };
});

vi.mock("phoenix", () => ({ Socket: doubles.Socket }));
vi.mock("phoenix_html", () => ({}));
vi.mock("phoenix_live_view", () => ({ LiveSocket: doubles.LiveSocket }));
vi.mock("phoenix-colocated/bnest_app", () => ({
  hooks: doubles.colocatedHooks,
}));
vi.mock("../../vendor/topbar", () => ({ default: doubles.topbar }));

interface Snapshot {
  route: string;
  draft: string;
  group: number;
  transcript: string[];
}

/** One visitor's session store: a Map behind the Storage surface. */
function visitorStore() {
  const backing = new Map<string, string>();
  return {
    getItem: (key: string): string | null => backing.get(key) ?? null,
    setItem: (key: string, value: string): void => {
      backing.set(key, value);
    },
    removeItem: (key: string): void => {
      backing.delete(key);
    },
  };
}

function installStore(store: ReturnType<typeof visitorStore>): void {
  Object.defineProperty(window, "sessionStorage", {
    configurable: true,
    value: store,
  });
}

function reconnectParams(): Record<string, unknown> {
  const last = doubles.constructed[doubles.constructed.length - 1] as unknown[];
  const options = last?.[2] as { params?: () => Record<string, unknown> };
  if (typeof options?.params !== "function")
    throw new Error("the LiveSocket has no reconnect params");
  return options.params();
}

function persist(snapshot: Snapshot): void {
  window.dispatchEvent(
    new CustomEvent("phx:persist-chat", { detail: snapshot }),
  );
}

function reconnectedSnapshot(): Snapshot {
  const raw = reconnectParams()["chat"];
  expect(typeof raw, "the reconnect carries no chat snapshot").toBe("string");
  return JSON.parse(raw as string) as Snapshot;
}

const VISITOR_COUNT = 10;
const GROUP_COUNT = 3;
const ROUTE = "/chat";

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Ten synthetic visitors preserve recoverable state across three groups
describe("ten recovery-group visitors keep their route and draft", () => {
  beforeAll(async () => {
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
    document.documentElement.dataset["browserPersistence"] = "true";
    await import("../../js/app.js");
    expect(doubles.connected).toHaveLength(1);
  });

  it("recovers every visitor's own draft on its own route after a deployment", () => {
    const stores = new Map<number, ReturnType<typeof visitorStore>>();
    const snapshots = new Map<number, Snapshot>();

    for (let index = 0; index < VISITOR_COUNT; index += 1) {
      const store = visitorStore();
      const snapshot: Snapshot = {
        route: ROUTE,
        draft: `Recovery draft ${index + 1}`,
        group: (index % GROUP_COUNT) + 1,
        transcript: [`Acknowledged exchange ${index + 1}`],
      };
      installStore(store);
      persist(snapshot);
      stores.set(index, store);
      snapshots.set(index, snapshot);
    }

    const sent = [...snapshots.values()];
    expect(new Set(sent.map((s) => s.group)).size).toBe(GROUP_COUNT);
    expect(new Set(sent.map((s) => s.draft)).size).toBe(VISITOR_COUNT);

    // The deployment: every visitor reconnects, each against its own store.
    for (let index = 0; index < VISITOR_COUNT; index += 1) {
      const store = stores.get(index);
      const expected = snapshots.get(index);
      if (!store || !expected)
        throw new Error(`visitor ${index + 1} was not prepared`);
      installStore(store);
      const recovered = reconnectedSnapshot();
      expect(recovered, `visitor ${index + 1} lost its snapshot`).toEqual(
        expected,
      );
      expect(recovered.route, `visitor ${index + 1} left its route`).toBe(
        ROUTE,
      );
      expect(recovered.draft, `visitor ${index + 1} lost its draft`).toBe(
        expected.draft,
      );
    }
  });
});
