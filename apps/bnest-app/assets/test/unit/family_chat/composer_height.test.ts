// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/composer_height.js`: the Family Chat composer grows with its draft
// up to a cap of six lines and then scrolls (FC-04). The arithmetic is tested on plain numbers; the element test
// checks what the page writes into the textarea's own height and overflow.

import { describe, expect, it } from "vitest";
import {
  composerHeightFor,
  fitComposerInput,
  lengthToPx,
} from "../../../js/family_chat/composer_height.js";

describe("composerHeightFor", () => {
  it("grows to the content plus the borders while the draft fits under the cap", () => {
    expect(
      composerHeightFor({ scrollHeight: 58, borderPx: 4, capPx: 170.4 }),
    ).toEqual({
      heightPx: 62,
      scrolls: false,
    });
  });

  it("stops at the cap and scrolls once the draft is taller than the cap", () => {
    expect(
      composerHeightFor({ scrollHeight: 310, borderPx: 4, capPx: 170.4 }),
    ).toEqual({
      heightPx: 170.4,
      scrolls: true,
    });
  });

  it("has no cap when none is declared", () => {
    expect(
      composerHeightFor({
        scrollHeight: 310,
        borderPx: 4,
        capPx: Number.POSITIVE_INFINITY,
      }),
    ).toEqual({
      heightPx: 314,
      scrolls: false,
    });
  });
});

describe("lengthToPx", () => {
  it("reads px and rem, with rem at the page's 16 pixels", () => {
    expect(lengthToPx("170.4px")).toBe(170.4);
    expect(lengthToPx("10.65rem")).toBeCloseTo(170.4, 6);
  });

  it("reads min() of a length and a window-height unit against the window's height", () => {
    expect(lengthToPx("min(10.65rem, 22svh)", 390)).toBeCloseTo(85.8, 6);
    expect(lengthToPx("min(10.65rem, 22svh)", 844)).toBeCloseTo(170.4, 6);
    expect(lengthToPx("max(1px, 50vh)", 400)).toBeCloseTo(200, 6);
  });

  it("applies no cap to a window-height unit when the window's height is unknown", () => {
    expect(Number.isNaN(lengthToPx("22svh"))).toBe(true);
    expect(Number.isNaN(lengthToPx("min(10.65rem, 22svh)"))).toBe(true);
  });

  it("reads nothing else as a length, so the caller applies no cap", () => {
    expect(Number.isNaN(lengthToPx("none"))).toBe(true);
    expect(Number.isNaN(lengthToPx(""))).toBe(true);
  });
});

describe("fitComposerInput", () => {
  it("sets the textarea height from its content, and scrolls only past the cap", () => {
    const textarea = document.createElement("textarea");
    textarea.style.maxHeight = "10.65rem";
    document.body.append(textarea);
    let content = 310;
    Object.defineProperty(textarea, "scrollHeight", {
      configurable: true,
      get: () => content,
    });

    fitComposerInput(textarea);
    expect(textarea.style.height).toBe("170.4px");
    expect(textarea.style.overflowY).toBe("auto");

    content = 62;
    fitComposerInput(textarea);
    expect(textarea.style.height).toBe("62px");
    expect(textarea.style.overflowY).toBe("hidden");
    textarea.remove();
  });
});
