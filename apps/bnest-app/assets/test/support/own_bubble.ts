// The text colours of the inline elements a Markdown body renders inside the Family Chat own (dark) bubble, read from
// the shipped stylesheets through `shipped_css.ts`. Both the unit proof and the behaviour binding use these, so a rule
// that colours an element with a light-bubble literal fails in both.

import {
  declarationsFor,
  hexOf,
  resolveVars,
  type Environment,
} from "./shipped_css";

export const OWN_BUBBLE =
  ".family-chat-message--own .family-chat-message-bubble";
// Colours do not depend on the width: the own bubble redefines its tokens at every width.
const OWN_ENV: Environment = { width: 1024, height: 768, coarse: false };

/**
 * The declarations an element takes inside the own bubble: a rule scoped to the own bubble wins over the element's own
 * rule, as the cascade does, so an override such as a header tint is the value measured.
 */
function ownDeclaration(
  elementSelector: string,
  property: string,
): string | undefined {
  const scoped = declarationsFor(`${OWN_BUBBLE} ${elementSelector}`, OWN_ENV)[
    property
  ];
  return scoped ?? declarationsFor(elementSelector, OWN_ENV)[property];
}

/** The colour an element's text takes inside the own bubble: its own colour rule, else the body's ink. */
export function ownTextColour(elementSelector: string): string {
  const own = declarationsFor(OWN_BUBBLE, OWN_ENV);
  const declared =
    ownDeclaration(elementSelector, "color") ?? "var(--chat-ink)";
  // A token the own bubble redefines takes the own value; the rest resolve to their shipped value.
  const token = /^var\((--[\w-]+)\)$/u.exec(declared.trim())?.[1];
  if (token !== undefined && own[token] !== undefined) return hexOf(own[token]);
  return hexOf(declared);
}

/** The own bubble's fill, from its surface token. */
export function ownBubbleFill(): string {
  return hexOf(
    declarationsFor(OWN_BUBBLE, OWN_ENV)["--markdown-surface"] ?? "",
  );
}

type Rgb = readonly [number, number, number];

function rgbOf(hex: string): Rgb {
  const match = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/iu.exec(hex.trim());
  if (!match) throw new Error(`not a #rrggbb colour: ${JSON.stringify(hex)}`);
  return [1, 2, 3].map((index) =>
    parseInt(match[index] ?? "", 16),
  ) as unknown as Rgb;
}

/**
 * A declared colour as a colour and an opacity. Tokens are resolved first, so `var(--chat-code-bg)` is read as the
 * `color-mix()` it names. Only the two forms the stylesheets use are read; any other value throws, so a new form is
 * noticed rather than measured wrongly.
 */
function layerOf(value: string): { colour: Rgb; alpha: number } {
  // A token can name another token (`--chat-code-bg` names `--bnest-ink`), so resolve until none is left.
  let resolved = value.trim();
  for (let depth = 0; resolved.includes("var("); depth += 1) {
    if (depth > 4)
      throw new Error(`a colour's tokens do not resolve: ${value}`);
    resolved = resolveVars(resolved).trim();
  }
  const mix =
    /^color-mix\(in srgb,\s*(#[0-9a-f]{6})\s+(\d+(?:\.\d+)?)%,\s*transparent\)$/iu.exec(
      resolved,
    );
  if (mix) return { colour: rgbOf(mix[1] ?? ""), alpha: Number(mix[2]) / 100 };
  return { colour: rgbOf(resolved), alpha: 1 };
}

/** The colour of a layer painted over a backdrop, channel by channel (source-over). */
function over(layer: { colour: Rgb; alpha: number }, backdrop: Rgb): Rgb {
  return layer.colour.map(
    (channel, index) =>
      layer.alpha * channel + (1 - layer.alpha) * (backdrop[index] ?? 0),
  ) as unknown as Rgb;
}

function luminanceOf(colour: Rgb): number {
  const [red, green, blue] = colour.map((channel) => {
    const scaled = channel / 255;
    return scaled <= 0.03928
      ? scaled / 12.92
      : ((scaled + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (red ?? 0) + 0.7152 * (green ?? 0) + 0.0722 * (blue ?? 0);
}

function ratioOf(first: Rgb, second: Rgb): number {
  const [light, dark] = [luminanceOf(first), luminanceOf(second)].sort(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

/**
 * The colour an inline element's text sits on: the element's own background (a translucent one is blended onto the
 * own bubble's fill, as a browser paints it), or the fill itself when the element has none.
 */
export function ownBackdropOf(elementSelector: string): Rgb {
  const fill = rgbOf(ownBubbleFill());
  const painted =
    ownDeclaration(elementSelector, "background-color") ??
    ownDeclaration(elementSelector, "background");
  if (painted === undefined || painted.trim() === "none") return fill;
  return over(layerOf(painted), fill);
}

/** The WCAG contrast of an inline element's text on what it sits on (its own background over the own fill). */
export function ownInlineContrast(elementSelector: string): number {
  return ratioOf(
    rgbOf(ownTextColour(elementSelector)),
    ownBackdropOf(elementSelector),
  );
}
