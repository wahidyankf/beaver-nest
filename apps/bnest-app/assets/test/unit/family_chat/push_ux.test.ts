// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/push_ux.js`'s server calls:
// reading the current binding, subscribing through the real Push API, and
// disabling server-side first. Every browser API is a double.

import { afterEach, describe, expect, it, vi } from "vitest";
import {
  attemptPushDisable,
  attemptPushSubscribe,
  fetchCurrentSubscriptionActive,
} from "../../../js/family_chat/push_ux.js";

const CONFIG = {
  data: {
    webPushConfiguration: { available: true, publicKey: "BDd-test-public-key" },
  },
};

function requestFor(responses: Record<string, unknown>) {
  return async (query: string) => {
    if (query.includes("webPushConfiguration")) return CONFIG;
    if (query.includes("currentWebPushSubscription")) {
      return (
        responses["current"] ?? { data: { currentWebPushSubscription: null } }
      );
    }
    if (query.includes("upsertWebPushSubscription")) {
      return (
        responses["upsert"] ?? { data: { upsertWebPushSubscription: null } }
      );
    }
    if (query.includes("disableCurrentWebPushSubscription")) {
      return (
        responses["disable"] ?? {
          data: { disableCurrentWebPushSubscription: true },
        }
      );
    }
    throw new Error(`unexpected query: ${query}`);
  };
}

function deviceWith(subscribeResult: {
  endpoint: string;
  keys: Record<string, string>;
}) {
  const subscription = {
    endpoint: subscribeResult.endpoint,
    toJSON: () => ({ keys: subscribeResult.keys }),
    unsubscribe: vi.fn(async () => true),
  };
  const registration = {
    pushManager: {
      subscribe: vi.fn(async () => subscription),
      getSubscription: vi.fn(async () => subscription),
    },
  };
  Object.defineProperty(window.navigator, "serviceWorker", {
    configurable: true,
    value: { ready: Promise.resolve(registration) },
  });
  vi.stubGlobal("Notification", {
    requestPermission: vi.fn(async () => "granted"),
  });
  return { registration, subscription };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("fetchCurrentSubscriptionActive", () => {
  it("reports the server binding", async () => {
    const active = await fetchCurrentSubscriptionActive(
      requestFor({
        current: { data: { currentWebPushSubscription: { enabled: true } } },
      }),
    );
    expect(active).toBe(true);
  });

  it("reports false when the request fails", async () => {
    const active = await fetchCurrentSubscriptionActive(async () => {
      throw new Error("down");
    });
    expect(active).toBe(false);
  });
});

describe("attemptPushSubscribe", () => {
  it("binds an enabled subscription end to end", async () => {
    deviceWith({
      endpoint: "https://push.example/e1",
      keys: { p256dh: "p", auth: "a" },
    });
    const enabled = await attemptPushSubscribe(
      requestFor({
        upsert: { data: { upsertWebPushSubscription: { enabled: true } } },
      }),
    );
    expect(enabled).toBe(true);
  });

  it("refuses when the server offers no configuration", async () => {
    const enabled = await attemptPushSubscribe(async () => ({ data: {} }));
    expect(enabled).toBe(false);
  });

  it("refuses when permission is denied", async () => {
    deviceWith({
      endpoint: "https://push.example/e2",
      keys: { p256dh: "p", auth: "a" },
    });
    vi.stubGlobal("Notification", {
      requestPermission: vi.fn(async () => "denied"),
    });
    const enabled = await attemptPushSubscribe(requestFor({}));
    expect(enabled).toBe(false);
  });

  it("refuses when the subscription has no keys", async () => {
    deviceWith({ endpoint: "https://push.example/e3", keys: {} });
    const enabled = await attemptPushSubscribe(requestFor({}));
    expect(enabled).toBe(false);
  });
});

describe("attemptPushDisable", () => {
  it("disables server-side and unsubscribes locally", async () => {
    const { subscription } = deviceWith({
      endpoint: "https://push.example/e4",
      keys: { p256dh: "p", auth: "a" },
    });
    await attemptPushDisable(requestFor({}));
    expect(subscription.unsubscribe).toHaveBeenCalledOnce();
  });
});
