// @vitest-environment happy-dom
// ADR 004, Decision 3: the engine runs in a hidden same-origin frame, so Mermaid draws in a document with none of
// the page's style sheets (60 edges took about 6 s in the page, because its `:has()` rules are matched again for
// every measurement). A real frame needs a browser; the end-to-end suite proves the draw. Here the frame is a
// stand-in whose document, load and script events are played by hand, to prove the steps the module takes.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  FRAME_POLICY,
  HOST_PROPERTY,
  loadEngineInFrame,
  removeEngineFrame,
} from "../../../js/diagrams/diagram_frame.js";
import { LIMITS } from "../../../js/diagrams/diagram_limits.js";

const ADDRESS = "/assets/js/diagrams/engine.js";

type Host = {
  resolve: (engine: unknown) => void;
  reject: (error: unknown) => void;
};

/** The timers of a load, as fakes: the callback of the one timer set is kept so a test can fire it. */
function fakeTimers() {
  const timers = {
    callback: null as (() => void) | null,
    cleared: [] as number[],
    setTimer: vi.fn((callback: () => void, _ms: number) => {
      timers.callback = callback;
      return 7;
    }),
    clearTimer: vi.fn((handle: number) => {
      timers.cleared.push(handle);
    }),
  };
  return timers;
}

/** A page whose frame the tests drive: happy-dom's own frame loading is replaced by a document made by hand. */
function startLoad(
  timers = fakeTimers(),
  accept: (api: unknown) => boolean = () => true,
) {
  // The frame's document is a stand-in with a detached head, so happy-dom does not try to fetch the script.
  const frameDoc = {
    createElement: (tag: string) => document.createElement(tag),
    head: document.createElement("head"),
  };
  const created = vi.spyOn(document, "createElement");
  const loaded = loadEngineInFrame(document, ADDRESS, timers, accept);
  const frame = created.mock.results
    .map((result) => result.value as Element)
    .find(
      (element): element is HTMLIFrameElement =>
        element instanceof HTMLIFrameElement,
    );
  created.mockRestore();
  if (frame === undefined) throw new Error("the module created no frame");
  Object.defineProperty(frame, "contentDocument", {
    value: frameDoc,
    configurable: true,
  });
  return { loaded, frame, frameDoc, timers };
}

function hostOf(frame: HTMLIFrameElement): Host {
  return Reflect.get(frame, HOST_PROPERTY) as Host;
}

describe("removeEngineFrame", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("removes the frame of a started engine, so a draw in it can no longer run", async () => {
    const { loaded, frame } = startLoad();
    const engine = { renderDiagram: () => undefined };
    hostOf(frame).resolve(engine);
    await loaded;
    expect(frame.isConnected).toBe(true);

    removeEngineFrame(engine);

    expect(frame.isConnected).toBe(false);
  });

  it("does nothing for a value no frame started", () => {
    expect(() => removeEngineFrame({})).not.toThrow();
  });
});

describe("loadEngineInFrame", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("puts one hidden, inert frame in standards mode in the body and nothing else", () => {
    const { frame } = startLoad();

    expect(document.body.children).toHaveLength(1);
    expect(document.body.firstElementChild).toBe(frame);
    expect(frame.getAttribute("aria-hidden")).toBe("true");
    expect(frame.getAttribute("tabindex")).toBe("-1");
    expect(frame.inert).toBe(true);
    expect(frame.getAttribute("style")).toContain("visibility:hidden");
    expect(frame.getAttribute("srcdoc")).toBe(
      "<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src data:\">",
    );
    expect(frame.hasAttribute("src")).toBe(false);
  });

  // ADR 004, Decision 3: a draw in the frame must not reach the network. The frame's own policy refuses every request
  // except the engine's script from this origin, and the picture's own data address, so a diagram that names an outside
  // picture or stylesheet cannot make the browser fetch it. The policy sits in the frame's first markup, before any script.
  it("gives the frame a policy that refuses every request but its own script and data pictures", () => {
    const { frame } = startLoad();
    const srcdoc = frame.getAttribute("srcdoc") ?? "";
    const policy =
      /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/u.exec(
        srcdoc,
      )?.[1];

    expect(policy).toBe(FRAME_POLICY);
    // The policy is the first markup after the doctype, so it is in force before the engine's script is appended.
    expect(
      srcdoc.startsWith(
        '<!doctype html><meta http-equiv="Content-Security-Policy"',
      ),
    ).toBe(true);
    expect(FRAME_POLICY.split(";").map((part) => part.trim())).toEqual([
      "default-src 'none'",
      "script-src 'self'",
      "style-src 'unsafe-inline'",
      "img-src data:",
    ]);
  });

  it("starts the timer with the engine start timeout, which is longer than a draw's timeout", () => {
    const { timers } = startLoad();

    expect(timers.setTimer).toHaveBeenCalledWith(
      expect.any(Function),
      LIMITS.engineStartTimeoutMs,
    );
    // The first start also fetches the engine's chunks (about 1.4 MB), so it may take longer than one draw.
    expect(LIMITS.engineStartTimeoutMs).toBeGreaterThan(LIMITS.renderTimeoutMs);
  });

  it("adds the module as a script with an absolute address when the frame has loaded", () => {
    const { frame, frameDoc } = startLoad();

    frame.dispatchEvent(new Event("load"));

    const script = frameDoc.head.querySelector("script");
    expect(script?.getAttribute("type")).toBe("module");
    expect(script?.getAttribute("src")).toBe(
      new URL(ADDRESS, document.baseURI).href,
    );
  });

  it("resolves to the API the module hands to the frame's host, and keeps the frame", async () => {
    const { loaded, frame, timers } = startLoad();
    frame.dispatchEvent(new Event("load"));
    const api = { renderDiagram: vi.fn() };

    hostOf(frame).resolve(api);

    await expect(loaded).resolves.toBe(api);
    expect(timers.cleared).toEqual([7]);
    expect(document.body.contains(frame)).toBe(true);
  });

  it("rejects with the error the module hands to the frame's host, and removes the frame", async () => {
    const { loaded, frame } = startLoad();
    const error = new Error("the engine chunk failed");

    hostOf(frame).reject(error);

    await expect(loaded).rejects.toBe(error);
    expect(document.body.contains(frame)).toBe(false);
  });

  it("rejects and removes the frame when the script fails to load", async () => {
    const { loaded, frame, frameDoc, timers } = startLoad();
    frame.dispatchEvent(new Event("load"));

    frameDoc.head.querySelector("script")?.dispatchEvent(new Event("error"));

    await expect(loaded).rejects.toThrow("did not load");
    expect(document.body.contains(frame)).toBe(false);
    expect(timers.cleared).toEqual([7]);
  });

  it("rejects and removes the frame when the frame has no document", async () => {
    const { loaded, frame } = startLoad();
    Object.defineProperty(frame, "contentDocument", { value: null });

    frame.dispatchEvent(new Event("load"));

    await expect(loaded).rejects.toThrow("no document");
    expect(document.body.contains(frame)).toBe(false);
  });

  it("rejects and removes the frame when the hand-over is not accepted, so a later start gets a new frame", async () => {
    const { loaded, frame, timers } = startLoad(fakeTimers(), () => false);

    hostOf(frame).resolve({ renderDiagram: "not a function" });

    await expect(loaded).rejects.toThrow("gave no engine");
    expect(document.body.contains(frame)).toBe(false);
    expect(timers.cleared).toEqual([7]);
  });

  it("rejects and removes the frame when the module does not start in time", async () => {
    const { loaded, frame, timers } = startLoad();

    timers.callback?.();

    await expect(loaded).rejects.toThrow("did not start");
    expect(document.body.contains(frame)).toBe(false);
  });
});
