// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/app.js`: the bundle entry that wires
// every hook, persistence event, and the LiveSocket. Sockets, the colocated
// hooks, and topbar are doubles; the entry's own wiring runs for real.

import { afterEach, describe, expect, it, vi } from "vitest";

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

function liveParams(): () => Record<string, unknown> {
  const last = doubles.constructed[doubles.constructed.length - 1] as unknown[];
  const options = last?.[2] as { params?: () => Record<string, unknown> };
  if (typeof options?.params !== "function") throw new Error("no live params");
  return options.params;
}

describe("app bundle entry", () => {
  it("wires hooks, persistence, and the live socket", async () => {
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
    document.documentElement.dataset["browserPersistence"] = "true";
    Object.defineProperty(window.navigator, "serviceWorker", {
      configurable: true,
      value: { register: vi.fn(async () => {}) },
    });
    vi.stubEnv("NODE_ENV", "development");
    try {
      await import("../../js/app.js");

      const liveSocket = (window as unknown as { liveSocket: object })
        .liveSocket;
      expect(liveSocket).toBeDefined();
      expect(doubles.connected).toHaveLength(1);

      expect(liveParams()()["chat"]).toBe("");
      expect(liveParams()()["sifat_allah"]).toBe("");

      const throwing = () => {
        throw new Error("denied");
      };
      const realSession = window.sessionStorage;
      const realLocal = window.localStorage;
      Object.defineProperty(window, "sessionStorage", {
        configurable: true,
        value: { getItem: throwing, setItem: () => {}, removeItem: () => {} },
      });
      Object.defineProperty(window, "localStorage", {
        configurable: true,
        value: { getItem: throwing, setItem: () => {}, removeItem: () => {} },
      });
      try {
        expect(liveParams()()["chat"]).toBe("");
        expect(liveParams()()["sifat_allah"]).toBe("");
      } finally {
        Object.defineProperty(window, "sessionStorage", {
          configurable: true,
          value: realSession,
        });
        Object.defineProperty(window, "localStorage", {
          configurable: true,
          value: realLocal,
        });
      }

      window.dispatchEvent(
        new CustomEvent("phx:persist-chat", { detail: { hello: 1 } }),
      );
      window.dispatchEvent(new Event("phx:persist-chat"));
      window.dispatchEvent(new CustomEvent("phx:clear-chat-storage"));
      window.dispatchEvent(
        new CustomEvent("phx:persist-sifat-allah", { detail: {} }),
      );
      window.dispatchEvent(new Event("phx:persist-sifat-allah"));
      window.dispatchEvent(new CustomEvent("phx:sifat-celebrate"));
      window.dispatchEvent(
        new CustomEvent("phx:page-loading-start", { detail: {} }),
      );
      window.dispatchEvent(
        new CustomEvent("phx:page-loading-stop", { detail: {} }),
      );
      expect(doubles.topbar.show).toHaveBeenCalled();
      expect(doubles.topbar.hide).toHaveBeenCalled();

      window.dispatchEvent(new Event("load"));
      await new Promise((resolve) => setTimeout(resolve, 10));

      const reloader = {
        enableServerLogs: vi.fn(),
        openEditorAtCaller: vi.fn(),
        openEditorAtDef: vi.fn(),
      };
      window.dispatchEvent(
        new CustomEvent("phx:live_reload:attached", { detail: reloader }),
      );
      expect(reloader.enableServerLogs).toHaveBeenCalledOnce();
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "c" }));
      window.dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
      window.dispatchEvent(new KeyboardEvent("keyup", { key: "c" }));
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "d" }));
      window.dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
      expect(reloader.openEditorAtCaller).toHaveBeenCalled();
      expect(reloader.openEditorAtDef).toHaveBeenCalled();
      expect(
        (window as unknown as { liveReloader: unknown }).liveReloader,
      ).toBe(reloader);
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it("refuses to boot without a CSRF token", async () => {
    vi.resetModules();
    document.head.innerHTML = "";
    await expect(import("../../js/app.js")).rejects.toThrow(
      "Missing CSRF token",
    );
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
  });

  it("reads no browser storage when persistence is disabled", async () => {
    vi.resetModules();
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
    delete document.documentElement.dataset["browserPersistence"];
    await import("../../js/app.js");

    expect(liveParams()()["chat"]).toBe("");
    expect(liveParams()()["sifat_allah"]).toBe("");
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});
