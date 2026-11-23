// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/browser_import.js`: the hook reports the
// browser sources on mount and removes only known keys the server accepts.

import { afterEach, describe, expect, it, vi } from "vitest";
import { BrowserImport } from "../../js/browser_import.js";

interface Hook {
  pushEvent: (event: string, payload: unknown) => void;
  handleEvent: (event: string, cb: (payload: never) => void) => void;
}

function mounted(storage: Record<string, string>): {
  pushed: Array<{ event: string; payload: unknown }>;
  handlers: Record<string, (payload: never) => void>;
} {
  const pushed: Array<{ event: string; payload: unknown }> = [];
  const handlers: Record<string, (payload: never) => void> = {};
  const hook: Hook = {
    pushEvent: (event, payload) => {
      pushed.push({ event, payload });
    },
    handleEvent: (event, cb) => {
      handlers[event] = cb;
    },
  };
  window.sessionStorage.clear();
  window.localStorage.clear();
  for (const [key, value] of Object.entries(storage)) {
    if (key.startsWith("session:")) {
      window.sessionStorage.setItem(key.slice("session:".length), value);
    } else {
      window.localStorage.setItem(key, value);
    }
  }
  const onMount = BrowserImport.mounted as unknown as
    ((this: Hook) => void) | undefined;
  if (!onMount) throw new Error("no mounted hook");
  onMount.call(hook);
  return { pushed, handlers };
}

afterEach(() => {
  window.sessionStorage.clear();
  window.localStorage.clear();
  vi.unstubAllGlobals();
});

describe("BrowserImport", () => {
  it("reports every source with its presence on mount", () => {
    const { pushed } = mounted({
      "session:bnest.chat.v1": "{}",
      "phx:theme": "dark",
    });

    expect(pushed).toHaveLength(1);
    expect(pushed[0]?.event).toBe("browser-sources");
    const sources = (
      pushed[0]?.payload as {
        sources: Array<{ storageKey: string; present: boolean }>;
      }
    ).sources;
    expect(sources.map((s) => [s.storageKey, s.present])).toEqual([
      ["bnest.chat.v1", true],
      ["bnest.sifat-allah.v1", false],
      ["phx:theme", true],
    ]);
  });

  it("removes an accepted key and ignores unknown or malformed payloads", () => {
    window.localStorage.setItem("phx:theme", "dark");
    const { handlers } = mounted({});
    const accept = handlers["imports-accepted"];
    if (!accept) throw new Error("no imports-accepted handler");

    accept({ storageKeys: ["phx:theme", "unknown-key", 42] } as never);
    expect(window.localStorage.getItem("phx:theme")).toBeNull();

    expect(() => accept({} as never)).not.toThrow();
    expect(() => accept({ storageKeys: "phx:theme" } as never)).not.toThrow();
  });

  it("reports a missing source as absent when storage throws", () => {
    const entries = new Map<string, string>();
    const calls: string[] = [];
    vi.stubGlobal("sessionStorage", {
      getItem: (key: string) => {
        calls.push(key);
        throw new Error("denied");
      },
      setItem: (key: string, value: string) => {
        entries.set(key, value);
      },
      removeItem: (key: string) => {
        entries.delete(key);
      },
      clear: () => {
        entries.clear();
      },
      key: (index: number) => [...entries.keys()][index] ?? null,
      get length() {
        return entries.size;
      },
    });
    try {
      const { pushed } = mounted({});
      const sources = (
        pushed[0]?.payload as { sources: Array<{ present: boolean }> }
      ).sources;
      expect(calls).toEqual(["bnest.chat.v1"]);
      expect(sources[0]?.present).toBe(false);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
