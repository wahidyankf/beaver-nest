// ADR 004, Decisions 1 and 4: the engine never writes SVG into the page as markup, only one module
// imports Mermaid, and the ELK layout (EPL-2.0 or GPL-3.0) stays out of the build. These checks read
// the source text, because they are rules about how the code is written.

import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import ElkDisabled from "../../../js/diagrams/elk_disabled.js";

const DIAGRAMS_DIR = new URL("../../../js/diagrams/", import.meta.url);

const engineFiles = [
  "engine.js",
  "engine_core.js",
  "engine_config.js",
  "diagram_frame.js",
  "elk_disabled.js",
];

const FORBIDDEN_DOM_WRITES =
  /\.innerHTML\b|insertAdjacentHTML|DOMParser|\beval\s*\(|new Function\b/;

function sourceOf(name: string): string {
  return readFileSync(new URL(name, DIAGRAMS_DIR), "utf8");
}

describe("engine source", () => {
  it.each(engineFiles)(
    "%s never writes markup from a string into the page",
    (name) => {
      expect(sourceOf(name)).not.toMatch(FORBIDDEN_DOM_WRITES);
    },
  );

  it("only engine_core.js imports mermaid at run time", () => {
    // A JSDoc type reference such as import("mermaid").MermaidConfig loads nothing, so only a static
    // import statement or an awaited dynamic import counts.
    const importsMermaid =
      /^\s*(import|export)\s[^;]*\bfrom\s*["']mermaid["']|await\s+import\(\s*["']mermaid["']\s*\)/m;

    const importers = readdirSync(DIAGRAMS_DIR).filter((name) =>
      name.endsWith(".js") ? importsMermaid.test(sourceOf(name)) : false,
    );

    expect(importers).toEqual(["engine_core.js"]);
  });
});

describe("ELK stub", () => {
  it("refuses to run, so no ELK layout can be drawn in this build", () => {
    // Mermaid constructs the layout with `new`; Reflect.construct does the same and types cleanly.
    expect(() => Reflect.construct(ElkDisabled, [])).toThrow(
      /not part of this build/,
    );
  });
});
