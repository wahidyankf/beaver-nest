// Plain Vitest unit coverage for the text colour of a Codex visitor's own (dark) message bubble (ADR 005, decision 4).
// The bubble fills with `--bnest-ink`, and its Markdown body reads `--chat-ink`, which is the light bubble's ink. The
// bubble must redefine that token to the light paper colour, so the text reads light on dark. The colours come from the
// shipped token layer, so no value is copied here.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const here = path.dirname(fileURLToPath(import.meta.url));
const CSS_DIR = path.resolve(here, "../../css");
const stylesheet = ["chat_shared.css", "app.css"]
  .map((file) => readFileSync(path.resolve(CSS_DIR, file), "utf8"))
  .join("\n")
  .replace(/\/\*[\s\S]*?\*\//gu, "");

/** The hex colour a token declares in the shared token layer. */
function tokenHex(name: string): string {
  const match = new RegExp(`--${name}:\\s*(#[0-9a-fA-F]{6})`, "u").exec(
    stylesheet,
  );
  if (!match?.[1]) throw new Error(`the stylesheets declare no --${name}`);
  return match[1];
}

/** The declarations a selector takes from every rule that names exactly it, later rules winning as the cascade does. */
function declarationsOf(selector: string): Record<string, string> {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
  const pattern = new RegExp(`(?:^|\\})\\s*${escaped}\\s*\\{([^}]*)\\}`, "gu");
  const declarations: Record<string, string> = {};
  for (const match of stylesheet.matchAll(pattern)) {
    for (const declaration of (match[1] ?? "").split(";")) {
      const separator = declaration.indexOf(":");
      if (separator === -1) continue;
      declarations[declaration.slice(0, separator).trim()] = declaration
        .slice(separator + 1)
        .trim();
    }
  }
  if (Object.keys(declarations).length === 0)
    throw new Error(`no rule for ${selector}`);
  return declarations;
}

/** WCAG relative luminance of a `#rrggbb` colour. */
function luminance(hex: string): number {
  const channels = [1, 3, 5].map((offset) => {
    const value = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  const [red = 0, green = 0, blue = 0] = channels;
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrast(first: string, second: string): number {
  const [light, dark] = [luminance(first), luminance(second)].toSorted(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

describe("the Codex visitor's own bubble", () => {
  it("fills with the dark ink and reads the light paper for its Markdown body", () => {
    const bubble = declarationsOf(".message-visitor");

    expect(bubble["background"]).toBe("var(--bnest-ink)");
    expect(bubble["--chat-ink"]).toBe("var(--bnest-paper)");
  });

  it("gives the body text at least 4.5 to 1 against the bubble fill", () => {
    const text = tokenHex("bnest-paper");
    const fill = tokenHex("bnest-ink");

    expect(contrast(text, fill)).toBeGreaterThanOrEqual(4.5);
  });

  it("reads the Show raw label in the light paper, not the bubble's dark ink", () => {
    // The toggle sits inside the dark bubble, so its label takes the bubble's light text token.
    expect(declarationsOf(".own-raw-toggle")["color"]).toBe("var(--chat-ink)");
    expect(
      contrast(tokenHex("bnest-paper"), tokenHex("bnest-ink")),
    ).toBeGreaterThanOrEqual(4.5);
  });

  it("draws the Show raw focus ring in the light sun colour, 3 to 1 or more against the bubble", () => {
    expect(declarationsOf(".message-visitor")["--chat-focus-ring"]).toBe(
      "var(--bnest-sun-light)",
    );
    expect(
      declarationsOf(".own-raw-toggle:focus-visible")["outline"],
    ).toContain("var(--chat-focus-ring)");
    expect(
      contrast(tokenHex("bnest-sun-light"), tokenHex("bnest-ink")),
    ).toBeGreaterThanOrEqual(3);
  });
});

describe("the Family own bubble", () => {
  it("reads light paper on its dark-teal fill at 4.5 to 1 or more", () => {
    const bubble = declarationsOf(
      ".family-chat-message--own .family-chat-message-bubble",
    );

    expect(bubble["background"]).toBe("var(--bnest-ink-soft)");
    expect(bubble["color"]).toBe("var(--bnest-paper)");
    expect(
      contrast(tokenHex("bnest-paper"), tokenHex("bnest-ink-soft")),
    ).toBeGreaterThanOrEqual(4.5);
  });
});
