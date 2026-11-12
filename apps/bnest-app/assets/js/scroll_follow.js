// Keeps a scrolling region on its newest content while its reader is at, or near, the bottom. The Codex conversation
// and the Family Chat history both use it, so a reply, a drawn diagram or a loaded picture that changes the height
// does not leave the newest part below the fold.
//
// A reader who scrolled up keeps their place: nothing the room adds pulls them down. The reader's position is judged
// from their last scroll, not from the layout. Content that grows under a reader who is at the bottom fires no scroll
// event, so the region stays "at the bottom" until the reader scrolls.
//
// The region can also get shorter while its content stays the same: a Family Chat composer that grows takes height
// from the history beside it. A browser keeps the scroll offset, so a reader at the bottom would then see the newest
// message slide under the composer. A resize observer re-pins that reader, as a content change does.

/** How close to the bottom, in CSS pixels, still counts as reading the newest content. */
export const BOTTOM_THRESHOLD_PX = 80;

/**
 * @param {{ scrollHeight: number, scrollTop: number, clientHeight: number }} region
 * @param {number} [thresholdPx]
 */
export function isNearBottom(region, thresholdPx = BOTTOM_THRESHOLD_PX) {
  return (
    region.scrollHeight - region.scrollTop - region.clientHeight <= thresholdPx
  );
}

/**
 * Installs the observers and listeners that drive a follower and returns the function that removes them.
 *
 * Only content changes move the reader: an attribute change (a highlight, a state flag) is made by the room while the
 * reader may be reading elsewhere. A picture or diagram changes the height of its message when it loads or fails, and
 * neither of those is a DOM mutation, so the capture phase listens for them on the region's descendants. Environments
 * without a ResizeObserver (old engines, and the happy-dom unit runs that do not stub it) keep the content observers.
 *
 * @param {HTMLElement} region
 * @param {{ onContent: () => void, onScroll: () => void, onResize: () => void }} handlers
 * @returns {() => void}
 */
function observeRegion(region, { onContent, onScroll, onResize }) {
  const observer = new MutationObserver(onContent);
  observer.observe(region, {
    childList: true,
    subtree: true,
    characterData: true,
  });
  const sizes =
    typeof ResizeObserver === "function" ? new ResizeObserver(onResize) : null;
  sizes?.observe(region);
  region.addEventListener("scroll", onScroll);
  region.addEventListener("load", onContent, true);
  region.addEventListener("error", onContent, true);
  return () => {
    observer.disconnect();
    sizes?.disconnect();
    region.removeEventListener("scroll", onScroll);
    region.removeEventListener("load", onContent, true);
    region.removeEventListener("error", onContent, true);
  };
}

/**
 * Moves a region to its newest content and tells the room that it did.
 * @param {HTMLElement} region
 * @param {(() => void) | undefined} onStick
 */
function stickToNewest(region, onStick) {
  region.scrollTop = region.scrollHeight;
  onStick?.();
}

/**
 * Starts following the newest content of `region` and returns a handle.
 *
 * @param {HTMLElement} region the scrolling region
 * @param {{ thresholdPx?: number, onStick?: () => void, startAtBottom?: boolean }} [options]
 *   `onStick` runs each time the region is moved to its newest content. `startAtBottom` (default true) moves the
 *   region to its newest content now; a room that places its reader itself passes false, and the follower then
 *   waits for the reader's first scroll before it follows.
 * @returns {{ pinned: () => boolean, pin: () => void, dispose: () => void }}
 *   `pin` moves the reader to the newest content and follows from there (a message the reader just sent).
 *   `dispose` stops following and releases the observers.
 */
export function createBottomFollower(region, options = {}) {
  const thresholdPx = options.thresholdPx ?? BOTTOM_THRESHOLD_PX;
  let pinned = options.startAtBottom ?? true;
  // The region's height at the last resize observation. A scroll event in the same frame as a height change is the
  // layout moving the content under a reader who did not move, so that scroll does not judge the reader's place; the
  // resize observation that follows re-pins a reader who was at the bottom.
  let observedHeight = region.clientHeight;

  const stick = () => stickToNewest(region, options.onStick);

  function onScroll() {
    if (
      typeof ResizeObserver === "function" &&
      region.clientHeight !== observedHeight
    )
      return;
    pinned = isNearBottom(region, thresholdPx);
  }

  function onContent() {
    if (pinned) stick();
  }

  function onResize() {
    observedHeight = region.clientHeight;
    onContent();
  }

  const stopObserving = observeRegion(region, {
    onContent,
    onScroll,
    onResize,
  });

  if (pinned) stick();

  return {
    pinned: () => pinned,
    pin() {
      pinned = true;
      stick();
    },
    dispose() {
      stopObserving();
      pinned = false;
    },
  };
}
