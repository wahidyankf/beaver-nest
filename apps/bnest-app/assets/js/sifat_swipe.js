// Sifat study swipe gesture (a left or right swipe on the card). The hook is registered in app.js.

const swipeThreshold = 56;

/** @typedef {{ pointerId: number, x: number, y: number }} SwipeStart */
/**
 * @typedef {{
 *   onPointerDown: (event: PointerEvent) => void,
 *   onPointerUp: (event: PointerEvent) => void,
 *   onPointerCancel: (event: PointerEvent) => void
 * }} SifatSwipeState
 */

/** @param {EventTarget | null} target */
const isInteractiveTarget = (target) =>
  target instanceof Element &&
  Boolean(target.closest("button, a, input, select, textarea, label"));

/** @param {Element} element @param {PointerEvent} event */
const releasePointerCapture = (element, event) => {
  if (element.hasPointerCapture(event.pointerId)) {
    element.releasePointerCapture(event.pointerId);
  }
};

/** @param {Element} element @param {PointerEvent} event */
const startSwipe = (element, event) => {
  if (!event.isPrimary || isInteractiveTarget(event.target)) return null;

  element.setPointerCapture(event.pointerId);
  return { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
};

/**
 * @param {{
 *   el: HTMLElement,
 *   pushEvent: (event: string, payload: {direction: "left" | "right"}) => void
 * }} hook
 * @param {SwipeStart | null} start
 * @param {PointerEvent} event
 */
const finishSwipe = (hook, start, event) => {
  if (!start || start.pointerId !== event.pointerId) return null;

  const distanceX = event.clientX - start.x;
  const distanceY = event.clientY - start.y;
  releasePointerCapture(hook.el, event);

  if (
    Math.abs(distanceX) < swipeThreshold ||
    Math.abs(distanceX) <= Math.abs(distanceY)
  ) {
    return null;
  }

  hook.pushEvent(hook.el.dataset["swipeEvent"] ?? "swipe-study", {
    direction: distanceX < 0 ? "left" : "right",
  });

  return null;
};

/** @type {import("phoenix_live_view").Hook<SifatSwipeState>} */
export const SifatSwipe = {
  mounted() {
    /** @type {SwipeStart | null} */
    let start = null;

    /** @param {PointerEvent} event */
    this.onPointerDown = (event) => {
      start = startSwipe(this.el, event);
    };

    /** @param {PointerEvent} event */
    this.onPointerUp = (event) => {
      start = finishSwipe(this, start, event);
    };

    /** @param {PointerEvent} event */
    this.onPointerCancel = (event) => {
      start = null;
      releasePointerCapture(this.el, event);
    };

    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("pointercancel", this.onPointerCancel);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown);
    this.el.removeEventListener("pointerup", this.onPointerUp);
    this.el.removeEventListener("pointercancel", this.onPointerCancel);
  },
};
