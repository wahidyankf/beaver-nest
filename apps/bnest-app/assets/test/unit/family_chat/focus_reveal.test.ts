// Plain Vitest unit coverage for `js/family_chat/focus_reveal.js`: how far the history scrolls when a keyboard move
// lands focus on a message. ADR 003, Decision 6 owns the rule; this file pins its geometry.
//
// The function reads only `getBoundingClientRect()` and `scrollTop`, so the fakes below are the whole contract. A
// real layout is FE_E2E's (`family-chat-history-scroll.steps.ts`), which proves the same rows in Chromium.

import { describe, expect, it } from "vitest";
import { revealInHistory } from "../../../js/family_chat/focus_reveal.js";

// The history's window: 100 to 500 on screen, 400 px tall.
const FRAME = { top: 100, bottom: 500, height: 400 };

function rect(top: number, height: number) {
  return { top, bottom: top + height, height };
}

/** A scroller whose frame is `FRAME` and whose content is scrolled to `scrollTop`. */
function scroller(scrollTop: number) {
  return {
    scrollTop,
    getBoundingClientRect: () => rect(FRAME.top, FRAME.height),
  };
}

/** A message at a given screen position, measured by its own rectangle. */
function message(top: number, height: number) {
  return { getBoundingClientRect: () => rect(top, height) };
}

/** Runs the reveal and returns where the history scrolled to. */
function revealed(
  row: { top: number; height: number },
  scrollTop: number,
): number {
  const history = scroller(scrollTop);
  revealInHistory(
    message(row.top, row.height) as unknown as HTMLElement,
    history as unknown as HTMLElement,
  );
  return history.scrollTop;
}

describe("revealInHistory", () => {
  it("scrolls a message above the window to the window's top edge", () => {
    // The message spans 40 to 80, so the history moves up 60 px to bring its top to 100.
    expect(revealed({ top: 40, height: 40 }, 300)).toBe(240);
  });

  it("scrolls a message below the window to the window's bottom edge", () => {
    // The message spans 520 to 560, so the history moves down 60 px to bring its bottom to 500.
    expect(revealed({ top: 520, height: 40 }, 300)).toBe(360);
  });

  it("aligns the top of a message taller than the window, even when its top is already inside", () => {
    // The message spans 150 to 750. Aligning its bottom would push its top above the window, so the top is
    // aligned: the history moves 50 px, and the first lines of the message show.
    expect(revealed({ top: 150, height: 600 }, 300)).toBe(350);
  });

  it("aligns the top of a taller-than-window message that starts above the window", () => {
    // The message spans 40 to 640, so the history moves up 60 px to bring its top to 100.
    expect(revealed({ top: 40, height: 600 }, 300)).toBe(240);
  });

  it("leaves the history alone when the message is already fully visible", () => {
    // The message spans 200 to 240, well inside the window, so a reader who is reading is not moved.
    expect(revealed({ top: 200, height: 40 }, 300)).toBe(300);
  });

  it("leaves the history alone when the message's bottom edge sits exactly on the window's bottom edge", () => {
    // The message spans 460 to 500, touching the bottom edge: it is visible, so nothing scrolls.
    expect(revealed({ top: 460, height: 40 }, 300)).toBe(300);
  });
});
