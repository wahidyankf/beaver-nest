// ADR 004, Decision 3: the module the page imports on demand (`import(engineUrl)`), so it and its chunks cost
// nothing on a page without a diagram. It holds no Mermaid code itself. It runs in two places:
//
// - In the page, `loadEngine()` starts the engine in a hidden frame (diagram_frame.js). The frame loads this same
//   file, which imports engine_core.js (the only module that imports Mermaid) and hands it back. A start that fails
//   removes its frame and leaves no failure behind here: the next call starts a new frame.
// - In the frame, this module imports engine_core.js and gives it to the frame's host. It never throws at the top
//   level, so a failed core import is reported to the host and does not stay in the browser's module map.

import {
  HOST_PROPERTY,
  loadEngineInFrame,
  removeEngineFrame,
} from "./diagram_frame.js";

/** The engine API version. The browser module refuses any other value. */
export const ENGINE_API = 1;

/**
 * @typedef {{ renderDiagram: (source: string, themeVariables: Record<string, unknown>) => Promise<{ svg: string }> }} FrameEngine
 */

/**
 * @param {unknown} owner the `frameElement` of the realm this module runs in
 * @returns {{ resolve: (engine: unknown) => void, reject: (error: unknown) => void } | null}
 */
function hostOf(owner) {
  if (typeof owner !== "object" || owner === null) return null;
  const host = Reflect.get(owner, HOST_PROPERTY);
  return typeof host === "object" && host !== null ? host : null;
}

/**
 * @param {unknown} value
 * @returns {value is FrameEngine}
 */
function isFrameEngine(value) {
  return (
    typeof value === "object" &&
    value !== null &&
    "renderDiagram" in value &&
    typeof value.renderDiagram === "function"
  );
}

/** The engine once a start has succeeded. A failed start is never kept. @type {FrameEngine | null} */
let loaded = null;
/** The start in progress, shared by every caller that asks while it runs. @type {Promise<FrameEngine> | null} */
let starting = null;

/** @returns {Promise<FrameEngine>} a new frame that has handed over an engine, or a rejection */
function startInFrame() {
  // `isFrameEngine` is the frame's accept check, so the value it resolves with is an engine.
  return (
    /** @type {Promise<FrameEngine>} */
    (
      loadEngineInFrame(
        document,
        import.meta.url,
        {
          setTimer: (callback, ms) => window.setTimeout(callback, ms),
          clearTimer: (handle) => window.clearTimeout(handle),
        },
        isFrameEngine,
      )
    )
  );
}

/**
 * Resolves to the engine, starting it on the first call. A start that fails rejects, and the next call starts
 * again with a new frame; the browser decides when to call again (diagram_draw.js keeps the retry window).
 *
 * @returns {Promise<FrameEngine>}
 */
export function loadEngine() {
  if (loaded !== null) return Promise.resolve(loaded);
  starting ??= startInFrame()
    .then((engine) => {
      loaded = engine;
      return engine;
    })
    .finally(() => {
      starting = null;
    });
  return starting;
}

/**
 * Discards the started engine and its frame, so the next `loadEngine()` starts a new frame. The page calls it after a
 * draw timed out: Mermaid's queue in that frame may be stuck behind the draw that did not finish.
 */
export function discardEngine() {
  const engine = loaded;
  if (engine === null) return;
  loaded = null;
  removeEngineFrame(engine);
}

const host = hostOf(globalThis.frameElement);
if (host !== null) {
  // The frame's own realm: the core goes to the page's frame element. A failure is reported to it and not thrown,
  // so this module does not stay failed in the frame; the page removes the frame on the report.
  try {
    host.resolve(await import("./engine_core.js"));
  } catch (error) {
    host.reject(error);
  }
}
