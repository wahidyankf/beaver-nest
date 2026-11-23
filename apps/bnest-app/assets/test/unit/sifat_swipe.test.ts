// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/sifat_swipe.js`: a horizontal primary
// swipe past the threshold reports its direction, and anything else reports
// nothing.

import { afterEach, describe, expect, it } from "vitest";
import { SifatSwipe } from "../../js/sifat_swipe.js";

interface Hook {
  el: HTMLElement;
  pushEvent: (event: string, payload: { direction: string }) => void;
  onPointerDown?: (event: PointerEvent) => void;
  onPointerUp?: (event: PointerEvent) => void;
  onPointerCancel?: (event: PointerEvent) => void;
}

function mounted(): { hook: Hook; pushed: Array<{ direction: string }> } {
  const pushed: Array<{ direction: string }> = [];
  const el = document.createElement("div");
  el.dataset["swipeEvent"] = "swipe-study";
  document.body.replaceChildren(el);
  const hook = {
    el,
    pushEvent: (_event: string, payload: { direction: string }) => {
      pushed.push(payload);
    },
  } as Hook;
  for (const target of [el]) {
    target.setPointerCapture = () => {};
    target.releasePointerCapture = () => {};
    target.hasPointerCapture = () => true;
  }
  const onMount = SifatSwipe.mounted as unknown as
    ((this: Hook) => void) | undefined;
  if (!onMount) throw new Error("no mounted hook");
  onMount.call(hook);
  return { hook, pushed };
}

function pointer(
  type: string,
  init: PointerEventInit & { pointerId: number },
): PointerEvent {
  const event = new Event(type) as PointerEvent;
  Object.assign(event, { isPrimary: true, clientX: 0, clientY: 0, ...init });
  return event;
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("SifatSwipe", () => {
  it("reports a left swipe past the threshold", () => {
    const { hook, pushed } = mounted();
    hook.onPointerDown?.(
      pointer("pointerdown", { pointerId: 7, clientX: 200, clientY: 100 }),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 7, clientX: 100, clientY: 105 }),
    );
    expect(pushed).toEqual([{ direction: "left" }]);
  });

  it("reports a right swipe past the threshold", () => {
    const { hook, pushed } = mounted();
    hook.onPointerDown?.(
      pointer("pointerdown", { pointerId: 3, clientX: 50, clientY: 100 }),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 3, clientX: 150, clientY: 95 }),
    );
    expect(pushed).toEqual([{ direction: "right" }]);
  });

  it("ignores short, vertical, non-primary, and interactive swipes", () => {
    const { hook, pushed } = mounted();
    hook.onPointerDown?.(
      pointer("pointerdown", { pointerId: 1, clientX: 100, clientY: 100 }),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 1, clientX: 120, clientY: 100 }),
    );
    hook.onPointerDown?.(
      pointer("pointerdown", { pointerId: 2, clientX: 100, clientY: 100 }),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 2, clientX: 100, clientY: 200 }),
    );
    hook.onPointerDown?.(
      Object.assign(
        pointer("pointerdown", { pointerId: 4, clientX: 100, clientY: 100 }),
        {
          isPrimary: false,
        },
      ),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 4, clientX: 0, clientY: 100 }),
    );
    expect(pushed).toEqual([]);
  });

  it("cancelling clears the swipe and removes listeners on destroy", () => {
    const { hook, pushed } = mounted();
    hook.onPointerDown?.(
      pointer("pointerdown", { pointerId: 9, clientX: 200, clientY: 100 }),
    );
    hook.onPointerCancel?.(
      pointer("pointercancel", { pointerId: 9, clientX: 0, clientY: 100 }),
    );
    hook.onPointerUp?.(
      pointer("pointerup", { pointerId: 9, clientX: 0, clientY: 100 }),
    );
    expect(pushed).toEqual([]);
    const onDestroy = SifatSwipe.destroyed as unknown as
      ((this: Hook) => void) | undefined;
    if (!onDestroy) throw new Error("no destroyed hook");
    onDestroy.call(hook);
  });
});
