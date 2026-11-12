// @vitest-environment happy-dom
// ADR 004, Decision 5: every colour Mermaid draws comes from a site token, resolved to rgb() before
// drawing, and each text and fill pair reaches WCAG contrast. The hex values are read from app.css, so
// a palette change that breaks contrast fails here.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  THEME_TOKENS,
  pageResolver,
  readThemeVariables,
} from "../../../js/diagrams/diagram_theme.js";

// happy-dom replaces the global URL, so the path is built from the directory, not a URL object.
const APP_CSS = resolve(import.meta.dirname, "../../../css/app.css");
// The Bnest tokens live in the shared chat stylesheet, which app.css imports (ADR 004, Decision 6).
const CHAT_SHARED_CSS = resolve(
  import.meta.dirname,
  "../../../css/chat_shared.css",
);

const EXPECTED_TOKENS: Record<string, string> = {
  background: "--bnest-paper",
  edgeLabelBackground: "--bnest-paper",
  tertiaryColor: "--bnest-paper",
  primaryColor: "--bnest-canvas",
  mainBkg: "--bnest-canvas",
  clusterBkg: "--bnest-canvas",
  actorBkg: "--bnest-canvas",
  secondaryColor: "--bnest-sun-light",
  noteBkgColor: "--bnest-sun-light",
  primaryTextColor: "--bnest-ink",
  secondaryTextColor: "--bnest-ink",
  tertiaryTextColor: "--bnest-ink",
  textColor: "--bnest-ink",
  noteTextColor: "--bnest-ink",
  actorTextColor: "--bnest-ink",
  titleColor: "--bnest-ink",
  primaryBorderColor: "--bnest-ink-soft",
  lineColor: "--bnest-ink-soft",
  nodeBorder: "--bnest-ink-soft",
  clusterBorder: "--bnest-ink-soft",
  actorBorder: "--bnest-ink-soft",
  actorLineColor: "--bnest-ink-soft",
  signalColor: "--bnest-ink-soft",
  pie1: "--bnest-lagoon",
  pie2: "--bnest-sun-light",
  pie3: "--sifat-mustahil",
  pie4: "--sifat-wajib",
  pie5: "--bnest-canvas",
  pie6: "--bnest-paper",
  fontFamily: "--bnest-body",
};

const TEXT_KEYS = [
  "primaryTextColor",
  "secondaryTextColor",
  "tertiaryTextColor",
  "textColor",
  "noteTextColor",
  "actorTextColor",
  "titleColor",
];

const FILL_KEYS = [
  "background",
  "edgeLabelBackground",
  "tertiaryColor",
  "primaryColor",
  "mainBkg",
  "clusterBkg",
  "actorBkg",
  "secondaryColor",
  "noteBkgColor",
  "pie1",
  "pie2",
  "pie3",
  "pie4",
  "pie5",
  "pie6",
];

const LINE_KEYS = [
  "primaryBorderColor",
  "lineColor",
  "nodeBorder",
  "clusterBorder",
  "actorBorder",
  "actorLineColor",
  "signalColor",
];

/** The hex value of every colour token declared in a `:root` block of the shipped stylesheets. */
function cssColours(): Map<string, string> {
  const css = [CHAT_SHARED_CSS, APP_CSS]
    .map((file) => readFileSync(file, "utf8"))
    .join("\n");
  const colours = new Map<string, string>();
  for (const block of css.matchAll(/:root\s*\{([^}]*)\}/gu)) {
    for (const declaration of (block[1] ?? "").matchAll(
      /(--(?:bnest|sifat)-[a-z-]+):\s*(#[0-9a-f]{6})\s*;/giu,
    )) {
      const [, token, hex] = declaration;
      if (token && hex && !colours.has(token)) colours.set(token, hex);
    }
  }
  return colours;
}

const COLOURS = cssColours();

function hexToRgb(hex: string): [number, number, number] {
  const value = Number.parseInt(hex.slice(1), 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

/** The rgb() form a browser returns for a resolved colour, which is what the module receives. */
function rgbOf(token: string): string {
  const hex = COLOURS.get(token);
  if (hex === undefined) throw new Error(`no colour for ${token}`);
  return `rgb(${hexToRgb(hex).join(", ")})`;
}

/** A resolver that answers from app.css, the way the browser answers from the page. */
const cssResolver = (token: string, property: "color" | "font-family") =>
  property === "font-family"
    ? "ui-sans-serif, system-ui, sans-serif"
    : rgbOf(token);

function luminance(rgb: string): number {
  const [r, g, b] = (rgb.match(/\d+/gu) ?? []).map(
    (channel) => Number(channel) / 255,
  ) as [number, number, number];
  const [R, G, B] = [r, g, b].map((c) =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4,
  ) as [number, number, number];
  return 0.2126 * R + 0.7152 * G + 0.0722 * B;
}

function contrast(a: string, b: string): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [
    number,
    number,
  ];
  return (light + 0.05) / (dark + 0.05);
}

describe("theme token mapping", () => {
  it("maps each Mermaid colour to the token ADR 004 names", () => {
    expect(THEME_TOKENS).toEqual(EXPECTED_TOKENS);
  });

  it("is frozen, so a caller cannot change the palette at run time", () => {
    expect(Object.isFrozen(THEME_TOKENS)).toBe(true);
  });
});

describe("readThemeVariables", () => {
  it("resolves every mapped key to the resolved token value", () => {
    const { themeVariables } = readThemeVariables(cssResolver);

    expect(Object.keys(themeVariables).sort()).toEqual(
      Object.keys(EXPECTED_TOKENS).sort(),
    );
    expect(themeVariables["primaryColor"]).toBe(rgbOf("--bnest-canvas"));
    expect(themeVariables["fontFamily"]).toBe(
      "ui-sans-serif, system-ui, sans-serif",
    );
  });

  it("drops a key whose token does not resolve, rather than sending an empty colour", () => {
    const { themeVariables } = readThemeVariables((token, property) =>
      token === "--bnest-ink" ? "" : cssResolver(token, property),
    );

    expect(themeVariables).not.toHaveProperty("textColor");
    expect(themeVariables).toHaveProperty("primaryColor");
  });

  it("gives the same signature for the same tokens and a new one when a token changes", () => {
    const first = readThemeVariables(cssResolver).themeSignature;
    const again = readThemeVariables(cssResolver).themeSignature;
    const changed = readThemeVariables((token, property) =>
      token === "--bnest-paper" ? "rgb(0, 0, 0)" : cssResolver(token, property),
    ).themeSignature;

    expect(again).toBe(first);
    expect(changed).not.toBe(first);
  });
});

describe("contrast of the mapped palette (ADR 004 Decision 5)", () => {
  const { themeVariables } = readThemeVariables(cssResolver);

  it.each(FILL_KEYS)("text reaches 4.5:1 on the %s fill", (fill) => {
    for (const text of TEXT_KEYS) {
      const ratio = contrast(
        themeVariables[text] ?? "",
        themeVariables[fill] ?? "",
      );
      expect(ratio, `${text} on ${fill}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it.each(LINE_KEYS)(
    "%s reaches the 3:1 non-text ratio on the paper and canvas surfaces",
    (line) => {
      for (const surface of ["background", "primaryColor"]) {
        const ratio = contrast(
          themeVariables[line] ?? "",
          themeVariables[surface] ?? "",
        );
        expect(ratio, `${line} on ${surface}`).toBeGreaterThanOrEqual(3);
      }
    },
  );
});

describe("pageResolver", () => {
  it("reads a token through a probe element and leaves no element behind", () => {
    document.documentElement.style.setProperty("--bnest-ink", "#153f42");
    const before = document.body.children.length;

    const colour = pageResolver(document, window)("--bnest-ink", "color");

    // A browser reports rgb(); happy-dom reports the stylesheet value it resolved. Both are the same colour.
    expect(["#153f42", "rgb(21, 63, 66)"]).toContain(colour);
    expect(document.body.children.length).toBe(before);
    document.documentElement.style.removeProperty("--bnest-ink");
  });
});
