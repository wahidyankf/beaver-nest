// @vitest-environment happy-dom
// ADR 004, Decision 3: engine.js is the module the page imports. It holds no Mermaid code. In the page, `loadEngine()`
// starts the engine in a hidden frame and keeps the engine once a start succeeds; a start that fails removes its
// frame, and the next call starts a new one. In the frame it imports engine_core.js and gives it to the frame's host.
// The frame and the core are fakes here; Chromium runs the real pair in the end-to-end suite.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const frame = vi.hoisted(() => ({
  loadEngineInFrame: vi.fn(),
}));
const core = vi.hoisted(() => ({
  renderDiagram: vi.fn(),
  DiagramError: class DiagramError extends Error {},
}));

vi.mock("../../../js/diagrams/diagram_frame.js", async (importOriginal) => ({
  ...(await importOriginal<
    typeof import("../../../js/diagrams/diagram_frame.js")
  >()),
  loadEngineInFrame: frame.loadEngineInFrame,
}));
vi.mock("../../../js/diagrams/engine_core.js", () => core);

const frameElementBefore = Object.getOwnPropertyDescriptor(
  globalThis,
  "frameElement",
);

/** Imports a fresh engine.js while the global `frameElement` is the given value, as a script in that realm sees it. */
async function importEngine(owner: unknown) {
  Object.defineProperty(globalThis, "frameElement", {
    value: owner,
    configurable: true,
  });
  vi.resetModules();
  return import("../../../js/diagrams/engine.js");
}

/** The API a frame hands over: an object with the engine's `renderDiagram`. */
function frameApi(renderDiagram = vi.fn()) {
  return { renderDiagram };
}

describe("engine.js in the page", () => {
  beforeEach(() => {
    frame.loadEngineInFrame.mockReset();
    core.renderDiagram.mockReset();
  });

  afterEach(() => {
    if (frameElementBefore)
      Object.defineProperty(globalThis, "frameElement", frameElementBefore);
    else Reflect.deleteProperty(globalThis, "frameElement");
  });

  it("exports ENGINE_API 1, which the browser module checks before use", async () => {
    const engine = await importEngine(null);

    expect(engine.ENGINE_API).toBe(1);
  });

  it("starts no frame when the module is imported, so a page without a diagram starts nothing", async () => {
    await importEngine(null);

    expect(frame.loadEngineInFrame).not.toHaveBeenCalled();
  });

  it("loads its own address in a frame, and resolves with the frame's engine", async () => {
    const api = frameApi();
    frame.loadEngineInFrame.mockResolvedValue(api);
    const engine = await importEngine(null);

    await expect(engine.loadEngine()).resolves.toBe(api);

    expect(frame.loadEngineInFrame).toHaveBeenCalledTimes(1);
    const [doc, address] = frame.loadEngineInFrame.mock.calls[0] ?? [];
    expect(doc).toBe(document);
    expect(address).toMatch(/\/engine\.js$/u);
  });

  it("forwards each draw to the frame's engine and returns its result", async () => {
    const framed = vi.fn().mockResolvedValue({ svg: "<svg></svg>" });
    frame.loadEngineInFrame.mockResolvedValue(frameApi(framed));
    const engine = await importEngine(null);

    const loaded = await engine.loadEngine();
    const result = await loaded.renderDiagram("flowchart TD\n  A --> B", {
      background: "red",
    });

    expect(result).toStrictEqual({ svg: "<svg></svg>" });
    expect(framed).toHaveBeenCalledWith("flowchart TD\n  A --> B", {
      background: "red",
    });
  });

  it("starts a second frame after a failed first start, so a later draw can succeed", async () => {
    const api = frameApi();
    frame.loadEngineInFrame
      .mockRejectedValueOnce(new Error("the engine chunk failed"))
      .mockResolvedValueOnce(api);
    const engine = await importEngine(null);

    await expect(engine.loadEngine()).rejects.toThrow("chunk failed");
    await expect(engine.loadEngine()).resolves.toBe(api);

    expect(frame.loadEngineInFrame).toHaveBeenCalledTimes(2);
  });

  it("keeps a successful engine, so a later call starts no frame", async () => {
    frame.loadEngineInFrame.mockResolvedValue(frameApi());
    const engine = await importEngine(null);

    await engine.loadEngine();
    await engine.loadEngine();

    expect(frame.loadEngineInFrame).toHaveBeenCalledTimes(1);
  });

  it("shares one attempt among calls made while it is starting", async () => {
    let finish: (api: unknown) => void = () => undefined;
    frame.loadEngineInFrame.mockReturnValue(
      new Promise((resolve) => (finish = resolve)),
    );
    const engine = await importEngine(null);

    const first = engine.loadEngine();
    const second = engine.loadEngine();
    finish(frameApi());

    await expect(Promise.all([first, second])).resolves.toHaveLength(2);
    expect(frame.loadEngineInFrame).toHaveBeenCalledTimes(1);
  });

  it("hands the frame a check that accepts only an object with renderDiagram", async () => {
    frame.loadEngineInFrame.mockResolvedValue(frameApi());
    const engine = await importEngine(null);
    await engine.loadEngine();

    const accept = frame.loadEngineInFrame.mock.calls[0]?.[3] as (
      value: unknown,
    ) => boolean;
    expect(accept(frameApi())).toBe(true);
    expect(accept({ renderDiagram: "not a function" })).toBe(false);
    expect(accept(null)).toBe(false);
  });

  it("treats a frame element of the embedding page without a host as the page", async () => {
    frame.loadEngineInFrame.mockResolvedValue(frameApi());
    const engine = await importEngine({});

    await engine.loadEngine();

    expect(frame.loadEngineInFrame).toHaveBeenCalledTimes(1);
  });
});

describe("engine.js in the frame", () => {
  beforeEach(() => {
    frame.loadEngineInFrame.mockReset();
  });

  afterEach(() => {
    if (frameElementBefore)
      Object.defineProperty(globalThis, "frameElement", frameElementBefore);
    else Reflect.deleteProperty(globalThis, "frameElement");
  });

  it("gives the core to the frame's host and loads no further frame", async () => {
    const host = { resolve: vi.fn(), reject: vi.fn() };

    await importEngine({ bnestEngineHost: host });

    // The core is handed over once its import settles, which is after the module has evaluated.
    await vi.waitFor(() => expect(host.resolve).toHaveBeenCalledTimes(1));
    expect(host.resolve).toHaveBeenCalledWith(
      expect.objectContaining({ renderDiagram: core.renderDiagram }),
    );
    expect(host.reject).not.toHaveBeenCalled();
    expect(frame.loadEngineInFrame).not.toHaveBeenCalled();
  });

  it("tells the frame's host when the core cannot load, and does not fail its own module", async () => {
    const host = { resolve: vi.fn(), reject: vi.fn() };
    vi.doMock("../../../js/diagrams/engine_core.js", () => {
      throw new Error("chunk request aborted");
    });

    try {
      // A failed module here would stay in the module map for the frame's life; the host is the one to hear of it.
      await expect(
        importEngine({ bnestEngineHost: host }),
      ).resolves.toBeDefined();
    } finally {
      vi.doMock("../../../js/diagrams/engine_core.js", () => core);
    }

    await vi.waitFor(() => expect(host.reject).toHaveBeenCalledTimes(1));
    expect(host.reject.mock.calls[0]?.[0]).toBeInstanceOf(Error);
    expect(host.resolve).not.toHaveBeenCalled();
  });
});
