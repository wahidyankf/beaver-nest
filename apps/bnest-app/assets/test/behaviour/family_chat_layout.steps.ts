// Step bindings for the layout scenarios of specs/apps/bnest/app-fe/behaviours/family_chat.feature that are tagged
// `@fe-vitest-unit`: a short screen, a narrow phone's message width, the composer's growth, and the Send button's
// contrast.
//
// happy-dom has no layout engine. Each Then here checks what the shipped stylesheet declares for the scenario's
// viewport (`support/shipped_css.ts`), and the composer's height is the value the real wiring writes. The rendered
// boxes are measured in Chromium by `bnest-app-fe-e2e`, which owns the same step texts.

import { readFileSync } from "node:fs";
import { expect } from "vitest";
import { activePage, device, isRendered } from "./support/browser_room";
import {
  contrastRatio,
  declarationsFor,
  lengthPx,
  cornerRadii,
  resolveVars,
  type Environment,
} from "../support/shipped_css";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import { hasRegion, settle, shrinkRegion } from "./support/scroll_scene";
import { recallOr, remember } from "./support/scenario_memory";
import { FAMILY_TEMPLATE } from "./support/send_hint";

const ROOT_PX = 16;

const registry: StepDefinition[] = [];

function step(
  expression: string,
  handler: (...args: string[]) => void | Promise<void>,
): void {
  const wrapped: StepHandler = async (context, ...args) => {
    await handler(...args);
    return context;
  };
  registry.push({ expression, handler: wrapped });
}

export function familyChatLayoutSteps(): readonly StepDefinition[] {
  return registry;
}

/** The viewport and pointer the page is laid out for: the scenario's own viewport, a fine pointer. */
function environment(): Environment {
  const { viewport } = device();
  return {
    width: viewport.width,
    height: viewport.height,
    coarse: recallOr("familyCoarse", false),
  };
}

function numberOf(value: string | undefined, label: string): number {
  const parsed = lengthPx(resolveVars(value ?? ""), environment());
  if (Number.isNaN(parsed))
    throw new Error(`${label} is not a length: ${JSON.stringify(value)}`);
  return parsed;
}

// --- Rule: Responsive and accessible presentation -------------------------------------

step("the conversation list is at least half the viewport height", () => {
  // The compact header applies at this viewport: one line, and the brand's text subline hidden. The list's share of
  // the height follows from that header; the measured share is the Playwright adapter's.
  const env = environment();
  const header = declarationsFor(".family-chat-header", env);
  expect(
    header["flex-wrap"],
    "the header wraps to a second line on a short screen",
  ).toBe("nowrap");
  const subline = declarationsFor(".family-chat-brand > span:last-child", env);
  expect(
    subline["display"],
    "the brand subline stays visible on a short screen",
  ).toBe("none");
});

step("the message composer is on screen", () => {
  const { composer, input, send } = activePage().elements;
  expect(isRendered(composer), "the composer is not rendered").toBe(true);
  expect(isRendered(input), "the message input is not rendered").toBe(true);
  expect(isRendered(send), "the Send button is not rendered").toBe(true);
});

step("no vertical page scroll is present", () => {
  // The room's margins and height fit the viewport together, and the body is a flow root so the room's margins do not
  // collapse through it into the document height. The measured scroll height is the Playwright adapter's.
  const env = environment();
  expect(
    declarationsFor("body:has(.family-chat-shell)", env)["display"],
    "the body lets the room's margins collapse",
  ).toBe("flow-root");
  const room = declarationsFor(".family-chat-shell", env);
  const blockMargin = numberOf(
    room["margin-block"] ?? room["margin"]?.split(/\s+/u)[0],
    "the room's block margin",
  );
  const height = numberOf(room["height"], "the room's height");
  expect(
    height + 2 * blockMargin,
    `the room and its margins are taller than the ${env.height} px screen`,
  ).toBeLessThanOrEqual(env.height);
});

step("the message takes at least 80 percent of the viewport width", () => {
  // The message's own share of the room: its `max-width` percentage of the history, which is inset by the room's
  // side padding and the history's margin, all declared at this viewport.
  const env = environment();
  const message =
    declarationsFor(".family-chat-message", env)["max-width"] ?? "";
  const percent = Number.parseFloat(message);
  expect(
    message.endsWith("%") && percent > 0,
    `the message max-width is ${JSON.stringify(message)}`,
  ).toBe(true);
  const shell = numberOf(
    declarationsFor(".family-chat-shell", env)["padding-inline"],
    "the room's side padding",
  );
  const history = numberOf(
    declarationsFor(".family-chat-history", env)["margin-inline"],
    "the history's margin",
  );
  const share =
    ((env.width - 2 * shell - 2 * history) * percent) / 100 / env.width;
  expect(
    share,
    `the message takes ${Math.round(share * 100)}% of the viewport`,
  ).toBeGreaterThanOrEqual(0.8);
});

// --- Composer growth -------------------------------------------------------------------

// The composer's sizes as the stylesheet declares them at this viewport, so each bound is the one the page uses:
// one text line, the vertical padding and the border that frame the text, and the cap on the whole box.
interface ComposerGeometry {
  readonly line: number;
  readonly padding: number;
  readonly border: number;
  readonly cap: number;
}

function composerGeometry(): ComposerGeometry {
  const declared = declarationsFor(".family-chat-message-input", environment());
  const [vertical = ""] = (declared["padding"] ?? "").split(" ");
  const [edge = ""] = (declared["border"] ?? "").split(" ");
  return {
    line: Number(declared["line-height"]) * ROOT_PX,
    padding: 2 * numberOf(vertical, "the composer padding"),
    border: 2 * numberOf(edge, "the composer border"),
    cap: numberOf(declared["max-height"], "the composer's max-height"),
  };
}

/** The composer's resting height (one 3rem line), which a draft grows from. */
const RESTING_COMPOSER_PX = 3 * ROOT_PX;

step(
  "the visitor types a draft of {int} lines into the composer",
  async (count) => {
    const lines = Number(count);
    const { line, padding, border, cap } = composerGeometry();
    if (hasRegion()) {
      // The reader is following a history in this scenario, and no room page is open. The composer's growth is the
      // height its draft needs up to the cap; the history beside it gives up that much room, which is what the follower
      // must answer. The measured growth is the Playwright adapter's.
      const wanted = Math.min(lines * line + padding + border, cap);
      shrinkRegion(Math.max(0, wanted - RESTING_COMPOSER_PX));
      await settle();
      return;
    }
    const page = activePage();
    const input = page.elements.input;
    // The page reads the window's height for a viewport-unit cap, so the window holds this scenario's height.
    page.window.innerHeight = device().viewport.height;
    // happy-dom lays nothing out, so the content height a browser would measure is supplied for this draft.
    Object.defineProperty(input, "scrollHeight", {
      configurable: true,
      get: () => lines * line + padding,
    });
    input.value = Array.from(
      { length: lines },
      (_unused, index) => `line ${index + 1}`,
    ).join("\n");
    input.dispatchEvent(
      new page.window.Event("input", { bubbles: true }) as unknown as Event,
    );
  },
);

function composerHeight(): number {
  const height = Number.parseFloat(activePage().elements.input.style.height);
  if (!Number.isFinite(height))
    throw new Error("the composer has no height set by the page");
  return height;
}

step("the message composer is at least two lines tall", () => {
  const { line, padding, border } = composerGeometry();
  expect(composerHeight(), "the composer height").toBeGreaterThanOrEqual(
    2 * line + padding + border,
  );
});

step("the message composer is at most six lines tall", () => {
  const geometry = composerGeometry();
  const sixLines = 6 * geometry.line + geometry.padding + geometry.border;
  expect(geometry.cap, "the stylesheet's composer cap").toBeLessThanOrEqual(
    sixLines + 0.5,
  );
  expect(composerHeight(), "the composer height").toBeLessThanOrEqual(
    geometry.cap + 0.5,
  );
});

step("the message composer is at most 22 percent of the screen height", () => {
  // A short window keeps most of its height for the conversation: the box's cap is the smaller of its six-line cap and
  // 22 percent of the window, and the box never grows past that cap.
  const share = 0.22 * environment().height;
  expect(
    composerGeometry().cap,
    "the composer's cap is not a share of the window",
  ).toBeLessThanOrEqual(share + 0.5);
  expect(composerHeight(), "the composer height").toBeLessThanOrEqual(
    share + 0.5,
  );
});

step("the Send button is on screen", () => {
  expect(
    isRendered(activePage().elements.send),
    "the Send button is not rendered",
  ).toBe(true);
});

step("the Send button text has a contrast ratio of at least 4.5 to 1", () => {
  const declared = declarationsFor(".family-chat-send", environment());
  const background = resolveVars(declared["background"] ?? "");
  const text = resolveVars(declared["color"] ?? "");
  const ratio = contrastRatio(background, text);
  expect(ratio, `${text} on ${background}`).toBeGreaterThanOrEqual(4.5);
});

step("the Family Chat message box is named {string}", (name) => {
  // The accessible name is the label the template ties to the box. The label is visually hidden, not removed.
  const template = readFileSync(FAMILY_TEMPLATE, "utf8");
  const label = /<label for="family-chat-message-input">([^<]*)<\/label>/u.exec(
    template,
  );
  expect(label?.[1]?.trim()).toBe(name);
});

step(
  "the message box placeholder has at least 4.5 to 1 contrast with the box",
  () => {
    const env = environment();
    const ink = resolveVars(
      declarationsFor(".family-chat-message-input::placeholder", env)[
        "color"
      ] ?? "",
    );
    const background = resolveVars(
      declarationsFor(".family-chat-message-input", env)["background"] ?? "",
    );
    expect(
      contrastRatio(background, ink),
      `${ink} on ${background}`,
    ).toBeGreaterThanOrEqual(4.5);
  },
);

step("the Family Chat Send button has four equal corner radii", () => {
  const radius = resolveVars(
    declarationsFor(".family-chat-send", environment())["border-radius"] ?? "",
  );
  expect(radius, "the Family Chat Send border-radius").not.toBe("");
  const [topLeft, topRight, bottomRight, bottomLeft] = cornerRadii(radius);
  expect([topRight, bottomRight, bottomLeft]).toEqual([
    topLeft,
    topLeft,
    topLeft,
  ]);
});

// --- Then: a long unbroken draft keeps the room, the composer and Send inside the screen -----------------------

step(
  "the visitor types an unbroken {int} character address into the composer",
  (length) => {
    // The Playwright adapter types the address and measures the boxes. The CSS checked below is a regression guard;
    // nothing here shows that it is the cause of the outcome.
    remember("familyUnbrokenDraft", Number(length));
  },
);

step("the Family room is inside the screen", () => {
  // Regression guard: a column sized to its content would let a long line widen the room.
  expect(
    declarationsFor(".family-chat-shell", environment())[
      "grid-template-columns"
    ],
    "the room's column is sized to its content",
  ).toBe("minmax(0, 1fr)");
});

step("the Send button is on screen and is not covered by the composer", () => {
  // Regression guard: a first column sized to its content, or a box with an automatic minimum width, would let a long
  // line widen the composer.
  const env = environment();
  expect(
    declarationsFor(".family-chat-composer", env)["grid-template-columns"],
    "the composer's first column is sized to its content",
  ).toMatch(/^minmax\(0, 1fr\)/u);
  expect(
    declarationsFor(".family-chat-message-input", env)["min-width"],
    "the message box keeps an automatic minimum width",
  ).toBe("0");
});
