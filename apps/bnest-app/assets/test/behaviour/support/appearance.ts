// Source-level checks shared by the chat rooms' bindings for the single light appearance (ADR 005, decision 3).
//
// Vitest cannot paint a page, so these read what the server ships: the room and home templates, the Codex chat
// LiveView, `app.js`, and the stylesheet. The e2e adapter checks the painted page with an OS dark preference.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect } from "vitest";

const here = path.dirname(fileURLToPath(import.meta.url));
const APP_ROOT = path.resolve(here, "../../../..");

export const TEMPLATES = {
  "/": path.join(
    APP_ROOT,
    "lib/bnest_app_web/controllers/page_html/home.html.heex",
  ),
  "/chat": path.join(APP_ROOT, "lib/bnest_app_web/live/chat_live.ex"),
  "/family-chat": path.join(
    APP_ROOT,
    "lib/bnest_app_web/controllers/family_chat_html/room.html.heex",
  ),
  "root layout": path.join(
    APP_ROOT,
    "lib/bnest_app_web/components/layouts/root.html.heex",
  ),
  "app layout": path.join(APP_ROOT, "lib/bnest_app_web/components/layouts.ex"),
  "app script": path.join(APP_ROOT, "assets/js/app.js"),
} as const;

/** The template that renders a route the scenario opens. */
export function templateFor(pathname: string): string {
  if (pathname === "/") return TEMPLATES["/"];
  if (pathname === "/chat") return TEMPLATES["/chat"];
  if (pathname.startsWith("/family-chat/")) return TEMPLATES["/family-chat"];
  throw new Error(`no template for ${JSON.stringify(pathname)}`);
}

/** No page the chat rooms serve has a colour theme control, and no script still switches a theme. */
export function assertNoThemeControl(): void {
  for (const file of Object.values(TEMPLATES)) {
    const source = readFileSync(file, "utf8");
    expect(
      !source.includes("Color theme") &&
        !source.includes("theme_toggle") &&
        !source.includes("data-theme"),
      `${path.basename(file)} still renders a theme control or a theme attribute`,
    ).toBe(true);
  }
  const js = readFileSync(TEMPLATES["app script"], "utf8");
  expect(
    !js.includes("phx:set-theme"),
    "app.js still listens for a theme event",
  ).toBe(true);
}

/** The page's base colour: the last colour of the body's background, with its variable resolved to a hex value. */
function declaredPageBase(): string {
  const appCss = readFileSync(
    path.join(APP_ROOT, "assets/css/app.css"),
    "utf8",
  );
  const sharedCss = readFileSync(
    path.join(APP_ROOT, "assets/css/chat_shared.css"),
    "utf8",
  );
  const body = /(?:^|\n)body\s*\{([^}]*)\}/u.exec(appCss)?.[1] ?? "";
  const background = /background:\s*([^;]*);/u.exec(body)?.[1] ?? "";
  const tokens = [
    ...background.matchAll(/var\((--[\w-]+)\)|(#[0-9a-fA-F]{6})\b/gu),
  ];
  const last = tokens.at(-1);
  if (!last) throw new Error("the body declares no colour in its background");
  if (last[2]) return last[2];
  const name = last[1];
  const value = new RegExp(`${name}:\\s*(#[0-9a-fA-F]{6})`, "u").exec(
    sharedCss,
  );
  if (!value?.[1]) throw new Error(`${name} is not a six-digit colour`);
  return value[1];
}

/** WCAG relative luminance of a six-digit hex colour. */
function relativeLuminance(hex: string): number {
  const [red, green, blue] = [1, 3, 5].map((index) => {
    const channel = parseInt(hex.slice(index, index + 2), 16) / 255;
    return channel <= 0.03928
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red! + 0.7152 * green! + 0.0722 * blue!;
}

/** WCAG contrast ratio of two six-digit hex colours, from 1 to 21. */
export function contrastRatio(first: string, second: string): number {
  const [light, dark] = [
    relativeLuminance(first),
    relativeLuminance(second),
  ].sort((a, b) => b - a) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

/** The page background is light: its declared base colour is clearly light, whatever the visitor's system prefers. */
export function assertPageBackgroundIsLight(): void {
  const base = declaredPageBase();
  expect(
    relativeLuminance(base),
    `the page background ${base} is not light`,
  ).toBeGreaterThan(0.6);
}

/** No rule in the stylesheet answers a dark system preference, so a dark preference changes nothing on the page. */
export function assertNoDarkPreferenceRule(): void {
  const css = readFileSync(path.join(APP_ROOT, "assets/css/app.css"), "utf8");
  expect(
    !css.includes("prefers-color-scheme"),
    "the stylesheet answers a dark system preference",
  ).toBe(true);
}

/** The stylesheet defines one light theme and answers no dark system preference. */
export function assertSingleLightAppearance(): void {
  const css = readFileSync(path.join(APP_ROOT, "assets/css/app.css"), "utf8");
  assertNoDarkPreferenceRule();
  expect(
    !/\[data-theme/u.test(css),
    "the stylesheet styles a data-theme attribute",
  ).toBe(true);
  expect(
    css.includes('name: "light"') && !css.includes('name: "dark"'),
    "the stylesheet defines a theme other than the light one",
  ).toBe(true);
}
