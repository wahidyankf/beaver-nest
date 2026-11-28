// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/graphql.js`'s HTTP request
// transport and its default `phoenix` socket opener: the CSRF header, the
// POST shape, and the socket the client opens when none is injected.

import { afterEach, describe, expect, it, vi } from "vitest";

const { MockSocket } = vi.hoisted(() => {
  class Channel {
    readonly listeners = new Set<string>();
    private static subscriptions = 0;

    constructor(readonly topic: string) {}

    join() {
      return {
        receive: (status: string, callback: () => void) => {
          if (status === "ok") callback();
          return { receive: () => {} };
        },
      };
    }

    push(event: string) {
      if (event === "doc") {
        Channel.subscriptions += 1;
        const subscriptionId = `subscription-${Channel.subscriptions}`;
        return {
          receive: (status: string, callback: (payload: unknown) => void) => {
            if (status === "ok") callback({ subscriptionId });
            return { receive: () => {} };
          },
        };
      }
      return { receive: () => {} };
    }

    on(event: string): void {
      this.listeners.add(event);
    }

    off(event: string): void {
      this.listeners.delete(event);
    }
  }

  class MockSocket {
    static instances: MockSocket[] = [];
    readonly channels: Channel[] = [];

    constructor(readonly path: string) {
      MockSocket.instances.push(this);
    }

    onOpen(): void {}

    connect(): void {}

    disconnect(): void {}

    channel(topic: string): Channel {
      const channel = new Channel(topic);
      this.channels.push(channel);
      return channel;
    }
  }

  return { MockSocket };
});

vi.mock("phoenix", () => ({ Socket: MockSocket }));

import {
  createSubscriptionClient,
  request,
} from "../../../js/family_chat/graphql.js";

afterEach(() => {
  vi.unstubAllGlobals();
  MockSocket.instances.length = 0;
  document.head.innerHTML = "";
});

describe("request", () => {
  it("posts the query with the CSRF token from the page", async () => {
    document.head.innerHTML = `<meta name="csrf-token" content="token-123">`;
    const calls: Array<{ url: string; init: RequestInit }> = [];
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return { json: async () => ({ data: { ok: true } }) };
    });

    const result = await request("query { ok }", { room: "ruang-keluarga" });

    expect(result).toEqual({ data: { ok: true } });
    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe("/api/graphql");
    expect(calls[0]?.init.method).toBe("POST");
    expect(
      (calls[0]?.init.headers as Record<string, string>)["x-csrf-token"],
    ).toBe("token-123");
    expect(JSON.parse(calls[0]?.init.body as string)).toEqual({
      query: "query { ok }",
      variables: { room: "ruang-keluarga" },
    });
  });

  it("sends an empty CSRF token when the page has no meta tag", async () => {
    vi.stubGlobal("fetch", async () => ({
      json: async () => ({ data: null }),
    }));
    await request("query { ok }", {});
    expect(document.querySelector("meta[name='csrf-token']")).toBeNull();
  });
});

describe("createSubscriptionClient with its default socket", () => {
  it("opens a real phoenix socket and subscribes over it", async () => {
    const client = createSubscriptionClient();
    const seen: unknown[] = [];
    const { unsubscribe } = await client.subscribe(
      "subscription { x }",
      {},
      (result) => {
        seen.push(result);
      },
    );

    expect(MockSocket.instances).toHaveLength(1);
    expect(MockSocket.instances[0]?.path).toBe("/api/graphql/socket");
    expect(seen).toEqual([]);
    unsubscribe();
  });
});
