// ADR 004, Decisions 3 and 4: one draw of one diagram. The engine (Mermaid) starts lazily, on the first draw that
// needs it. A failed start is remembered for engineRetryMs, and within that window every draw reports `unavailable`
// without a new start; after the window the next draw starts the engine again, in a new frame. Each draw races the
// render timeout. The page cap counts successful draws.

import { LIMITS } from "./diagram_limits.js";
import { svgToImage } from "./diagram_figure.js";

/**
 * Why a diagram is shown as its source (ADR 004, Decision 3). The note texts are in diagram_figure.js.
 *
 * @typedef {"syntax" | "limits" | "render" | "timeout" | "unavailable" | "unsafe" | "page-limit"} Reason
 */

/**
 * @typedef {{ image: { src: string, width: number, height: number } } | { reason: Reason }} DrawOutcome
 */

/**
 * @typedef {{
 *   ENGINE_API: 1,
 *   renderDiagram: (source: string, themeVariables: Record<string, string>) => Promise<{ svg: string }>,
 *   discard?: () => void
 * }} EngineModule
 */

/**
 * The services a draw needs. A test supplies fakes; the browser supplies the real ones.
 *
 * @typedef {{
 *   importEngine: () => Promise<unknown>,
 *   now: () => number,
 *   setTimer: (callback: () => void, ms: number) => number,
 *   clearTimer: (handle: number) => void
 * }} DrawDeps
 */

/** A failure a draw step raises, carrying the reason the reader is told. */
export class DrawFailure extends Error {
  /** @type {Reason} */
  reason;

  /** @param {Reason} reason */
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

/**
 * @param {unknown} value
 * @returns {value is EngineModule}
 */
function isEngineModule(value) {
  return (
    typeof value === "object" &&
    value !== null &&
    "ENGINE_API" in value &&
    value.ENGINE_API === 1 &&
    "renderDiagram" in value &&
    typeof value.renderDiagram === "function"
  );
}

/**
 * The reason for a draw error: the engine's own kind (`syntax` or `limits`) when it gives one, or `render`
 * for anything else.
 *
 * @param {unknown} error
 * @returns {Reason}
 */
export function reasonOf(error) {
  if (error instanceof DrawFailure) return error.reason;
  const kind = engineKindOf(error);
  return kind === "syntax" || kind === "limits" ? kind : "render";
}

/**
 * The `kind` an engine error carries, or undefined for any other value.
 *
 * @param {unknown} error
 * @returns {unknown}
 */
function engineKindOf(error) {
  if (typeof error !== "object" || error === null) return null;
  return "name" in error && error.name === "DiagramError" && "kind" in error
    ? error.kind
    : null;
}

/**
 * @param {DrawDeps} deps
 * @param {{ module: EngineModule | null, failedAt: number | null }} state
 * @returns {Promise<EngineModule>}
 */
async function loadEngine(deps, state) {
  if (state.module !== null) return state.module;
  if (
    state.failedAt !== null &&
    deps.now() - state.failedAt < LIMITS.engineRetryMs
  ) {
    throw new DrawFailure("unavailable");
  }
  try {
    const loaded = await deps.importEngine();
    if (!isEngineModule(loaded)) {
      throw new Error("the diagram engine has another API version");
    }
    state.module = loaded;
    state.failedAt = null;
    return loaded;
  } catch {
    state.failedAt = deps.now();
    throw new DrawFailure("unavailable");
  }
}

/**
 * Races the work against the render timeout. The work is not cancelled; a late result is ignored.
 *
 * @template T
 * @param {DrawDeps} deps
 * @param {Promise<T>} work
 * @returns {Promise<T>}
 */
function withTimeout(deps, work) {
  return new Promise((resolve, reject) => {
    const timer = deps.setTimer(
      () => reject(new DrawFailure("timeout")),
      LIMITS.renderTimeoutMs,
    );
    work.then(
      (value) => {
        deps.clearTimer(timer);
        resolve(value);
      },
      (error) => {
        deps.clearTimer(timer);
        reject(error);
      },
    );
  });
}

/**
 * The picture of a successful draw. A picture the SVG check refuses is an `unsafe` failure.
 *
 * @param {{ svg: string }} result
 * @returns {{ src: string, width: number, height: number }}
 */
function pictureOf(result) {
  try {
    return svgToImage(result.svg);
  } catch {
    throw new DrawFailure("unsafe");
  }
}

/**
 * Drops an engine whose draw timed out: its frame goes, and the next draw starts the engine again. The draw may be
 * stuck in the engine's own queue, so the engine cannot be trusted with the next draw.
 *
 * @param {{ module: EngineModule | null }} state
 * @param {EngineModule} engine
 */
function discardTimedOut(state, engine) {
  if (state.module === engine) state.module = null;
  engine.discard?.();
}

/**
 * @param {DrawDeps} deps
 * @param {{ module: EngineModule | null, failedAt: number | null, drawn: number }} state
 * @param {string} source
 * @param {Record<string, string>} themeVariables
 * @returns {Promise<DrawOutcome>}
 */
async function drawSource(deps, state, source, themeVariables) {
  if (state.drawn >= LIMITS.maxPerPage) return { reason: "page-limit" };
  try {
    const loaded = await loadEngine(deps, state);
    const result = await withTimeout(
      deps,
      loaded.renderDiagram(source, themeVariables),
    ).catch((error) => {
      if (reasonOf(error) === "timeout") discardTimedOut(state, loaded);
      throw error;
    });
    const image = pictureOf(result);
    state.drawn += 1;
    return { image };
  } catch (error) {
    return { reason: reasonOf(error) };
  }
}

/**
 * One drawer per page: the engine, the failed-load window and the page count are shared by every draw.
 *
 * @param {DrawDeps} deps
 * @returns {{ draw: (source: string, themeVariables: Record<string, string>) => Promise<DrawOutcome> }}
 */
export function createDrawer(deps) {
  /** @type {{ module: EngineModule | null, failedAt: number | null, drawn: number }} */
  const state = { module: null, failedAt: null, drawn: 0 };
  return {
    draw: (source, themeVariables) =>
      drawSource(deps, state, source, themeVariables),
  };
}
