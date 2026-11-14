// chat.feature and family_chat.feature, the Rules "Codex header and composer stay in place while the messages scroll"
// and "Family Chat header and composer stay in place while the messages scroll". This layer checks the stylesheet's
// declared layout contract that makes the geometry hold: a column room that clips, one flex scroller for the messages,
// a height that follows the visible area through `--vvh` (set from the visual viewport, so a soft keyboard shrinks it),
// and the header and Send boxes declared in the column. It does not measure boxes: the real positions, heights and
// scroll results are measured in Chromium by the e2e bindings (apps/bnest-app-fe-e2e/tests/steps/codex-sticky-layout.steps.ts
// and family-chat-sticky-layout.steps.ts). The Codex and Family steps share one page check, which accepts whichever
// room's shell is on the page.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect } from "vitest";
import {
  declarationsFor,
  lengthPx,
  type Environment,
} from "../support/shipped_css";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import { device } from "./support/browser_room";
import { recall, recallOr, remember } from "./support/scenario_memory";

const here = path.dirname(fileURLToPath(import.meta.url));
const APP_JS = path.resolve(here, "../../js/app.js");

// Each corpus binds only its own steps (verify.ts checks for unused bindings), so the Codex and Family lists are kept
// apart, and the two steps both rooms use are added to both.
const codexRegistry: StepDefinition[] = [];
const familyRegistry: StepDefinition[] = [];

function register(
  target: StepDefinition[],
  expression: string,
  handler: (...args: string[]) => void | Promise<void>,
): void {
  const wrapped: StepHandler = async (context, ...args) => {
    await handler(...args);
    return context;
  };
  target.push({ expression, handler: wrapped });
}

const SHARED = new Set([
  "the page does not scroll",
  "the soft keyboard shrinks the screen to {string}",
  "the room follows the visible area through the --vvh height",
]);

function step(
  expression: string,
  handler: (...args: string[]) => void | Promise<void>,
): void {
  if (SHARED.has(expression)) {
    register(codexRegistry, expression, handler);
    register(familyRegistry, expression, handler);
    return;
  }
  if (/family|Family/u.test(expression)) {
    register(familyRegistry, expression, handler);
    return;
  }
  register(codexRegistry, expression, handler);
}

export function codexStickySteps(): readonly StepDefinition[] {
  return codexRegistry;
}

export function familyStickySteps(): readonly StepDefinition[] {
  return familyRegistry;
}

/** The screen a scenario is on: the Codex page's viewport when it set one, otherwise the room's device viewport. */
function envOf(): Environment {
  const codex = recallOr<{ width: number; height: number } | null>(
    "codexViewport",
    null,
  );
  const viewport = codex ?? device().viewport;
  return {
    width: viewport.width,
    height: viewport.height,
    coarse: recallOr("codexCoarse", false),
  };
}

/** The declared rules of a selector. A selector with no declared rule fails here, so a renamed class cannot pass. */
function expectDeclared(selector: string): Record<string, string> {
  const declared = declarationsFor(selector, envOf());
  expect(
    Object.keys(declared).length,
    `${selector} has a declared rule`,
  ).toBeGreaterThan(0);
  return declared;
}

function expectNotTakenOutOfFlow(selector: string): void {
  const position = expectDeclared(selector)["position"];
  expect(
    position === "absolute" || position === "fixed",
    `${selector} is taken out of the column`,
  ).toBe(false);
}

/** The room a scenario is on, from the steps it ran: the Codex steps record a Codex page; the Family steps do not. */
function roomUnderTest(): "codex" | "family" {
  const codexPage =
    recallOr<unknown>("codexViewport", null) !== null ||
    recallOr<unknown>("codexLaidOut", null) !== null;
  return codexPage ? "codex" : "family";
}

function expectCodexPanelFillsScreen(): void {
  const env = envOf();
  const panel = declarationsFor(".chat-panel", env);
  expect(panel["flex-direction"], "the panel stacks its parts").toBe("column");
  expect(panel["overflow"], "the panel clips").toBe("hidden");
  expect(
    expectDeclared(".chat-shell")["height"],
    "the Codex room follows the visible area",
  ).toContain("100dvh");
}

function expectFamilyShellFillsScreen(): void {
  const env = envOf();
  const height = expectDeclared(".family-chat-shell")["height"] ?? "";
  expect(
    height.includes("dvh"),
    "the Family Chat room follows the visible area",
  ).toBe(true);
  expect(
    declarationsFor(".family-chat-shell", env)["grid-template-rows"],
    "the room stacks header, banner, history and composer",
  ).toBe("auto auto 1fr auto");
}

function expectCodexConversationIsTheOnlyScroller(): void {
  const conversation = expectDeclared(".conversation");
  expect(conversation["overflow-y"], "the conversation scrolls").toBe("auto");
  expect(conversation["flex"], "the conversation takes the space left").toBe(
    "1",
  );
  expect(conversation["min-height"], "the conversation may shrink").toBe("0");
}

function expectFamilyHistoryIsTheOnlyScroller(): void {
  const history = expectDeclared(".family-chat-history");
  expect(history["overflow-y"], "the history scrolls").toBe("auto");
  expect(history["min-height"], "the history may shrink").toBe("0");
}

/** Both rooms' shells: each is the page's full height, so each must follow the visible area. */
const ROOM_SHELLS = [".chat-shell", ".family-chat-shell"] as const;

/** A screen size from a scenario's "WxH" text. */
function screenOf(spec: string): { width: number; height: number } {
  const match = /^(\d+)x(\d+)$/u.exec(spec);
  if (!match) throw new Error(`unknown screen size ${spec}`);
  return { width: Number(match[1]), height: Number(match[2]) };
}

/**
 * The height a room shell gets when the visible area is `visibleHeight` pixels: the page writes that height to --vvh,
 * and the shell's declared height reads it (with its 100dvh fallback in the same declaration, not needed here).
 */
function shellHeightWhenVisible(
  selector: string,
  screen: { width: number; height: number },
): number {
  const env = { ...envOf(), width: screen.width, height: screen.height };
  const declared = expectDeclared(selector)["height"] ?? "";
  const resolved = declared.replace(
    /var\(--vvh,\s*100dvh\)/gu,
    `${screen.height}px`,
  );
  return lengthPx(resolved, env);
}

// The composer's line and its own chrome, in pixels: the body text's 1.5 line height, and the box's padding and border.
const BODY_LINE_HEIGHT = 1.5;

function codexComposerBox(): {
  fontPx: number;
  linePx: number;
  chromePx: number;
} {
  const env = envOf();
  const box = declarationsFor(".composer textarea", env);
  const [vertical = ""] = (box["padding"] ?? "").split(/\s+/u);
  const [edge = ""] = (box["border"] ?? "").split(/\s+/u);
  const fontPx = lengthPx(box["font-size"] ?? "", env);
  return {
    fontPx,
    linePx: fontPx * BODY_LINE_HEIGHT,
    chromePx: 2 * lengthPx(vertical, env) + 2 * lengthPx(edge, env),
  };
}

// The seeded count lives in Chromium (the e2e binding seeds the conversation). Here the count is recorded, so the When
// below can refuse a scenario that never set a conversation to scroll.
step("a Codex conversation holds {int} messages", (count) => {
  remember("codexMessages", Number(count));
});

// Vitest cannot scroll a conversation: this When checks the declared scroller and the recorded count, the two things a
// scroll needs. The scroll itself is performed in Chromium by the e2e binding of the same step text.
step("the visitor scrolls the Codex conversation to the middle", () => {
  expect(
    recall<number>("codexMessages"),
    "the scenario seeded a Codex conversation to scroll",
  ).toBeGreaterThan(0);
  expectCodexConversationIsTheOnlyScroller();
});

step("the visitor scrolls the family conversation to the middle", () => {
  expectFamilyHistoryIsTheOnlyScroller();
});

step("the Codex header is at the top of the screen", () => {
  expectCodexPanelFillsScreen();
  expectNotTakenOutOfFlow(".chat-header");
});

step("the Family Chat header is at the top of the screen", () => {
  expectFamilyShellFillsScreen();
  expectNotTakenOutOfFlow(".family-chat-header");
});

step("the Codex composer is at the bottom of the screen", () => {
  expectCodexPanelFillsScreen();
  expectNotTakenOutOfFlow(".composer");
});

step("the Family Chat composer is at the bottom of the screen", () => {
  expectFamilyShellFillsScreen();
  expectNotTakenOutOfFlow(".family-chat-composer");
});

step("the newest Codex message ends above the composer", () => {
  expectCodexConversationIsTheOnlyScroller();
  expectNotTakenOutOfFlow(".composer");
});

step("the newest Family Chat message ends above the composer", () => {
  expectFamilyHistoryIsTheOnlyScroller();
  expectNotTakenOutOfFlow(".family-chat-composer");
});

step("the page does not scroll", () => {
  // Only the room under test: its shell is sized to the visible area, and the page (html and body) clips to it.
  const room = roomUnderTest();
  const shell = room === "codex" ? ".chat-shell" : ".family-chat-shell";
  const root = `html:has(${shell})`;
  const body = `body:has(${shell})`;
  expect(
    expectDeclared(shell)["height"] ?? "",
    `${shell} is sized to the visible area`,
  ).toContain("dvh");
  expect(expectDeclared(root)["overflow"], `${root} clips the page`).toBe(
    "hidden",
  );
  expect(expectDeclared(body)["overflow"], `${body} clips the page`).toBe(
    "hidden",
  );
  // A body with its own minimum height of the viewport unit can scroll by the browser toolbar's height.
  expect(
    expectDeclared(body)["min-height"],
    `${body} does not add the viewport unit's height`,
  ).toBe("0");
});

step("the soft keyboard shrinks the screen to {string}", (spec) => {
  // The page writes the visual viewport's height to --vvh, and the shell's height reads it, so the shell is the height
  // the screen has left. Verified here only by the declared rule and the emulated resize; a real phone's keyboard is
  // checked by hand (ADR 005, Accepted limits).
  const screen = screenOf(spec);
  for (const selector of ROOM_SHELLS) {
    const declared = expectDeclared(selector)["height"] ?? "";
    expect(
      declared.includes("var(--vvh"),
      `${selector} reads --vvh, which follows the visible area`,
    ).toBe(true);
    const shown = shellHeightWhenVisible(selector, screen);
    expect(shown, `${selector} height at ${spec}`).toBeLessThanOrEqual(
      screen.height,
    );
    // The Family shell keeps a 2.5rem margin; the Codex shell takes the whole visible area.
    expect(
      screen.height - shown,
      `${selector} gives up at most its margin`,
    ).toBeLessThanOrEqual(lengthPx("2.5rem", envOf()));
  }
});

// The keyboard path end to end: each room shell reads --vvh (with 100dvh as its fallback), and app.js starts the writer at
// the top level of the page script, so a mounted page writes --vvh. The e2e binding checks the written value in Chromium.
step("the room follows the visible area through the --vvh height", () => {
  for (const selector of ROOM_SHELLS) {
    expect(
      expectDeclared(selector)["height"] ?? "",
      `${selector} reads --vvh, with 100dvh as the fallback`,
    ).toContain("var(--vvh, 100dvh)");
  }
  expect(
    /^installVisualViewportHeight\(\);$/mu.test(readFileSync(APP_JS, "utf8")),
    "app.js starts the --vvh writer at the top level of the page script",
  ).toBe(true);
});

// A box taken out of the column (absolute or fixed) fails here; the real on-screen check is the e2e binding.
step("the Send button and the Codex header are on screen", () => {
  expectNotTakenOutOfFlow(".send-button");
  expectNotTakenOutOfFlow(".chat-header");
});

step("the Family Chat Send button and header are on screen", () => {
  expectNotTakenOutOfFlow(".family-chat-send");
  expectNotTakenOutOfFlow(".family-chat-header");
});

step(
  "the Codex header keeps its full height and its controls stay inside it",
  () => {
    // The controls' boxes are measured in Chromium; here the header's column rule must not let it shrink.
    expectCodexPanelFillsScreen();
    expectNotTakenOutOfFlow(".chat-header");
    expect(
      expectDeclared(".chat-header")["flex-shrink"],
      "the header does not shrink",
    ).toBe("0");
  },
);

// The box's resting height is a phone's 3.25 rem, below two lines, so the two-line claim is the growth: the box fits its
// draft (field-sizing: content) up to a cap that holds two lines and their chrome. Chromium measures the grown box in
// the e2e binding; this layer checks the rule that makes it grow.
step("the Codex message box is at least two lines tall", () => {
  const env = envOf();
  const box = expectDeclared(".composer textarea");
  expect(box["field-sizing"], "the box grows with its draft").toBe("content");
  const { linePx, chromePx } = codexComposerBox();
  const cap = lengthPx(box["max-height"] ?? "", env);
  expect(
    cap,
    "the box's cap holds two lines and their chrome",
  ).toBeGreaterThanOrEqual(2 * linePx + chromePx);
});

step("the Codex message box is no taller than {int} lines", (lines) => {
  const env = envOf();
  const cap = lengthPx(
    expectDeclared(".composer textarea")["max-height"] ?? "",
    env,
  );
  expect(Number.isNaN(cap), "the message box has a height cap").toBe(false);
  // N lines of text plus the box's own padding and border, the same measure the e2e binding uses.
  const { linePx, chromePx } = codexComposerBox();
  const limit = Number(lines) * linePx + chromePx;
  expect(
    cap,
    "the message box cap, in pixels, with its chrome",
  ).toBeLessThanOrEqual(limit + 1);
});

step("the Codex message list keeps its overscroll inside itself", () => {
  expectCodexConversationIsTheOnlyScroller();
  expect(
    expectDeclared(".conversation")["overscroll-behavior"],
    "the Codex message list keeps its overscroll inside itself",
  ).toBe("contain");
});

step("the Family Chat message list keeps its overscroll inside itself", () => {
  expectFamilyHistoryIsTheOnlyScroller();
  expect(
    expectDeclared(".family-chat-history")["overscroll-behavior"],
    "the Family Chat message list keeps its overscroll inside itself",
  ).toBe("contain");
});
