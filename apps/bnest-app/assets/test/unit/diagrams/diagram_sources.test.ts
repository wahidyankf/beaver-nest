// ADR 004, Decisions 1 and 3: every module in assets/js/diagrams/ writes DOM with createElement and
// textContent only. These checks read the source text, because they are rules about how the code is
// written, and they cover each file the directory holds, so a new module is checked as well.

import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const DIAGRAMS_DIR = resolve(import.meta.dirname, "../../../js/diagrams");

const moduleFiles = readdirSync(DIAGRAMS_DIR).filter((name) =>
  name.endsWith(".js"),
);

/** Writes that turn a string into markup, or run a string as code. */
const FORBIDDEN =
  /\.innerHTML\b|\.outerHTML\b|insertAdjacentHTML|DOMParser|document\.write|\beval\s*\(|new Function\b/u;

function sourceOf(name: string): string {
  return readFileSync(resolve(DIAGRAMS_DIR, name), "utf8");
}

describe("diagram modules write no markup from a string", () => {
  it("covers every module in the directory", () => {
    expect(moduleFiles).toEqual(
      expect.arrayContaining([
        "chat_diagrams_hook.js",
        "diagram_figure.js",
        "diagram_frame.js",
        "diagram_limits.js",
        "diagram_theme.js",
        "engine.js",
        "engine_config.js",
        "engine_core.js",
        "mermaid_diagrams.js",
      ]),
    );
  });

  it.each(moduleFiles)("%s", (name) => {
    expect(sourceOf(name)).not.toMatch(FORBIDDEN);
  });
});

describe("the engine stays out of the app bundle", () => {
  it("no other module imports the engine statically", () => {
    const staticImporters = moduleFiles.filter(
      (name) =>
        name !== "engine.js" &&
        /^\s*(import|export)\s[^;]*\bfrom\s*["']\.\/engine\.js["']/mu.test(
          sourceOf(name),
        ),
    );

    expect(staticImporters).toEqual([]);
  });

  it("engine.js reaches Mermaid only through a dynamic import, so the page loads none of it", () => {
    const staticCoreImporters = moduleFiles.filter((name) =>
      /^\s*(import|export)\s[^;]*\bfrom\s*["']\.\/engine_core\.js["']/mu.test(
        sourceOf(name),
      ),
    );

    expect(staticCoreImporters).toEqual([]);
    expect(sourceOf("engine.js")).toMatch(
      /import\(\s*["']\.\/engine_core\.js["']\s*\)/u,
    );
  });
});
