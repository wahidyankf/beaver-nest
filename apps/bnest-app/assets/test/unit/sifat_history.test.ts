// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/sifat_history.js`: the hook seeds a
// mission history entry on mount, pushes an active entry on demand, and goes
// back or to the dashboard on demand.

import { afterEach, describe, expect, it, vi } from "vitest";
import { SifatHistory } from "../../js/sifat_history.js";

interface Hook {
  pushEvent: (event: string, payload: unknown) => void;
  onHistoryEntry?: () => void;
  onHistoryBack?: () => void;
  onPopState?: (event: PopStateEvent) => void;
}

function mounted(): { hook: Hook; pushed: string[] } {
  const pushed: string[] = [];
  const hook: Hook = {
    pushEvent: (event) => {
      pushed.push(event);
    },
  };
  const onMount = SifatHistory.mounted as unknown as
    ((this: Hook) => void) | undefined;
  if (!onMount) throw new Error("no mounted hook");
  onMount.call(hook);
  return { hook, pushed };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("SifatHistory", () => {
  it("seeds a mission entry when none is present", () => {
    const replace = vi.fn();
    const state = window.history.state;
    Object.defineProperty(window.history, "state", {
      configurable: true,
      value: null,
    });
    window.history.replaceState =
      replace as unknown as typeof window.history.replaceState;
    try {
      mounted();
      expect(replace).toHaveBeenCalledOnce();
      expect(replace.mock.calls[0]?.[0]).toMatchObject({
        bnestSifatMode: "mission",
      });
    } finally {
      Object.defineProperty(window.history, "state", {
        configurable: true,
        value: state,
      });
    }
  });

  it("pushes an active entry and goes back from it, else to the dashboard", () => {
    const push = vi.fn();
    const back = vi.fn();
    window.history.pushState =
      push as unknown as typeof window.history.pushState;
    window.history.back = back as unknown as typeof window.history.back;
    const { hook, pushed } = mounted();

    hook.onHistoryEntry?.();
    expect(push).toHaveBeenCalledOnce();

    Object.defineProperty(window.history, "state", {
      configurable: true,
      value: { bnestSifatMode: "active" },
    });
    hook.onHistoryBack?.();
    expect(back).toHaveBeenCalledOnce();

    Object.defineProperty(window.history, "state", {
      configurable: true,
      value: null,
    });
    hook.onHistoryBack?.();
    expect(pushed).toEqual(["dashboard"]);
  });

  // @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: Browser Back returns a child from a quiz to the mission
  it("goes to the dashboard when a mission entry is popped", () => {
    const { hook, pushed } = mounted();
    hook.onPopState?.({
      state: { bnestSifatMode: "mission" },
    } as PopStateEvent);
    expect(pushed).toEqual(["dashboard"]);
    hook.onPopState?.({ state: null } as unknown as PopStateEvent);
    expect(pushed).toEqual(["dashboard"]);
  });

  it("removes its listeners when destroyed", () => {
    const remove = vi.spyOn(window, "removeEventListener");
    const { hook } = mounted();
    const onDestroy = SifatHistory.destroyed as unknown as
      ((this: Hook) => void) | undefined;
    if (!onDestroy) throw new Error("no destroyed hook");
    onDestroy.call(hook);
    const names = remove.mock.calls.map((call) => call[0]);
    expect(names).toEqual(
      expect.arrayContaining([
        "phx:sifat-history-entry",
        "phx:sifat-history-back",
        "popstate",
      ]),
    );
    remove.mockRestore();
  });
});
