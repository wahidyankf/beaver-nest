// The shipped stylesheet, read the way a browser cascades it for one viewport and one pointer.
//
// happy-dom has no layout engine, so a layout scenario's Vitest binding checks the declared values that the
// browser would use for that viewport: the media rules that apply, the later rule that wins, and the tokens a
// `var()` names. The rendered sizes are measured by the Playwright adapter (`bnest-app-fe-e2e`). Only the
// subset of CSS these stylesheets use is understood: style rules, one level of nested `@media`, and the
// length, colour and media features the chat rooms declare. An unknown media feature never matches.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const CSS_DIR = path.resolve(here, "../../css");
// The files the page loads: app.css imports the other two (ADR 004, Decision 6; the shared chat rules).
const SHIPPED_FILES = ["chat_shared.css", "diagrams.css", "app.css"] as const;

/** The rem size a browser uses for the page, in CSS pixels. */
const ROOT_PX = 16;

export interface Environment {
  readonly width: number;
  readonly height: number;
  readonly coarse: boolean;
}

interface StyleRule {
  readonly media: string | null;
  readonly selectors: readonly string[];
  readonly declarations: Readonly<Record<string, string>>;
}

let cachedRules: StyleRule[] | null = null;

function stripComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//gu, "");
}

/** The index of the `}` that closes the `{` at `open`. */
function closingBrace(css: string, open: number): number {
  let depth = 0;
  for (let index = open; index < css.length; index += 1) {
    if (css[index] === "{") depth += 1;
    if (css[index] === "}") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return css.length;
}

/** Splits a declaration block at semicolons that sit outside parentheses. */
function declarationsOf(body: string): Record<string, string> {
  const parts: string[] = [];
  let depth = 0;
  let current = "";
  for (const character of body) {
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
    if (character === ";" && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += character;
    }
  }
  parts.push(current);
  const declarations: Record<string, string> = {};
  for (const part of parts) {
    const colon = part.indexOf(":");
    if (colon < 0) continue;
    const property = part.slice(0, colon).trim().toLowerCase();
    if (property === "") continue;
    declarations[property] = part
      .slice(colon + 1)
      .replace(/\s+/gu, " ")
      .trim();
  }
  return declarations;
}

function collectRules(
  css: string,
  media: string | null,
  rules: StyleRule[],
): void {
  let index = 0;
  while (index < css.length) {
    const brace = css.indexOf("{", index);
    if (brace < 0) return;
    const semicolon = css.indexOf(";", index);
    if (semicolon >= 0 && semicolon < brace) {
      // A block-less at-rule such as `@import "x";` or `@source "x";`.
      index = semicolon + 1;
      continue;
    }
    const prelude = css.slice(index, brace).trim();
    const end = closingBrace(css, brace);
    const body = css.slice(brace + 1, end);
    if (prelude.startsWith("@media")) {
      const query = prelude.slice("@media".length).trim();
      collectRules(
        body,
        media === null ? query : `(${media}) and (${query})`,
        rules,
      );
    } else if (!prelude.startsWith("@")) {
      rules.push({
        media,
        selectors: prelude
          .split(",")
          .map((selector) => selector.replace(/\s+/gu, " ").trim()),
        declarations: declarationsOf(body),
      });
    }
    index = end + 1;
  }
}

function allRules(): StyleRule[] {
  if (cachedRules !== null) return cachedRules;
  const rules: StyleRule[] = [];
  for (const file of SHIPPED_FILES) {
    collectRules(
      stripComments(readFileSync(path.join(CSS_DIR, file), "utf8")),
      null,
      rules,
    );
  }
  cachedRules = rules;
  return rules;
}

/**
 * Every sizing rule of an image the shipped stylesheet declares for this environment: the selector that names an
 * `img`, and the `max-width` or `width` it sets there. A later rule's value is listed as well as an earlier one's.
 * Values are returned as written: a `var()` is not resolved, because a diagram's width is set by its script at run
 * time, which no stylesheet declares.
 */
export function imageSizingRules(
  env: Environment,
): { selector: string; property: string; value: string }[] {
  const found: { selector: string; property: string; value: string }[] = [];
  for (const rule of allRules()) {
    if (rule.media !== null && !mediaMatches(rule.media, env)) continue;
    for (const selector of rule.selectors) {
      if (!/\bimg\b/u.test(selector)) continue;
      for (const property of ["max-width", "width"]) {
        const value = rule.declarations[property];
        if (value !== undefined)
          found.push({ selector, property, value: value });
      }
    }
  }
  return found;
}

/** The value a `--bnest-*` (or any) custom property holds on `:root`, with its own `var()` references resolved. */
function tokenValue(name: string): string {
  let value: string | undefined;
  for (const rule of allRules()) {
    if (
      rule.media === null &&
      rule.selectors.includes(":root") &&
      rule.declarations[name] !== undefined
    ) {
      value = rule.declarations[name];
    }
  }
  if (value === undefined)
    throw new Error(`the shipped stylesheet declares no ${name}`);
  return resolveVars(value);
}

/** Replaces every `var(--token)` in a value with the token's own value. */
export function resolveVars(value: string): string {
  return value.replace(/var\((--[\w-]+)\)/gu, (_match, name: string) =>
    tokenValue(name),
  );
}

function px(value: string): number {
  const match = /^(-?\d*\.?\d+)(px|rem|em)?$/u.exec(value.trim());
  if (!match) return Number.NaN;
  const amount = Number(match[1]);
  return match[2] === "rem" || match[2] === "em" ? amount * ROOT_PX : amount;
}

function compare(actual: number, operator: string, expected: number): boolean {
  if (operator === "<=") return actual <= expected;
  if (operator === ">=") return actual >= expected;
  if (operator === "<") return actual < expected;
  if (operator === ">") return actual > expected;
  return actual === expected;
}

function featureMatches(feature: string, env: Environment): boolean {
  const range = /^(width|height)\s*(<=|>=|<|>|=)\s*(.+)$/u.exec(feature);
  if (range) {
    const actual = range[1] === "width" ? env.width : env.height;
    return compare(actual, range[2] ?? "=", px(range[3] ?? ""));
  }
  const pair = /^([a-z-]+)\s*:\s*(.+)$/u.exec(feature);
  if (!pair) return false;
  const [, name = "", value = ""] = pair;
  if (name === "max-width") return env.width <= px(value);
  if (name === "min-width") return env.width >= px(value);
  if (name === "max-height") return env.height <= px(value);
  if (name === "min-height") return env.height >= px(value);
  if (name === "pointer")
    return value === "coarse" ? env.coarse : value === "fine" && !env.coarse;
  if (name === "prefers-reduced-motion") return value === "no-preference";
  return false;
}

/** Whether a media query list holds for the environment: commas are alternatives, `and` joins features. */
export function mediaMatches(query: string, env: Environment): boolean {
  return query.split(",").some((alternative) =>
    alternative.split(/\s+and\s+/u).every((term) => {
      const trimmed = term.trim();
      if (!trimmed.startsWith("("))
        return trimmed === "screen" || trimmed === "all";
      return featureMatches(trimmed.replace(/^\(|\)$/gu, "").trim(), env);
    }),
  );
}

/** The declarations a browser applies to `selector` in this environment; a later rule overrides an earlier one. */
export function declarationsFor(
  selector: string,
  env: Environment,
): Record<string, string> {
  const declared: Record<string, string> = {};
  for (const rule of allRules()) {
    if (!rule.selectors.includes(selector)) continue;
    if (rule.media !== null && !mediaMatches(rule.media, env)) continue;
    Object.assign(declared, rule.declarations);
  }
  return declared;
}

/**
 * A length in CSS pixels for this environment: px, rem, em, vh, svh, dvh, min() or max() of those, and calc() with one
 * `+` or `-` between two such lengths (the only calc forms the shipped rules use). A clamp() is its preferred value kept
 * between the minimum and the maximum.
 */
export function lengthPx(value: string, env: Environment): number {
  const trimmed = value.trim();
  const fn = /^(min|max)\((.*)\)$/u.exec(trimmed);
  if (fn) {
    const parts = (fn[2] ?? "").split(",").map((part) => lengthPx(part, env));
    return fn[1] === "min" ? Math.min(...parts) : Math.max(...parts);
  }
  // clamp(minimum, preferred, maximum), with each argument a length of the forms above.
  const clamped = /^clamp\((.*)\)$/u.exec(trimmed);
  if (clamped) {
    const [low = "", preferred = "", high = ""] = (clamped[1] ?? "").split(",");
    return Math.min(
      Math.max(lengthPx(low, env), lengthPx(preferred, env)),
      lengthPx(high, env),
    );
  }
  const calc = /^calc\((.*)\)$/u.exec(trimmed);
  if (calc) {
    const operands = /^(.*\S)\s+([+-])\s+(\S.*)$/u.exec(calc[1] ?? "");
    if (!operands) return Number.NaN;
    const left = lengthPx(operands[1] ?? "", env);
    const right = lengthPx(operands[3] ?? "", env);
    return operands[2] === "+" ? left + right : left - right;
  }
  const match = /^(-?\d*\.?\d+)(px|rem|em|vw|vh|svh|dvh)?$/u.exec(trimmed);
  if (!match) return Number.NaN;
  const amount = Number(match[1]);
  if (match[2] === "vw") return (amount / 100) * env.width;
  if (match[2] === "vh" || match[2] === "svh" || match[2] === "dvh")
    return (amount / 100) * env.height;
  return px(trimmed);
}

/** A colour from `#rrggbb` (the only form these tokens use), as its relative luminance. */
function luminance(hex: string): number {
  const match = /^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/iu.exec(hex.trim());
  if (!match) throw new Error(`not a #rrggbb colour: ${hex}`);
  const [red, green, blue] = [match[1], match[2], match[3]].map((part) => {
    const channel = Number.parseInt(part ?? "0", 16) / 255;
    return channel <= 0.03928
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (red ?? 0) + 0.7152 * (green ?? 0) + 0.0722 * (blue ?? 0);
}

/** The WCAG contrast ratio of two `#rrggbb` colours. */
export function contrastRatio(first: string, second: string): number {
  const [light, dark] = [luminance(first), luminance(second)].sort(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

/** A declared colour value, after its tokens are resolved, as `#rrggbb`. */
export function hexOf(value: string): string {
  return resolveVars(value).trim();
}
