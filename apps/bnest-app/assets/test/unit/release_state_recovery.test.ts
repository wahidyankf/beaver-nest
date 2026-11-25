// @vitest-environment happy-dom
//
// Unit coverage for the state recovery behind the compatible-release
// scenario: the acknowledged transcript and the unsent draft reach the
// browser store through the production `phx:persist-chat` wiring in
// `js/app.js`, and the LiveSocket a compatible release reconnects reads that
// same snapshot back through its `params`. Storage is wiped only by the
// explicit clear event, never by the reconnect itself.

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

const ACKNOWLEDGED_MESSAGE = "Acknowledged before rollout";
const ACKNOWLEDGED_REPLY = "Fixture response complete.";
const UNSENT_DRAFT = "Unsent draft before rollout";

function reconnectParams(): Record<string, unknown> {
  const last = doubles.constructed[doubles.constructed.length - 1] as unknown[];
  const options = last?.[2] as { params?: () => Record<string, unknown> };
  if (typeof options?.params !== "function")
    throw new Error("the LiveSocket has no reconnect params");
  return options.params();
}

function reconnectedChat(): {
  acknowledged: string;
  reply: string;
  draft: string;
} {
  const raw = reconnectParams()["chat"];
  expect(typeof raw, "the reconnect carries no chat snapshot").toBe("string");
  return JSON.parse(raw as string) as {
    acknowledged: string;
    reply: string;
    draft: string;
  };
}

// @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: A connected user keeps their state across a compatible release
describe("connected user state across a compatible release", () => {
  beforeAll(async () => {
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
    document.documentElement.dataset["browserPersistence"] = "true";
    await import("../../js/app.js");
    expect(doubles.connected).toHaveLength(1);
  });

  it("recovers the acknowledged state and the unsent draft on reconnect", () => {
    window.dispatchEvent(
      new CustomEvent("phx:persist-chat", {
        detail: {
          acknowledged: ACKNOWLEDGED_MESSAGE,
          reply: ACKNOWLEDGED_REPLY,
          draft: UNSENT_DRAFT,
        },
      }),
    );

    // The compatible release: the page is not refreshed, the LiveSocket
    // reconnects, and its params carry what the store still holds.
    const recovered = reconnectedChat();
    expect(recovered.acknowledged).toBe(ACKNOWLEDGED_MESSAGE);
    expect(recovered.reply).toBe(ACKNOWLEDGED_REPLY);
    expect(recovered.draft).toBe(UNSENT_DRAFT);
  });

  it("keeps the stored state until the server explicitly clears it", () => {
    window.dispatchEvent(
      new CustomEvent("phx:persist-chat", {
        detail: {
          acknowledged: ACKNOWLEDGED_MESSAGE,
          reply: ACKNOWLEDGED_REPLY,
          draft: UNSENT_DRAFT,
        },
      }),
    );
    expect(reconnectedChat().draft).toBe(UNSENT_DRAFT);

    window.dispatchEvent(new CustomEvent("phx:clear-chat-storage"));

    expect(reconnectParams()["chat"]).toBe("");
  });
});
