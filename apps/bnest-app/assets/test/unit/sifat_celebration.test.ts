// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/sifat_celebration.js`: a correct Sifat
// answer bursts confetti unless the visitor prefers reduced motion or the
// celebration shell is absent.

import { afterEach, describe, expect, it, vi } from "vitest";
import {
  celebrateSifatAnswer,
  randomItem,
} from "../../js/sifat_celebration.js";

function matchMedia(reduce: boolean): void {
  window.matchMedia = ((query: string) => ({
    matches: reduce && query === "(prefers-reduced-motion: reduce)",
    media: query,
    onchange: null,
    addEventListener: () => {},
    removeEventListener: () => {},
    addListener: () => {},
    removeListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}

function shell(): HTMLElement {
  document.body.innerHTML = `<div id="sifat-celebrations"></div>`;
  const container = document.querySelector("#sifat-celebrations");
  if (!(container instanceof HTMLElement)) throw new Error("no shell");
  return container;
}

afterEach(() => {
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

describe("randomItem", () => {
  it("picks the only item and refuses an empty list", () => {
    expect(randomItem(["star"])).toBe("star");
    expect(() => randomItem([])).toThrow("Cannot select from an empty list");
  });
});

// @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A celebration plays on success and is skipped with reduced motion
describe("celebrateSifatAnswer", () => {
  it("bursts fourteen confetti pieces when motion is allowed", () => {
    matchMedia(false);
    const container = shell();
    const raf: FrameRequestCallback[] = [];
    window.requestAnimationFrame = ((cb: FrameRequestCallback) => {
      raf.push(cb);
      return raf.length;
    }) as unknown as typeof window.requestAnimationFrame;

    celebrateSifatAnswer();

    expect(container.childElementCount).toBe(14);
    for (const piece of container.children) {
      expect(piece.className).toMatch(
        /sifat-confetti is-(star|dot|diamond|spark)/,
      );
    }
    raf.forEach((cb) => cb(0));
    for (const piece of container.children) {
      expect(piece.classList.contains("is-flying")).toBe(true);
    }
  });

  it("does nothing when the visitor prefers reduced motion", () => {
    matchMedia(true);
    const container = shell();

    celebrateSifatAnswer();

    expect(container.childElementCount).toBe(0);
  });

  it("does nothing when the celebration shell is absent", () => {
    matchMedia(false);
    document.body.innerHTML = `<main><p>No shell here</p></main>`;

    expect(() => celebrateSifatAnswer()).not.toThrow();
    expect(document.querySelectorAll(".sifat-confetti")).toHaveLength(0);
  });

  it("a finished piece removes itself on animation end", () => {
    matchMedia(false);
    const container = shell();
    window.requestAnimationFrame = ((cb: FrameRequestCallback) => {
      cb(0);
      return 1;
    }) as unknown as typeof window.requestAnimationFrame;

    celebrateSifatAnswer();

    const piece = container.firstElementChild;
    if (!(piece instanceof HTMLElement)) throw new Error("no piece");
    piece.dispatchEvent(new Event("animationend"));
    expect(container.childElementCount).toBe(13);
  });
});
