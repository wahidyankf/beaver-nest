// ADR 004, Decisions 3 and 4: the page's draw queue and result cache. A job is one source and theme; every
// diagram that shows that source waits on the same job. Jobs run one at a time, yielding to the event loop
// between them. A result is kept for the rest of the page, except the failures that depend on the moment.

import { diagramKind, LIMITS } from "./diagram_limits.js";
import { drawnFigure, fallbackFigure, setFocusable } from "./diagram_figure.js";

/** @typedef {import("./diagram_draw.js").DrawOutcome} DrawOutcome */

/**
 * The part of a session a waiter needs: whether it is still on the page, and whether its canvas is focusable.
 *
 * @typedef {{ connected: boolean, focusable: boolean }} Viewer
 */

/** @typedef {{ session: Viewer, pre: Element }} Waiter */

/**
 * @typedef {{
 *   key: string,
 *   source: string,
 *   themeVariables: Record<string, string>,
 *   waiters: Waiter[]
 * }} Job
 */

/**
 * @typedef {{
 *   cache: Map<string, HTMLElement>,
 *   jobs: Map<string, Job>,
 *   pending: Job[],
 *   running: boolean,
 *   drawer: { draw: (source: string, themeVariables: Record<string, string>) => Promise<DrawOutcome> },
 *   yieldTurn: () => Promise<void>
 * }} Queue
 */

/**
 * The failures that depend only on the source and the theme, so the same result can be kept. The engine's
 * load (`unavailable`), the page's cap (`page-limit`) and a `timeout` depend on the moment, so they are not
 * kept: a timeout was a slow draw on a busy device, and the next request for the source draws it again.
 */
const CACHEABLE_REASONS = new Set(["syntax", "limits", "render", "unsafe"]);

/**
 * @param {{ drawer: Queue["drawer"], yieldTurn: () => Promise<void> }} options
 * @returns {Queue}
 */
export function createQueue({ drawer, yieldTurn }) {
  return {
    cache: new Map(),
    jobs: new Map(),
    pending: [],
    running: false,
    drawer,
    yieldTurn,
  };
}

/**
 * Puts a figure in place of a marked diagram. A figure already on the page is cloned (the same picture can
 * appear twice); a detached one is used as it is.
 *
 * @param {Viewer} session
 * @param {Element} pre
 * @param {HTMLElement} figure
 */
export function place(session, pre, figure) {
  const node = copyFor(figure);
  pre.replaceWith(node);
  // Set once the figure is in the page, because a picture is a keyboard stop only while it overflows (setFocusable).
  setFocusable(node, session.focusable);
  if (session.focusable) measureOnResize(node);
}

/**
 * A figure is used as it is when it is detached (the cache keeps it, and it may have left the page with its source
 * open). A connected one is cloned, so the page holds two copies. Either way the source starts closed: the
 * disclosure state belongs to the figure already on the page.
 *
 * @param {HTMLElement} figure
 * @returns {HTMLElement}
 */
function copyFor(figure) {
  const node = figure.isConnected ? figure.cloneNode(true) : figure;
  if (!(node instanceof HTMLElement)) return figure;
  for (const details of node.querySelectorAll("details")) details.open = false;
  return node;
}

/**
 * The box a picture is in can change size after it is placed (a rotation, a text size change), and a picture
 * overflows only inside that box. Its keyboard stop is measured again whenever its canvas is resized. An observer
 * on a figure that left the page is dropped at its next resize, which its removal makes.
 *
 * @param {HTMLElement} node
 */
function measureOnResize(node) {
  const canvas = node.querySelector(".bnest-diagram-canvas");
  if (!(canvas instanceof HTMLElement) || typeof ResizeObserver !== "function")
    return;
  const observer = new ResizeObserver(() => {
    if (!node.isConnected) {
      observer.disconnect();
      return;
    }
    setFocusable(node, true);
  });
  observer.observe(canvas);
}

/**
 * @param {Queue} queue
 * @param {string} key
 * @param {HTMLElement} figure
 */
function cacheSet(queue, key, figure) {
  queue.cache.set(key, figure);
  while (queue.cache.size > LIMITS.cacheEntries) {
    const oldest = queue.cache.keys().next().value;
    if (oldest === undefined) break;
    queue.cache.delete(oldest);
  }
}

/**
 * The figure for one outcome, and whether it may be kept in the cache.
 *
 * @param {Job} job
 * @param {DrawOutcome} outcome
 * @returns {{ figure: HTMLElement, cacheable: boolean }}
 */
function figureFor(job, outcome) {
  if ("image" in outcome) {
    const figure = drawnFigure({
      image: outcome.image,
      kind: diagramKind(job.source) ?? "Diagram",
      source: job.source,
      focusable: false,
    });
    return { figure, cacheable: true };
  }
  return {
    figure: fallbackFigure({ reason: outcome.reason, source: job.source }),
    cacheable: CACHEABLE_REASONS.has(outcome.reason),
  };
}

/**
 * Runs one job and delivers its figure to every waiter still on the page.
 *
 * @param {Queue} queue
 * @param {Job} job
 */
async function runJob(queue, job) {
  const outcome = await queue.drawer.draw(job.source, job.themeVariables);
  const { figure, cacheable } = figureFor(job, outcome);
  if (cacheable) cacheSet(queue, job.key, figure);
  queue.jobs.delete(job.key);

  // A node removed during the draw gets no figure; the cache above still keeps the result.
  for (const waiter of job.waiters) {
    if (waiter.session.connected && waiter.pre.isConnected) {
      place(waiter.session, waiter.pre, figure);
    }
  }
}

/**
 * Runs the next pending job, yields, and repeats until nothing is pending. A job that fails drops only itself.
 *
 * @param {Queue} queue
 */
function drainNext(queue) {
  const job = queue.pending.shift();
  if (job === undefined) {
    queue.running = false;
    return;
  }
  void runJob(queue, job)
    .catch(() => queue.jobs.delete(job.key))
    .then(() => queue.yieldTurn())
    .then(() => drainNext(queue));
}

/**
 * Adds a job to the queue and starts the drain if nothing is running.
 *
 * @param {Queue} queue
 * @param {Job} job
 */
export function enqueue(queue, job) {
  queue.jobs.set(job.key, job);
  queue.pending.push(job);
  if (queue.running) return;
  queue.running = true;
  drainNext(queue);
}
