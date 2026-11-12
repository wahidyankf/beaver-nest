// The diagram stylesheet (`css/diagrams.css`), read as text for the Vitest adapters of both chat rooms.
//
// happy-dom has no layout engine, and a computed style cannot show a `var()` expression, so a binding checks the
// declared block: the picture's width rule, the canvas's overflow rule. The rendered sizes are measured in Chromium
// by `bnest-app-fe-e2e`, which is the proof that the picture is readable and scrolls.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const DIAGRAM_CSS_TEXT = readFileSync(
  path.resolve(here, "../../css/diagrams.css"),
  "utf8",
);

/** The picture's declared width: the natural width, never less than the readable minimum (ADR 004, Decision 5). */
export const PICTURE_WIDTH_RULE =
  "width: min(var(--bnest-diagram-width), max(100%, 30rem, calc(var(--bnest-diagram-width) * 0.75)));";

export const PICTURE_SELECTOR = ".bnest-diagram .bnest-diagram-canvas img";
export const CANVAS_SELECTOR = ".bnest-diagram-canvas";

/**
 * A declaration block of diagrams.css with its whitespace collapsed. The formatter may wrap a long value over several
 * lines, so the whitespace just inside a parenthesis is dropped too: `min(\n  a,\n  b\n)` reads as `min(a, b)`. The
 * tokens themselves are compared exactly.
 */
export function declaredDiagramBlock(selector: string): string {
  const escaped = selector.replaceAll(".", "\\.").replaceAll(" ", "\\s+");
  const match = new RegExp(`${escaped}\\s*\\{([^}]*)\\}`, "u").exec(
    DIAGRAM_CSS_TEXT,
  );
  if (!match) throw new Error(`diagrams.css declares no ${selector} block`);
  return (match[1] ?? "")
    .replace(/\s+/gu, " ")
    .replace(/\(\s/gu, "(")
    .replace(/\s\)/gu, ")");
}
