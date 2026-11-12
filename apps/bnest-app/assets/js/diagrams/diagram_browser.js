// ADR 004, Decision 4: the browser services the diagram renderer uses. Only this module reads the page, so the
// renderer and its queue can be tested with fakes.

import { readThemeVariables } from "./diagram_theme.js";

/** @typedef {import("./mermaid_diagrams.js").RendererDeps} RendererDeps */

/**
 * The engine's module as the page imports it: `loadEngine()` starts the engine, and a failed start is retried by the
 * next call (engine.js).
 *
 * @typedef {{ ENGINE_API: unknown, loadEngine: () => Promise<{ renderDiagram: unknown }>, discardEngine?: () => void }} EngineModule
 */

/**
 * The address for a retry after `failures` failed imports. A failed module fetch stays failed in the browser's module
 * map for its exact address, so the retry asks for the same module under a query the map does not hold yet.
 *
 * @param {string} url
 * @param {number} failures
 * @returns {string}
 */
function retryAddress(url, failures) {
  return `${url}${url.includes("?") ? "&" : "?"}retry=${failures}`;
}

/**
 * The page's engine importer. The address comes from the meta tag the root layout renders, so a page without a marked
 * diagram never asks for the engine. The first import uses the address itself; after a failed import the next call
 * uses a retry address. The count lives in the importer, so it is created once per page.
 *
 * @param {{ readUrl: () => string | undefined, importModule: (address: string) => Promise<EngineModule> }} io
 * @returns {() => Promise<unknown>} the module's API as diagram_draw.js expects it: `ENGINE_API` and `renderDiagram`
 */
export function createEngineImporter(io) {
  let failedImports = 0;

  return async () => {
    const url = io.readUrl();
    if (!url) {
      throw new Error("the diagram engine address is missing");
    }

    let engineModule;
    try {
      engineModule = await io.importModule(
        failedImports === 0 ? url : retryAddress(url, failedImports),
      );
    } catch (error) {
      failedImports += 1;
      throw error;
    }

    const engine = await engineModule.loadEngine();
    return {
      ENGINE_API: engineModule.ENGINE_API,
      renderDiagram: engine.renderDiagram,
      discard: engineModule.discardEngine,
    };
  };
}

const readPageTheme = makeThemeReader(() => readThemeVariables());

const importEngineFromPage = createEngineImporter({
  readUrl: () =>
    document
      .querySelector('meta[name="bnest-diagram-engine"]')
      ?.getAttribute("content") ?? undefined,
  importModule: (address) =>
    import(
      /* @vite-ignore */
      address
    ),
});

/**
 * Wraps a theme read so that one synchronous batch of diagrams reads the theme once. A read forces the browser to
 * match the page's styles, and a page with several diagrams asks once per diagram. The cache ends with the batch
 * (a microtask), so the next draw reads a theme change.
 *
 * @template T
 * @param {() => T} read
 * @returns {() => T}
 */
export function makeThemeReader(read) {
  /** @type {T | null} */
  let cached = null;
  return () => {
    if (cached !== null) return cached;
    cached = read();
    queueMicrotask(() => {
      cached = null;
    });
    return cached;
  };
}

/** @returns {RendererDeps} the browser's services */
export function browserDeps() {
  return {
    importEngine: importEngineFromPage,
    readTheme: readPageTheme,
    now: () => performance.now(),
    setTimer: (callback, ms) => window.setTimeout(callback, ms),
    clearTimer: (handle) => window.clearTimeout(handle),
    yieldTurn: () =>
      new Promise((resolve) => {
        window.setTimeout(resolve, 0);
      }),
    createIntersectionObserver: (callback, options) =>
      typeof IntersectionObserver === "function"
        ? new IntersectionObserver(callback, options)
        : null,
  };
}
