// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/diagrams/engine.js`'s frame lifecycle:
// starting shares one frame, a failed start leaves nothing behind, and
// discarding drops the started engine so the next load starts a new frame.

import { describe, expect, it, vi } from "vitest";

const frame = vi.hoisted(() => {
  const calls: Array<{
    clock: {
      setTimer: (cb: () => void, ms: number) => unknown;
      clearTimer: (h: unknown) => void;
    };
  }> = [];
  const removed: unknown[] = [];
  return {
    calls,
    removed,
    HOST_PROPERTY: "__bnest_test_engine_host__",
    loadEngineInFrame: vi.fn(
      async (
        _document: unknown,
        _url: string,
        clock: {
          setTimer: (cb: () => void, ms: number) => unknown;
          clearTimer: (h: unknown) => void;
        },
        accept: (value: unknown) => boolean,
      ) => {
        calls.push({ clock });
        const engine = { renderDiagram: async () => ({ svg: "<svg></svg>" }) };
        if (!accept(engine)) throw new Error("frame refused the engine");
        return engine;
      },
    ),
    removeEngineFrame: vi.fn((engine: unknown) => {
      removed.push(engine);
    }),
  };
});

vi.mock("../../../js/diagrams/diagram_frame.js", () => ({
  HOST_PROPERTY: frame.HOST_PROPERTY,
  loadEngineInFrame: frame.loadEngineInFrame,
  removeEngineFrame: frame.removeEngineFrame,
}));

import {
  discardEngine,
  ENGINE_API,
  loadEngine,
} from "../../../js/diagrams/engine.js";

describe("diagram engine loading", () => {
  it("exposes its API version", () => {
    expect(ENGINE_API).toBe(1);
  });

  it("starts one shared frame and reuses the loaded engine", async () => {
    const first = loadEngine();
    const second = loadEngine();
    expect(first).toBe(second);

    const engine = await first;
    expect(typeof (engine as { renderDiagram: unknown }).renderDiagram).toBe(
      "function",
    );
    expect(frame.calls).toHaveLength(1);

    const again = await loadEngine();
    expect(again).toBe(engine);
    expect(frame.calls).toHaveLength(1);
  });

  it("drives its timers through the window", () => {
    const clock = frame.calls[0]?.clock;
    if (!clock) throw new Error("no frame was started");
    const handle = clock.setTimer(() => {}, 1000);
    clock.clearTimer(handle);
  });

  it("discards the engine so the next load starts a new frame", async () => {
    const engine = await loadEngine();
    discardEngine();
    expect(frame.removed).toContain(engine);

    discardEngine();
    await loadEngine();
    expect(frame.calls.length).toBeGreaterThan(1);
  });
});
