// Plain Vitest unit coverage for the focus ring of a keyboard stop inside an own (dark) message bubble (ADR 003,
// Decision 6, rule 8; ADR 004, Decision 6, task 2). The coral ring is about 2.3:1 against the own bubble, below the 3:1
// a non-text indicator needs (WCAG 1.4.11). Every stop kind draws its ring with `--chat-focus-ring`, and the own bubble
// sets that token to `--bnest-sun-light`. The rules are read from the shipped stylesheets and the colours from the token
// layer, so neither is copied here.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const here = path.dirname(fileURLToPath(import.meta.url));
const CSS_DIR = path.resolve(here, "../../../css");
const stylesheet = ["chat_shared.css", "diagrams.css", "app.css"]
  .map((file) => readFileSync(path.resolve(CSS_DIR, file), "utf8"))
  .join("\n")
  .replace(/\/\*[\s\S]*?\*\//gu, "");

/** The colour a token declares in the shared token layer. */
function tokenValue(name: string): string {
  const match = new RegExp(`--${name}:\\s*(#[0-9a-fA-F]{6})`, "u").exec(
    stylesheet,
  );
  if (!match) throw new Error(`the stylesheets declare no --${name}`);
  return match[1] ?? "";
}

/** The value a rule ending with `selectorSuffix` declares for `property`, or undefined when no such rule does. */
function declarationOf(
  selectorSuffix: string,
  property: string,
): string | undefined {
  // The property names used here (`outline`, `display`, `--chat-focus-ring`) hold no regex metacharacters, and under the
  // `u` flag a hyphen needs no escape outside a character class.
  const pattern = new RegExp(`(?:^|;|\\s)${property}\\s*:\\s*([^;]+)`, "u");
  for (const match of stylesheet.matchAll(/([^{}]+)\{([^{}]*)\}/gu)) {
    const selectors = (match[1] ?? "").split(",").map((part) => part.trim());
    if (!selectors.some((selector) => selector.endsWith(selectorSuffix)))
      continue;
    const value = pattern.exec(match[2] ?? "")?.[1];
    if (value !== undefined) return value.trim();
  }
  return undefined;
}

function luminance(hex: string): number {
  const channels = [1, 3, 5].map(
    (offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255,
  );
  const [red, green, blue] = channels.map((value) =>
    value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4,
  ) as [number, number, number];
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrast(first: string, second: string): number {
  const [lighter, darker] = [luminance(first), luminance(second)].sort(
    (a, b) => b - a,
  ) as [number, number];
  return (lighter + 0.05) / (darker + 0.05);
}

// Each stop kind a keyboard reader can reach inside a message (ADR 003, Decision 6, rule 2).
const STOP_KINDS = [
  ".markdown-body a",
  ".markdown-body table",
  ".markdown-body pre",
  ".bnest-diagram-canvas",
  ".bnest-diagram-source summary",
];

describe("the focus ring inside an own message bubble", () => {
  it.each(STOP_KINDS)(
    "draws %s with the focus-ring token, not a literal coral",
    (kind) => {
      const outline = declarationOf(`${kind}:focus-visible`, "outline");

      expect(outline, `no focus ring for ${kind}`).toBeDefined();
      expect(outline).toContain("var(--chat-focus-ring)");
      expect(outline).not.toContain("var(--bnest-coral)");
    },
  );

  it("sets the focus-ring token to the light sun colour on the own bubble", () => {
    expect(
      declarationOf(
        ".family-chat-message--own .family-chat-message-bubble",
        "--chat-focus-ring",
      ),
    ).toBe("var(--bnest-sun-light)");
  });

  it("keeps no own-bubble outline override that would bypass the token", () => {
    expect(
      declarationOf(
        ".family-chat-message--own .markdown-body a:focus-visible",
        "outline",
      ),
    ).toBeUndefined();
    expect(
      declarationOf(
        ".family-chat-message--own .bnest-diagram-canvas:focus-visible",
        "outline",
      ),
    ).toBeUndefined();
  });

  it("gives the light sun ring at least 3:1 against the own bubble, where coral falls short", () => {
    const bubble = tokenValue("bnest-ink-soft");

    expect(
      contrast(tokenValue("bnest-sun-light"), bubble),
    ).toBeGreaterThanOrEqual(3);
    expect(contrast(tokenValue("bnest-coral"), bubble)).toBeLessThan(3);
  });
});
