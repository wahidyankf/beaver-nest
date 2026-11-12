// @vitest-environment happy-dom
// ADR 004, Decisions 1 and 3: Mermaid's SVG is never written into the page as markup. It is checked, then
// shown as an <img> with a data: URL, and the source is always text. These tests read the built DOM.

import { describe, expect, it } from "vitest";
import {
  FALLBACK_NOTES,
  drawnFigure,
  fallbackFigure,
  setFocusable,
  svgToImage,
} from "../../../js/diagrams/diagram_figure.js";

const PREFIX = "data:image/svg+xml;charset=utf-8,";
const SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 418"><g><rect width="10" height="10"/><text>A</text></g></svg>';
const SOURCE = "flowchart TD\n  A --> B";
const HOSTILE = '<img src="x" onerror="alert(1)"><script>alert(2)</script>';

describe("svgToImage accepts a safe picture", () => {
  it("returns a data URL of the exact SVG, with its size from the viewBox", () => {
    const image = svgToImage(SVG);

    expect(image.src.startsWith(PREFIX)).toBe(true);
    expect(decodeURIComponent(image.src.slice(PREFIX.length))).toBe(SVG);
    expect(image.width).toBe(360);
    expect(image.height).toBe(418);
  });

  it("clamps the size to 1 to 4000 pixels", () => {
    const image = svgToImage('<svg viewBox="0 0 9000 0.5"></svg>');

    expect(image.width).toBe(4000);
    expect(image.height).toBe(1);
  });

  it("accepts an escaped label that only looks like an attribute", () => {
    const svg =
      '<svg viewBox="0 0 10 10"><text>&lt;img onerror=alert(1)&gt;</text></svg>';

    expect(() => svgToImage(svg)).not.toThrow();
  });
});

describe("svgToImage refuses an unsafe or malformed picture", () => {
  it.each([
    ["a script element", '<svg viewBox="0 0 10 10"><script>x()</script></svg>'],
    [
      "an upper-case script element",
      '<svg viewBox="0 0 10 10"><SCRIPT>x()</SCRIPT></svg>',
    ],
    [
      "a foreignObject",
      '<svg viewBox="0 0 10 10"><foreignObject><div>x</div></foreignObject></svg>',
    ],
    ["an iframe", '<svg viewBox="0 0 10 10"><iframe src="x"></iframe></svg>'],
    [
      "an image",
      '<svg viewBox="0 0 10 10"><image href="https://e.test/x.png"/></svg>',
    ],
    ["an on-attribute", '<svg viewBox="0 0 10 10"><rect onload="x()"/></svg>'],
    [
      "a javascript: address",
      '<svg viewBox="0 0 10 10"><a href="javascript:alert(1)"><text>x</text></a></svg>',
    ],
  ])("refuses %s", (_name, svg) => {
    expect(() => svgToImage(svg)).toThrow(/unsafe/u);
  });

  it("refuses text that does not start with an svg element", () => {
    expect(() => svgToImage(`<div viewBox="0 0 10 10">${SVG}</div>`)).toThrow();
  });

  it("refuses an svg without a positive viewBox", () => {
    expect(() => svgToImage('<svg width="10"></svg>')).toThrow();
    expect(() => svgToImage('<svg viewBox="0 0 0 10"></svg>')).toThrow();
    expect(() => svgToImage('<svg viewBox="0 0 -1 10"></svg>')).toThrow();
  });

  it("refuses an svg longer than 300000 characters", () => {
    const big = `<svg viewBox="0 0 10 10">${"<g/>".repeat(100001)}</svg>`;

    expect(() => svgToImage(big)).toThrow();
  });

  it("refuses a value that is not a string", () => {
    expect(() => svgToImage(42 as unknown as string)).toThrow();
  });
});

describe("drawnFigure", () => {
  const image = svgToImage(SVG);

  it("builds the figure, canvas and source as the ADR markup describes", () => {
    const figure = drawnFigure({
      image,
      kind: "Flowchart",
      source: SOURCE,
      focusable: true,
    });

    expect(figure.tagName).toBe("FIGURE");
    expect(figure.className).toBe("bnest-diagram");
    expect(figure.getAttribute("data-bnest-diagram-state")).toBe("drawn");
    expect(figure.getAttribute("aria-live")).toBe("off");

    const canvas = figure.querySelector(".bnest-diagram-canvas");
    expect(canvas?.getAttribute("role")).toBe("img");
    expect(canvas?.getAttribute("aria-label")).toBe(
      "Flowchart. The diagram source follows.",
    );

    const img = canvas?.querySelector("img");
    expect(img?.getAttribute("alt")).toBe("");
    expect(img?.getAttribute("src")).toBe(image.src);
    expect(img?.getAttribute("width")).toBe("360");
    expect(img?.getAttribute("height")).toBe("418");

    const details = figure.querySelector("details.bnest-diagram-source");
    expect(details?.querySelector("summary")?.textContent).toBe(
      "Diagram source",
    );
    expect(details?.querySelector("pre > code")?.textContent).toBe(SOURCE);
  });

  it("keeps a picture that fits out of the tab order in the Codex chat (focusable true)", () => {
    const figure = drawnFigure({
      image,
      kind: "Pie chart",
      source: SOURCE,
      focusable: true,
    });

    expect(
      figure.querySelector(".bnest-diagram-canvas")?.getAttribute("tabindex"),
    ).toBe("-1");
    expect(figure.querySelector("summary")?.hasAttribute("tabindex")).toBe(
      false,
    );
  });

  it("removes the tab stops in Family Chat (focusable false)", () => {
    const figure = drawnFigure({
      image,
      kind: "Pie chart",
      source: SOURCE,
      focusable: false,
    });

    expect(
      figure.querySelector(".bnest-diagram-canvas")?.getAttribute("tabindex"),
    ).toBe("-1");
    expect(figure.querySelector("summary")?.getAttribute("tabindex")).toBe(
      "-1",
    );
  });

  it("shows hostile source as text inside the code element and adds no element", () => {
    const figure = drawnFigure({
      image,
      kind: "Flowchart",
      source: HOSTILE,
      focusable: true,
    });
    const code = figure.querySelector("pre > code");

    expect(code?.textContent).toBe(HOSTILE);
    expect(code?.children).toHaveLength(0);
    expect(figure.querySelectorAll("img")).toHaveLength(1);
    expect(figure.querySelectorAll("script")).toHaveLength(0);
  });
});

describe("setFocusable", () => {
  it("moves the canvas and summary in and out of the tab order", () => {
    const figure = drawnFigure({
      image: svgToImage(SVG),
      kind: "Flowchart",
      source: SOURCE,
      focusable: true,
    });

    const canvas = figure.querySelector<HTMLElement>(".bnest-diagram-canvas");
    if (canvas === null) throw new Error("the figure has no canvas");
    // A picture is a keyboard stop only while it overflows its box, so the box is made to overflow here.
    Object.defineProperty(canvas, "scrollWidth", {
      configurable: true,
      value: 900,
    });
    Object.defineProperty(canvas, "clientWidth", {
      configurable: true,
      value: 300,
    });

    setFocusable(figure, false);
    expect(canvas.getAttribute("tabindex")).toBe("-1");

    setFocusable(figure, true);
    expect(canvas.getAttribute("tabindex")).toBe("0");
    expect(figure.querySelector("summary")?.hasAttribute("tabindex")).toBe(
      false,
    );
  });
});

describe("fallbackFigure", () => {
  it.each([
    // One wording for both phases: the server's refusal note (ChatMarkdown) and the browser's fallback note.
    ["syntax", "Diagram not drawn: it has a syntax error."],
    ["limits", "Diagram not drawn: it is too large."],
    ["timeout", "Diagram not drawn: it took too long to draw."],
    ["unavailable", "Diagram not drawn: the diagram tool did not load."],
    ["unsafe", "Diagram not drawn: its picture failed a safety check."],
    [
      "page-limit",
      "Diagram not drawn: only the first 30 diagrams on a page are drawn.",
    ],
  ])("states the %s reason in a note", (reason, text) => {
    const figure = fallbackFigure({
      reason: reason as keyof typeof FALLBACK_NOTES,
      source: SOURCE,
    });
    const note = figure.querySelector("p.bnest-diagram-note");

    expect(figure.getAttribute("data-bnest-diagram-state")).toBe("fallback");
    expect(figure.getAttribute("data-reason")).toBe(reason);
    expect(note?.getAttribute("role")).toBe("note");
    expect(note?.textContent).toBe(text);
    expect(figure.querySelector("pre > code")?.textContent).toBe(SOURCE);
    expect(figure.querySelector("img")).toBeNull();
  });

  it("uses the syntax wording for a render failure, which 004 does not word separately", () => {
    expect(FALLBACK_NOTES["render"]).toBe(FALLBACK_NOTES["syntax"]);
  });

  it("keeps hostile source as text", () => {
    const figure = fallbackFigure({ reason: "syntax", source: HOSTILE });

    expect(figure.querySelector("pre > code")?.textContent).toBe(HOSTILE);
    expect(figure.querySelector("pre > code")?.children).toHaveLength(0);
    expect(figure.querySelectorAll("script, img")).toHaveLength(0);
  });
});
