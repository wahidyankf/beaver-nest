import { readFileSync } from "node:fs";
import path from "node:path";
// ADR 004, Decisions 1 and 3: the Mermaid configuration is strict, draws labels as text, and carries the
// diagram limits. The config module is pure, so these tests never load Mermaid.

import { describe, expect, it } from "vitest";
import { LIMITS, mermaidConfig } from "../../../js/diagrams/engine_config.js";

const THEME = {
  primaryColor: "rgb(216, 241, 236)",
  primaryTextColor: "rgb(21, 63, 66)",
  fontFamily: "system-ui, sans-serif",
};

describe("mermaidConfig security", () => {
  it("runs in strict mode and never starts on load", () => {
    const config = mermaidConfig(THEME);

    expect(config.securityLevel).toBe("strict");
    expect(config.startOnLoad).toBe(false);
  });

  it("keeps Mermaid's protected keys and the label keys out of reach of a directive", () => {
    const config = mermaidConfig(THEME);

    expect(config.secure).toEqual(
      expect.arrayContaining([
        "secure",
        "securityLevel",
        "startOnLoad",
        "maxTextSize",
        "suppressErrorRendering",
        "maxEdges",
        "htmlLabels",
        "flowchart",
      ]),
    );
  });

  it("never logs above fatal, so diagram source is not echoed to the console", () => {
    expect(mermaidConfig(THEME).logLevel).toBe("fatal");
  });

  it("suppresses Mermaid's own error diagram, because the browser shows the source instead", () => {
    expect(mermaidConfig(THEME).suppressErrorRendering).toBe(true);
  });
});

describe("mermaidConfig layout", () => {
  it("lays diagrams out with dagre, because Mermaid's default ELK layout is not shipped in this build", () => {
    // Mermaid's default config names `elk`; every diagram reads this top-level key, so without it a
    // flowchart asks for the ELK loader, which is a stub that refuses to run.
    expect(mermaidConfig(THEME).layout).toBe("dagre");
  });

  it("keeps the layout key out of reach of a directive, so ELK cannot be selected from a diagram", () => {
    expect(mermaidConfig(THEME).secure).toContain("layout");
  });
});

describe("mermaidConfig labels", () => {
  it("draws labels as text at the top level and for flowcharts", () => {
    const config = mermaidConfig(THEME);

    expect(config.htmlLabels).toBe(false);
    expect(config.flowchart?.htmlLabels).toBe(false);
  });

  it("uses the base theme, so the theme variables decide every colour", () => {
    expect(mermaidConfig(THEME).theme).toBe("base");
  });
});

describe("mermaidConfig limits", () => {
  it("sets the 004 limits from one exported source", () => {
    const config = mermaidConfig(THEME);

    expect(LIMITS).toEqual({ maxTextSize: 6000, maxEdges: 60 });
    expect(config.maxTextSize).toBe(LIMITS.maxTextSize);
    expect(config.maxEdges).toBe(LIMITS.maxEdges);
  });
});

describe("mermaidConfig theme", () => {
  it("passes the string theme variables through unchanged", () => {
    const config = mermaidConfig(THEME);

    expect(config.themeVariables).toEqual(THEME);
  });

  it("drops any theme value that is not a string", () => {
    const config = mermaidConfig({
      primaryColor: "rgb(1, 2, 3)",
      nested: { evil: true },
      count: 4,
    });

    expect(config.themeVariables).toEqual({ primaryColor: "rgb(1, 2, 3)" });
  });

  it("takes the font from the theme", () => {
    expect(mermaidConfig({ fontFamily: "Georgia, serif" }).fontFamily).toBe(
      "Georgia, serif",
    );
  });

  it("falls back to a system font stack when the theme gives none", () => {
    expect(mermaidConfig({}).fontFamily).toBe("system-ui, sans-serif");
  });

  it("returns a new object each call, so one caller cannot change the next draw", () => {
    const first = mermaidConfig(THEME);
    first.secure?.push("injected");
    first.themeVariables = {};

    const second = mermaidConfig(THEME);

    expect(second.secure).not.toContain("injected");
    expect(second.themeVariables).toEqual(THEME);
  });
});

// ADR 004, Decision 2: the edge cap and the text cap are written once, in diagram_limits.js, which the renderer
// checks before a draw. A second literal here could drift from it, so this reads the module's text.
describe("the shared limits", () => {
  const source = readFileSync(
    path.resolve(import.meta.dirname, "../../../js/diagrams/engine_config.js"),
    "utf8",
  );

  it("imports its limits from diagram_limits.js", () => {
    expect(source).toMatch(/from "\.\/diagram_limits\.js"/u);
  });

  it("does not write the edge cap or the text cap as a number of its own", () => {
    expect(source).not.toMatch(/\bmaxEdges:\s*\d/u);
    expect(source).not.toMatch(/\bmaxTextSize:\s*\d/u);
  });
});
