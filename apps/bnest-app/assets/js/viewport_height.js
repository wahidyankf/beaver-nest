// The room heights follow the visible area when a soft keyboard opens (ADR 005, decision 5). On the room pages the
// stylesheet reads `--vvh` for those heights and falls back to `100dvh`, so the page works without this module. Where
// the browser has `window.visualViewport`, this writes its height to `--vvh` while a room is on the page. It writes
// nothing on any other page, and it keeps the last height while the visitor is pinch-zoomed (the visual viewport
// shrinks under a zoom, which is not a keyboard). A scrolled room page is put back at the top; the stylesheet already
// clips the page, so this covers only the case where a keyboard has panned it.

const ROOM_SELECTOR = ".chat-shell, .family-chat-shell";
const ZOOMED_ABOVE = 1.01;
// The stop function of each live install, keyed by window, so a second install (app.js mounted twice) returns the
// first stop instead of adding listeners again.
const liveStops = new WeakMap();

/**
 * Keeps `--vvh` equal to the visual viewport's height on the room pages, until the returned function runs.
 * @param {Window} [win]
 * @returns {() => void} removes the listeners
 */
export function installVisualViewportHeight(win = window) {
  const viewport = win.visualViewport;
  if (!viewport) return () => {};

  const existing = liveStops.get(win);
  if (existing) return existing;

  const root = win.document.documentElement;
  const sync = () => {
    if (!win.document.querySelector(ROOM_SELECTOR)) return;
    if (viewport.scale > ZOOMED_ABOVE) return;
    root.style.setProperty("--vvh", `${viewport.height}px`);
    if (win.scrollY !== 0) win.scrollTo(0, 0);
  };
  sync();
  viewport.addEventListener("resize", sync);
  viewport.addEventListener("scroll", sync);
  // LiveView renders a room after a navigation, with no resize, so the height is written when that load settles.
  win.addEventListener("phx:page-loading-stop", sync);

  const stop = () => {
    viewport.removeEventListener("resize", sync);
    viewport.removeEventListener("scroll", sync);
    win.removeEventListener("phx:page-loading-stop", sync);
    liveStops.delete(win);
  };
  liveStops.set(win, stop);
  return stop;
}
