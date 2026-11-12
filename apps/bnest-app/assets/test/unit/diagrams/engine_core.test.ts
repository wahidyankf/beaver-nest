// @vitest-environment happy-dom
// ADR 004, Decision 3: engine_core.js is the only module that imports Mermaid. Real layout needs a browser
// (getBBox), so Mermaid is replaced here by a fake that records its calls. Drawing in Chromium is
// verified by the smoke check and the end-to-end suite, not here.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mermaid = vi.hoisted(() => ({
  initialize: vi.fn(),
  parse: vi.fn(),
  render: vi.fn(),
}));

vi.mock("mermaid", () => ({ default: mermaid }));

import {
  DiagramError,
  renderDiagram,
} from "../../../js/diagrams/engine_core.js";

const THEME = { primaryColor: "rgb(216, 241, 236)" };
const SOURCE = "flowchart TD\n  A --> B";

/** A render that draws into the body the way Mermaid does, with its temporary element. */
function rendersInBody(svg: string) {
  mermaid.render.mockImplementation(async (id: string) => {
    const holder = document.createElement("div");
    holder.id = `d${id}`;
    holder.innerHTML = svg;
    document.body.appendChild(holder);
    return { svg };
  });
}

describe("renderDiagram success", () => {
  beforeEach(() => {
    mermaid.initialize.mockReset();
    mermaid.parse.mockReset().mockResolvedValue({ diagramType: "flowchart" });
    mermaid.render.mockReset();
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("initializes Mermaid with the strict config before it parses", async () => {
    rendersInBody("<svg></svg>");

    await renderDiagram(SOURCE, THEME);

    expect(mermaid.initialize).toHaveBeenCalledWith(
      expect.objectContaining({
        securityLevel: "strict",
        htmlLabels: false,
        startOnLoad: false,
        theme: "base",
      }),
    );
    expect(mermaid.initialize.mock.invocationCallOrder[0]).toBeLessThan(
      mermaid.parse.mock.invocationCallOrder[0] ?? Infinity,
    );
  });

  it("resolves to the SVG Mermaid drew, unchanged", async () => {
    const svg = '<svg viewBox="0 0 10 10"><text>A</text></svg>';
    rendersInBody(svg);

    const result = await renderDiagram(SOURCE, THEME);

    expect(result).toStrictEqual({ svg });
  });

  it("renders the exact source text", async () => {
    rendersInBody("<svg></svg>");

    await renderDiagram(SOURCE, THEME);

    expect(mermaid.render).toHaveBeenCalledWith(expect.any(String), SOURCE);
  });

  it("uses a different DOM id for every render on the page", async () => {
    rendersInBody("<svg></svg>");

    await renderDiagram(SOURCE, THEME);
    await renderDiagram(SOURCE, THEME);

    const [firstId] = mermaid.render.mock.calls[0] ?? [];
    const [secondId] = mermaid.render.mock.calls[1] ?? [];
    expect(firstId).toEqual(expect.any(String));
    expect(secondId).toEqual(expect.any(String));
    expect(firstId).not.toBe(secondId);
  });

  it("removes the temporary element Mermaid left in the body", async () => {
    rendersInBody("<svg></svg>");

    await renderDiagram(SOURCE, THEME);

    expect(document.body.querySelector("[id^='d']")).toBeNull();
    expect(document.body.children).toHaveLength(0);
  });
});

describe("renderDiagram failures", () => {
  beforeEach(() => {
    mermaid.initialize.mockReset();
    mermaid.parse.mockReset().mockResolvedValue({ diagramType: "flowchart" });
    mermaid.render.mockReset();
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("reports a parser refusal as kind syntax and never renders", async () => {
    mermaid.parse.mockRejectedValue(new Error("Parse error on line 2"));

    const error = await renderDiagram(SOURCE, THEME).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(DiagramError);
    expect((error as DiagramError).kind).toBe("syntax");
    expect(mermaid.render).not.toHaveBeenCalled();
  });

  it("reports text over the size limit as kind limits, before Mermaid sees it", async () => {
    const tooLong = `flowchart TD\n${"  A --> B\n".repeat(700)}`;

    const error = await renderDiagram(tooLong, THEME).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(DiagramError);
    expect((error as DiagramError).kind).toBe("limits");
    expect(mermaid.parse).not.toHaveBeenCalled();
    expect(mermaid.render).not.toHaveBeenCalled();
  });

  it("reports Mermaid's edge limit as kind limits", async () => {
    mermaid.parse.mockRejectedValue(
      new Error("Edge limit exceeded. 61 edges found, but the limit is 60."),
    );

    const error = await renderDiagram(SOURCE, THEME).catch((e: unknown) => e);

    expect((error as DiagramError).kind).toBe("limits");
  });

  it("reports a Mermaid failure after a valid parse as kind render", async () => {
    mermaid.render.mockRejectedValue(new Error("layout exploded"));

    const error = await renderDiagram(SOURCE, THEME).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(DiagramError);
    expect((error as DiagramError).kind).toBe("render");
  });

  it("removes the temporary element even when the render fails", async () => {
    mermaid.render.mockImplementation(async (id: string) => {
      const holder = document.createElement("div");
      holder.id = `d${id}`;
      document.body.appendChild(holder);
      throw new Error("layout exploded");
    });

    await renderDiagram(SOURCE, THEME).catch(() => undefined);

    expect(document.body.children).toHaveLength(0);
  });

  it("rejects a source that is not a string with a TypeError", async () => {
    await expect(
      renderDiagram(42 as unknown as string, THEME),
    ).rejects.toBeInstanceOf(TypeError);
  });
});

// A render Mermaid never settles is not cut off here: the page's draw timeout ends the draw and discards this engine
// (diagram_draw.js). What this module owns is the temporary element of a draw, removed whatever the outcome.
describe("renderDiagram cleanup", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("removes the temporary element of a render that fails", async () => {
    mermaid.parse.mockResolvedValue({ diagramType: "flowchart" });
    mermaid.render.mockReset().mockImplementation(async (id: string) => {
      const holder = document.createElement("div");
      holder.id = `d${id}`;
      document.body.append(holder);
      throw new Error("the render broke");
    });

    await expect(renderDiagram(SOURCE, THEME)).rejects.toMatchObject({
      kind: "render",
    });

    expect(document.body.querySelector("div[id^='d']")).toBeNull();
  });
});
