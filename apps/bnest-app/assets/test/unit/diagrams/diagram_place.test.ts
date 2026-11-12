// @vitest-environment happy-dom
// ADR 004, Decision 4 (a figure on the page). A copy of a figure already on the page starts with its source closed,
// and a picture is a keyboard stop in the Codex chat only while it overflows its box, so a picture that fits is not
// a tab stop.
import { afterEach, describe, expect, it, vi } from "vitest";
import { drawnFigure } from "../../../js/diagrams/diagram_figure.js";
import { place } from "../../../js/diagrams/diagram_queue.js";

const IMAGE = {
  src: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",
  width: 200,
  height: 100,
};
const CHAT = { connected: true, focusable: true };

function figureOf(focusable: boolean): HTMLElement {
  return drawnFigure({
    image: IMAGE,
    kind: "Flowchart",
    source: "flowchart TD\n  A --> B",
    focusable,
  });
}

function canvasOf(figure: HTMLElement): HTMLElement {
  const canvas = figure.querySelector<HTMLElement>(".bnest-diagram-canvas");
  if (canvas === null) throw new Error("the figure has no canvas");
  return canvas;
}

function overflowing(
  canvas: HTMLElement,
  scrollWidth: number,
  clientWidth: number,
): void {
  Object.defineProperty(canvas, "scrollWidth", {
    configurable: true,
    value: scrollWidth,
  });
  Object.defineProperty(canvas, "clientWidth", {
    configurable: true,
    value: clientWidth,
  });
}

// A resize observer the test calls by hand: the callback of the one observer a placement creates.
class FakeResizeObserver {
  static instances: FakeResizeObserver[] = [];
  constructor(readonly callback: () => void) {
    FakeResizeObserver.instances.push(this);
  }
  observe(): void {}
  disconnect(): void {}
}

afterEach(() => {
  document.body.replaceChildren();
  FakeResizeObserver.instances = [];
  vi.unstubAllGlobals();
});

describe("place a figure", () => {
  it("gives a copy of a figure on the page a closed source", () => {
    const original = figureOf(true);
    document.body.append(original);
    const originalDetails = original.querySelector("details");
    if (originalDetails === null)
      throw new Error("the figure has no source disclosure");
    originalDetails.open = true;

    const pre = document.createElement("pre");
    document.body.append(pre);
    place(CHAT, pre, original);

    const copy = [...document.querySelectorAll("figure.bnest-diagram")].find(
      (figure) => figure !== original,
    );
    expect(copy?.querySelector("details")?.open).toBe(false);
    expect(originalDetails.open).toBe(true);
  });

  it("makes a canvas a keyboard stop only while its picture overflows", () => {
    const fitting = figureOf(true);
    overflowing(canvasOf(fitting), 200, 200);
    const overflowingFigure = figureOf(true);
    overflowing(canvasOf(overflowingFigure), 500, 200);

    const pre = document.createElement("pre");
    document.body.append(pre);
    place(CHAT, pre, fitting);
    const second = document.createElement("pre");
    document.body.append(second);
    place(CHAT, second, overflowingFigure);

    expect(canvasOf(fitting).tabIndex).toBe(-1);
    expect(canvasOf(overflowingFigure).tabIndex).toBe(0);
  });

  it("places a figure that left the page, the cached one, with its source closed", () => {
    // The figure came off the page with its source open (LiveView removed its message); the cache holds it.
    const cached = figureOf(true);
    const details = cached.querySelector("details");
    if (details === null)
      throw new Error("the figure has no source disclosure");
    details.open = true;

    const pre = document.createElement("pre");
    document.body.append(pre);
    place(CHAT, pre, cached);

    expect(cached.querySelector("details")?.open).toBe(false);
  });

  it("measures a picture again when its box is resized after it was placed", () => {
    vi.stubGlobal("ResizeObserver", FakeResizeObserver);
    const figure = figureOf(true);
    overflowing(canvasOf(figure), 200, 200);
    const pre = document.createElement("pre");
    document.body.append(pre);
    place(CHAT, pre, figure);
    expect(canvasOf(figure).tabIndex).toBe(-1);

    // The box narrows, so the picture now overflows; the observer reports the resize.
    overflowing(canvasOf(figure), 500, 200);
    const [observer] = FakeResizeObserver.instances;
    if (observer === undefined)
      throw new Error("no resize observer was made for the placed picture");
    observer.callback();

    expect(canvasOf(figure).tabIndex).toBe(0);
  });
});
