// ADR 004, Decisions 3 and 4: finds the marked diagrams in a root, draws them when they are near the viewport,
// and puts the result in place. The engine, the draw, the queue and the browser services live in
// diagram_draw.js, diagram_queue.js and diagram_browser.js. Nothing here writes markup from a string.

import { checkSource, LIMITS } from "./diagram_limits.js";
import { fallbackFigure } from "./diagram_figure.js";
import { createDrawer } from "./diagram_draw.js";
import { createQueue, enqueue, place } from "./diagram_queue.js";
import { browserDeps } from "./diagram_browser.js";

/** @typedef {{ observe(target: Element): void, unobserve(target: Element): void, disconnect(): void }} IntersectionLike */

/**
 * One observed root. `watched` holds the diagrams waiting for the viewport, by element.
 *
 * @typedef {{
 *   connected: boolean,
 *   focusable: boolean,
 *   watched: Map<Element, () => void>,
 *   intersection: IntersectionLike | null
 * }} Session
 */

/**
 * The browser services the renderer needs. A test supplies fakes; the default reads the page.
 *
 * @typedef {{
 *   importEngine: () => Promise<unknown>,
 *   readTheme: () => { themeVariables: Record<string, string>, themeSignature: string },
 *   now: () => number,
 *   setTimer: (callback: () => void, ms: number) => number,
 *   clearTimer: (handle: number) => void,
 *   yieldTurn: () => Promise<void>,
 *   createIntersectionObserver: (
 *     callback: (entries: { target: Element, isIntersecting: boolean }[]) => void,
 *     options: { rootMargin: string }
 *   ) => IntersectionLike | null
 * }} RendererDeps
 */

/**
 * The renderer's shared state. One renderer per page: the queue, the cache and the page cap are shared by
 * every root it observes.
 *
 * @typedef {{
 *   deps: RendererDeps,
 *   queue: import("./diagram_queue.js").Queue,
 *   claimed: WeakSet<Element>
 * }} Renderer
 */

const SELECTOR = 'pre[data-bnest-diagram="mermaid"]';

/**
 * The source of a marked diagram: the text of its code element, as the server escaped it.
 *
 * @param {Element} pre
 * @returns {string}
 */
function sourceOf(pre) {
  const code = pre.querySelector("code");
  return code ? (code.textContent ?? "") : (pre.textContent ?? "");
}

/**
 * @param {{ themeSignature: string }} theme
 * @param {string} source
 * @returns {string}
 */
function cacheKey(theme, source) {
  return `${theme.themeSignature}\n${source}`;
}

/**
 * Admits a diagram to the queue: the source is checked again, a cached result is placed at once, and a
 * diagram already waiting or drawing takes this place as one more waiter.
 *
 * @param {Renderer} renderer
 * @param {Session} session
 * @param {Element} pre
 */
function admit(renderer, session, pre) {
  if (!session.connected || !pre.isConnected) return;
  const source = sourceOf(pre);
  const theme = renderer.deps.readTheme();
  if (!checkSource(source)) {
    place(session, pre, fallbackFigure({ reason: "limits", source }));
    return;
  }

  const key = cacheKey(theme, source);
  const hit = renderer.queue.cache.get(key);
  if (hit !== undefined) {
    place(session, pre, hit);
    return;
  }

  const waiting = renderer.queue.jobs.get(key);
  if (waiting !== undefined) {
    waiting.waiters.push({ session, pre });
    return;
  }

  enqueue(renderer.queue, {
    key,
    source,
    themeVariables: theme.themeVariables,
    waiters: [{ session, pre }],
  });
}

/**
 * Decides what to do with one marked diagram: a claimed one is skipped, a cached one is placed at once, a
 * refused one gets its note at once, and any other waits for the viewport (or goes at once without an
 * observer).
 *
 * @param {Renderer} renderer
 * @param {Session} session
 * @param {Element} pre
 */
function consider(renderer, session, pre) {
  if (renderer.claimed.has(pre)) return;
  renderer.claimed.add(pre);

  const source = sourceOf(pre);
  const theme = renderer.deps.readTheme();
  const hit = renderer.queue.cache.get(cacheKey(theme, source));
  if (hit !== undefined) {
    place(session, pre, hit);
    return;
  }
  if (!checkSource(source)) {
    place(session, pre, fallbackFigure({ reason: "limits", source }));
    return;
  }

  if (session.intersection === null) {
    admit(renderer, session, pre);
    return;
  }
  session.watched.set(pre, () => admit(renderer, session, pre));
  session.intersection.observe(pre);
}

/**
 * Considers a node and every marked diagram inside it.
 *
 * @param {Renderer} renderer
 * @param {Session} session
 * @param {Element} node
 */
function considerTree(renderer, session, node) {
  if (node.matches(SELECTOR)) consider(renderer, session, node);
  for (const pre of node.querySelectorAll(SELECTOR)) {
    consider(renderer, session, pre);
  }
}

/**
 * Admits the waiting diagrams that have come near the viewport in one session.
 *
 * @param {Session} session
 * @param {{ target: Element, isIntersecting: boolean }[]} entries
 */
function onEntries(session, entries) {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    const admitLater = session.watched.get(entry.target);
    if (admitLater === undefined) continue;
    session.watched.delete(entry.target);
    session.intersection?.unobserve(entry.target);
    admitLater();
  }
}

/**
 * @param {Renderer} renderer
 * @param {{ focusable?: boolean } | undefined} options
 * @returns {Session}
 */
function openSession(renderer, options) {
  /** @type {Session} */
  const session = {
    connected: true,
    focusable: options?.focusable === true,
    watched: new Map(),
    intersection: renderer.deps.createIntersectionObserver(
      (entries) => onEntries(session, entries),
      { rootMargin: `${LIMITS.prefetchMarginPx}px 0px` },
    ),
  };
  return session;
}

/**
 * @param {Renderer} renderer
 * @param {Session} session
 * @param {MutationRecord[]} records
 */
function onRecords(renderer, session, records) {
  if (!session.connected) return;
  for (const record of records) {
    if (record.type === "attributes" && record.target instanceof Element) {
      considerTree(renderer, session, record.target);
    }
    for (const node of record.addedNodes) {
      if (node instanceof Element) considerTree(renderer, session, node);
    }
  }
}

/**
 * Draws the marked diagrams inside `root` and any that are added or marked later. The returned object stops
 * the watching; a diagram still waiting for the viewport is then never drawn.
 *
 * @param {Renderer} renderer
 * @param {Element} root
 * @param {{ focusable?: boolean }} [options]
 * @returns {{ disconnect(): void }}
 */
function watchRoot(renderer, root, options) {
  const session = openSession(renderer, options);
  const observer = new MutationObserver((records) =>
    onRecords(renderer, session, records),
  );
  observer.observe(root, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-bnest-diagram"],
  });
  considerTree(renderer, session, root);

  return {
    disconnect() {
      observer.disconnect();
      session.connected = false;
      session.watched.clear();
      session.intersection?.disconnect();
    },
  };
}

/**
 * @param {RendererDeps} deps
 * @returns {{
 *   observeDiagrams: (root: Element, options?: { focusable?: boolean }) => { disconnect(): void }
 * }}
 */
export function createDiagramRenderer(deps) {
  /** @type {Renderer} */
  const renderer = {
    deps,
    queue: createQueue({
      drawer: createDrawer(deps),
      yieldTurn: deps.yieldTurn,
    }),
    claimed: new WeakSet(),
  };
  return {
    observeDiagrams: (root, options) => watchRoot(renderer, root, options),
  };
}

const defaultRenderer = createDiagramRenderer(browserDeps());

/**
 * Watches `root` for marked diagrams for as long as the returned object is not disconnected.
 * `focusable` makes the canvas a keyboard stop (the Codex chat); the default keeps the history's single tab stop.
 */
export const observeDiagrams = defaultRenderer.observeDiagrams;
