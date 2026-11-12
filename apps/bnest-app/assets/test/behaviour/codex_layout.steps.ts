// Step bindings for the touch and short-screen layout scenarios of specs/apps/bnest/app-fe/behaviours/chat.feature
// (tag `@fe-vitest-unit`): control sizes on a touch pointer, the composer text size, the scroll cues and height caps
// of replies, and the focus rings.
//
// happy-dom has no layout engine, so each Then checks the declared values the shipped stylesheet gives the page for
// the scenario's viewport and pointer (`support/shipped_css.ts`). The rendered boxes are measured in Chromium by
// `bnest-app-fe-e2e`, which owns the same step texts. A reply's markup is the canned fixture the server and
// Playwright use, so the elements a Then names are the ones a reader would see.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect } from "vitest";
import { currentRegion, openRegion } from "./support/scroll_scene";
import {
  contrastRatio,
  declarationsFor,
  hexOf,
  imageSizingRules,
  lengthPx,
  resolveVars,
  type Environment,
} from "../support/shipped_css";
import {
  forgetScenario,
  recallOr,
  remember,
  recall,
} from "./support/scenario_memory";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  here,
  "../../../test/support/codex_fixture_replies.json",
);
const FIXTURES = JSON.parse(readFileSync(FIXTURE_PATH, "utf8")) as Record<
  string,
  { text: string }
>;

const DEFAULT_VIEWPORT = { width: 1280, height: 800 };
const TOUCH_TARGET_PX = 44;
const CODE_BLOCK_MAX_PX = 384;
const SCREEN_IMAGE_SHARE = 0.7;
const CORAL_RING = "3px solid #e5633d";
// A conversation of three long replies, taller than its box, so the panel has something to scroll.
const LONG_CONVERSATION_PX = 1000;
const CONVERSATION_BOX_PX = 300;

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

export function codexLayoutSteps(): readonly StepDefinition[] {
  return registry;
}

/** Forgets the layout a scenario set up; `verify.ts` calls this after every scenario. */
export function resetCodexLayout(): void {
  forgetScenario();
}

interface Laid {
  readonly viewport: { width: number; height: number };
  readonly coarse: boolean;
}

/** The environment the last "the page is laid out" step fixed; a Then cannot run before one. */
function laidOut(): Environment {
  const laid = recall<Laid>("codexLaidOut");
  return {
    width: laid.viewport.width,
    height: laid.viewport.height,
    coarse: laid.coarse,
  };
}

function pixels(
  value: string | undefined,
  label: string,
  env: Environment,
): number {
  const parsed = lengthPx(resolveVars(value ?? ""), env);
  if (Number.isNaN(parsed))
    throw new Error(`${label} is not a length: ${JSON.stringify(value)}`);
  return parsed;
}

/** The overflow a box declares on one axis: `overflow-x`, `overflow-y`, or the `overflow` shorthand. */
function scrolls(declared: Record<string, string>, axis: "x" | "y"): boolean {
  const value = declared[`overflow-${axis}`] ?? declared["overflow"] ?? "";
  return value === "auto" || value === "scroll";
}

function fixtureText(prompt: string): string {
  const text = FIXTURES[prompt]?.text;
  if (text === undefined)
    throw new Error(`no fixture reply for ${JSON.stringify(prompt)}`);
  return text;
}

// --- Given ---------------------------------------------------------------------------

step("the Codex chat page is open at {string}", (spec) => {
  const match = /^\w+ (\d+)x(\d+)$/u.exec(spec);
  if (!match) throw new Error(`unreadable viewport ${JSON.stringify(spec)}`);
  remember("codexViewport", {
    width: Number(match[1]),
    height: Number(match[2]),
  });
});

step("the visitor's pointer is a touch pointer", () => {
  remember("codexCoarse", true);
});

step("a Codex reply answers {string}", (prompt) => {
  // The reply the scenario sends is the fixture the server and Playwright use; it must carry what the Thens name.
  const text = fixtureText(prompt);
  expect(/^\|.*\|$/mu.test(text), "the reply has no table").toBe(true);
  expect(text.includes("```elixir"), "the reply has no code block").toBe(true);
  expect(
    text.includes("beaver-nest-logo.png"),
    "the reply has no repository image",
  ).toBe(true);
  expect(
    text.includes("](https://example.com/docs)"),
    "the reply has no link",
  ).toBe(true);
  remember("codexPrompt", prompt);
});

// --- When ----------------------------------------------------------------------------

step("the page is laid out", () => {
  remember("codexLaidOut", {
    viewport: recallOr("codexViewport", DEFAULT_VIEWPORT),
    coarse: recallOr("codexCoarse", false),
  });
});

// --- Then: touch targets and text size ---------------------------------------------

const HEADER_CONTROLS = [
  ".model-picker select",
  ".repository-write-toggle",
  ".clear-chat-button",
  ".chat-theme-control button",
];

step("the header controls are at least 44 pixels tall", () => {
  const env = laidOut();
  for (const selector of HEADER_CONTROLS) {
    const declared = declarationsFor(selector, env);
    const height = pixels(
      declared["min-height"],
      `${selector} min-height`,
      env,
    );
    expect(
      height,
      `${selector} is ${height} px tall on a touch pointer`,
    ).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
  }
});

step("the message composer text is 16 pixels", () => {
  const env = laidOut();
  const size = pixels(
    declarationsFor(".composer textarea", env)["font-size"],
    "the composer text size",
    env,
  );
  expect(size, "the composer text size").toBe(16);
});

step("the diagram source summary is at least 44 pixels tall", () => {
  const env = laidOut();
  const height = pixels(
    declarationsFor(".bnest-diagram-source summary", env)["min-height"],
    "the diagram source min-height",
    env,
  );
  expect(
    height,
    "the diagram source is shorter than a touch target",
  ).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
});

// --- Then: scroll cues and height caps ------------------------------------------------

step("the wide table and the code block show a scroll cue", () => {
  const env = laidOut();
  expect(recall<string>("codexPrompt")).toBeTruthy();
  for (const selector of [".markdown-body table", ".markdown-body pre"]) {
    const declared = declarationsFor(selector, env);
    expect(scrolls(declared, "x"), `${selector} does not scroll sideways`).toBe(
      true,
    );
    const background =
      declared["background"] ?? declared["background-image"] ?? "";
    expect(
      background.includes("linear-gradient") && background.includes("local"),
      `${selector} has no scroll cue`,
    ).toBe(true);
  }
});

step("the page does not overflow horizontally at 390 pixels", () => {
  // Checks the declared rules only: the reply picture's cap (`.markdown-body img`), that no other shipped rule for an
  // image outside a diagram lifts that cap, and that the wide table, the code block and the diagram canvas scroll
  // inside their own boxes. A diagram's picture is allowed to be wider than its bubble, because its canvas scrolls it.
  // Whether the page actually overflows is measured in Chromium (bnest-app-fe-e2e), because no layout engine runs here.
  // A width the diagram script sets at run time is not read here either.
  const env = laidOut();
  expect(
    declarationsFor(".markdown-body img", env)["max-width"],
    "the reply picture can be wider than its bubble",
  ).toBe("100%");
  for (const rule of imageSizingRules(env)) {
    if (rule.selector.includes(".bnest-diagram")) continue;
    if (rule.property === "max-width") {
      expect(rule.value, `${rule.selector} lifts the picture cap`).toBe("100%");
    }
  }
  for (const selector of [
    ".markdown-body table",
    ".markdown-body pre",
    ".bnest-diagram-canvas",
  ]) {
    expect(
      scrolls(declarationsFor(selector, env), "x"),
      `${selector} does not scroll sideways`,
    ).toBe(true);
  }
});

step("the code block is no taller than 384 pixels and scrolls", () => {
  const env = laidOut();
  const declared = declarationsFor(".markdown-body pre", env);
  const height = pixels(
    declared["max-height"],
    "the code block max-height",
    env,
  );
  expect(height, "the code block height cap").toBeLessThanOrEqual(
    CODE_BLOCK_MAX_PX,
  );
  expect(
    scrolls(declared, "y"),
    "the code block does not scroll vertically",
  ).toBe(true);
});

step("the logo is no taller than 70 percent of the screen height", () => {
  const env = laidOut();
  const height = pixels(
    declarationsFor(".markdown-body img", env)["max-height"],
    "the image max-height",
    env,
  );
  expect(height, "the image height cap").toBeLessThanOrEqual(
    SCREEN_IMAGE_SHARE * env.height,
  );
});

// --- Then: the composer and the header on a phone ----------------------------------------

/** The top and bottom padding of a box in pixels, from its `padding` shorthand or its longhands. */
function paddingBlockPx(
  declared: Record<string, string>,
  env: Environment,
  label: string,
): [number, number] {
  // The shorthand runs top, right, bottom, left; with one or two values the bottom repeats the top.
  const shorthand = (declared["padding"] ?? "0").trim().split(/\s+/u);
  const top = declared["padding-top"] ?? shorthand[0] ?? "0";
  const bottom =
    declared["padding-bottom"] ?? shorthand[2] ?? shorthand[0] ?? "0";
  return [
    pixels(top, `${label} padding-top`, env),
    pixels(bottom, `${label} padding-bottom`, env),
  ];
}

/** The most padding a phone header keeps above and below its title, so the header stays compact. */
const COMPACT_HEADER_PADDING_PX = 12;

step("the message composer is on screen without scrolling the page", () => {
  // The panel fills the screen and the conversation above the composer is the region that scrolls, so the page itself
  // does not scroll. The composer's measured place is the Playwright adapter's.
  const env = laidOut();
  const [shellTop, shellBottom] = paddingBlockPx(
    declarationsFor(".chat-shell", env),
    env,
    "the chat shell",
  );
  expect(
    shellTop + shellBottom,
    "the shell adds padding around the panel",
  ).toBe(0);
  const panel = declarationsFor(".chat-panel", env);
  const panelHeight = pixels(panel["height"], "the panel height", env);
  expect(
    panelHeight,
    `the panel is ${panelHeight} px tall on a ${env.height} px screen`,
  ).toBeLessThanOrEqual(env.height);
  expect(
    pixels(panel["min-height"] ?? "0", "the panel min-height", env),
    "the panel min-height",
  ).toBe(0);
  expect(
    scrolls(declarationsFor(".conversation", env), "y"),
    "the conversation does not scroll",
  ).toBe(true);
});

step("the Codex header is at most 30 percent of the screen height", () => {
  // The header's measured height is the Playwright adapter's. Here its declared padding must be the compact phone one.
  const env = laidOut();
  const [top, bottom] = paddingBlockPx(
    declarationsFor(".chat-header", env),
    env,
    "the Codex header",
  );
  expect(top, "the header top padding").toBeLessThanOrEqual(
    COMPACT_HEADER_PADDING_PX,
  );
  expect(bottom, "the header bottom padding").toBeLessThanOrEqual(
    COMPACT_HEADER_PADDING_PX,
  );
});

// --- Then: focus rings ------------------------------------------------------------------

function ringOf(selector: string): string {
  return resolveVars(declarationsFor(selector, laidOut())["outline"] ?? "");
}

step("a focused link shows the coral focus ring", () => {
  expect(ringOf(".markdown-body a:focus-visible"), "the link focus ring").toBe(
    CORAL_RING,
  );
});

step("the visitor tabs to a Codex theme button", () => {
  // The Playwright adapter presses Tab until focus is on a theme button; this binding keeps that the scenario's focus target.
  remember("codexFocusTarget", "theme");
});

step("the focused Codex theme button shows the coral focus ring", () => {
  // The theme buttons carry the same 3 px coral ring as the other Codex header controls.
  expect(
    recallOr("codexFocusTarget", ""),
    "the scenario did not tab to a theme button",
  ).toBe("theme");
  expect(
    ringOf(".chat-theme-control button:focus-visible"),
    "the theme button focus ring",
  ).toBe(CORAL_RING);
});

step(
  "a focused table and a focused code block show the coral focus ring",
  () => {
    for (const selector of [
      ".markdown-body table:focus-visible",
      ".markdown-body pre:focus-visible",
    ]) {
      expect(ringOf(selector), `${selector} focus ring`).toBe(CORAL_RING);
    }
  },
);

step("a focused diagram source shows the coral focus ring", () => {
  expect(
    ringOf(".bnest-diagram-source summary:focus-visible"),
    "the diagram source focus ring",
  ).toBe(CORAL_RING);
});

// --- Then: a conversation that keeps room on a small screen, and a panel bounded by the window --------------------

/** The touch target every header control keeps (the touch rules above), counted as one row of the header. */
const CONTROL_ROW_PX = 44;
/** The share of a short screen the header, the composer and the controls may use, leaving the rest to the conversation. */
const CHROME_SHARE = 0.6;

/** A percentage in a declared value, as a number (`86%` is 86); NaN when the value is not a percentage. */
function percentOf(value: string | undefined): number {
  const match = /^(\d+(?:\.\d+)?)%$/u.exec(resolveVars(value ?? "").trim());
  return match ? Number(match[1]) : Number.NaN;
}

step("the conversation is at least 40 percent of the screen height", () => {
  // The conversation is what the header, the controls row and the composer leave. The budget is the declared sizes of
  // those, with the one row of controls counted as a touch target tall. The measured share is the Playwright adapter's.
  const env = laidOut();
  const [top, bottom] = paddingBlockPx(
    declarationsFor(".chat-header", env),
    env,
    "the Codex header",
  );
  const logo = pixels(
    declarationsFor(".brand-logo", env)["height"],
    "the logo height",
    env,
  );
  const [composerTop, composerBottom] = paddingBlockPx(
    declarationsFor(".composer", env),
    env,
    "the composer",
  );
  const field = pixels(
    declarationsFor(".composer textarea", env)["min-height"],
    "the message box min-height",
    env,
  );
  const used =
    top + bottom + logo + CONTROL_ROW_PX + composerTop + composerBottom + field;
  expect(
    used,
    `the header, controls and composer use ${used} px of a ${env.height} px screen`,
  ).toBeLessThanOrEqual(CHROME_SHARE * env.height);
});

step("the Send button is beside the message box", () => {
  // The composer is one row of two tracks: the box, then Send. A single track would put Send below the box.
  const env = laidOut();
  const columns = (
    declarationsFor(".composer", env)["grid-template-columns"] ?? ""
  ).trim();
  expect(columns, "the composer is a single column").not.toBe("1fr");
  expect(
    columns.endsWith(" auto"),
    `the composer columns are ${JSON.stringify(columns)}`,
  ).toBe(true);
});

step("the Codex panel is no taller than the window", () => {
  const env = laidOut();
  const height = pixels(
    declarationsFor(".chat-panel", env)["height"],
    "the Codex panel height",
    env,
  );
  expect(
    height,
    `the panel is ${height} px on a ${env.height} px window`,
  ).toBeLessThanOrEqual(env.height);
});

step("the conversation holds three long Codex replies", () => {
  openRegion(LONG_CONVERSATION_PX, CONVERSATION_BOX_PX);
});

step("the conversation scrolls inside the panel", () => {
  const env = laidOut();
  const declared = declarationsFor(".conversation", env);
  expect(scrolls(declared, "y"), "the conversation does not scroll").toBe(true);
  // The conversation really overflows its box (the scene holds the three replies), so the scroll has content to show.
  const { metrics } = currentRegion();
  expect(
    metrics.content,
    "the conversation is not taller than its box",
  ).toBeGreaterThan(metrics.box);
  expect(
    pixels(declared["min-height"] ?? "0", "the conversation min-height", env),
    "the conversation cannot shrink",
  ).toBe(0);
});

step(
  "the reply bubble takes at least 80 percent of the conversation width",
  () => {
    const env = laidOut();
    const share = percentOf(
      declarationsFor(".message-assistant:has(.bnest-diagram-canvas)", env)[
        "width"
      ],
    );
    expect(
      share,
      "the bubble around a drawn diagram is not a share of the column",
    ).toBeGreaterThanOrEqual(80);
  },
);

step(
  "the repository write toggle text has a contrast ratio of at least 4.5 to 1",
  () => {
    // The pill is checked in both states: its text on its paper (read-only) and on its coral-ink (writes enabled).
    const env = laidOut();
    for (const selector of [
      ".repository-access-badge",
      ".repository-access-badge-write",
    ]) {
      const declared = declarationsFor(selector, env);
      const ratio = contrastRatio(
        hexOf(declared["color"] ?? ""),
        hexOf(declared["background"] ?? ""),
      );
      expect(ratio, `${selector} text contrast`).toBeGreaterThanOrEqual(4.5);
    }
  },
);

// --- Then: the header row on a landscape phone and a narrow phone, and the composer's cap ------------------------

const TOUCH_THEME_BUTTON_PX = 44;
/** One line of Chrome's default text in a header control, with its padding and border, as the e2e's one-line bound. */
const LINE_OF_TEXT_PX = 24;
const COMPOSER_LABEL_PX = 20;
const CONVERSATION_SHARE_CAPPED = 0.25;

/** The composer draft's line count for the scenario, as the step before it recorded it. */
function draftLines(): number {
  return recall<number>("codexDraftLines");
}

step("the header controls start inside the header", () => {
  // A row aligned to its end pushes the first controls past the header's left edge, where a sideways scroll cannot
  // reach them. The row starts at the left edge instead, and each control keeps its own width (the rule for every
  // control, on any screen). The measured boxes are the Playwright adapter's.
  const env = laidOut();
  expect(
    declarationsFor(".chat-actions", env)["justify-content"],
    "the header row alignment",
  ).toBe("flex-start");
  expect(
    declarationsFor(".chat-actions > *", env)["flex"],
    "a header control can shrink",
  ).toBe("none");
});

step("the repository write toggle is one line tall", () => {
  // Its label stays on one line, so the pill does not grow to three lines in a short row.
  const declared = declarationsFor(".repository-access-badge", laidOut());
  expect(declared["white-space"], "the write toggle wraps its label").toBe(
    "nowrap",
  );
});

step("every header control is reachable by scrolling the header", () => {
  // The controls keep their own widths on one row, which scrolls sideways, so each one can be brought into view. The
  // Playwright adapter scrolls to each control and measures it.
  const env = laidOut();
  const row = declarationsFor(".chat-actions", env);
  expect(row["flex-wrap"], "the header controls wrap").toBe("nowrap");
  expect(scrolls(row, "x"), "the header row does not scroll sideways").toBe(
    true,
  );
  expect(
    declarationsFor(".chat-actions > *", env)["flex"],
    "a header control can shrink",
  ).toBe("none");
});

step("the header row fades at its edge to show more controls", () => {
  // A right-edge fade over the row is the visible cue that more controls follow the ones in view.
  const fade = declarationsFor(".chat-actions", laidOut())["mask-image"] ?? "";
  expect(
    fade.includes("linear-gradient") && fade.includes("transparent"),
    `the header row mask is ${JSON.stringify(fade)}`,
  ).toBe(true);
});

step("each theme button is at least 44 pixels across", () => {
  // The theme control holds three buttons, each a touch target of its own (on a touch pointer only).
  const env = laidOut();
  expect(env.coarse, "the theme buttons are checked on a touch pointer").toBe(
    true,
  );
  const control = pixels(
    declarationsFor(".chat-theme-control", env)["width"],
    "the theme control width",
    env,
  );
  expect(
    control,
    "the theme control is too narrow for three touch targets",
  ).toBeGreaterThanOrEqual(3 * TOUCH_THEME_BUTTON_PX);
  const minWidth = pixels(
    declarationsFor(".chat-theme-control button", env)["min-width"],
    "the theme button min-width",
    env,
  );
  expect(
    minWidth,
    "the theme button width on a touch screen",
  ).toBeGreaterThanOrEqual(TOUCH_THEME_BUTTON_PX);
});

step(
  "the visitor types a draft of {int} lines into the Codex message box",
  (count) => {
    // The message box grows with the draft in the browser (field-sizing) and is capped by the window's height. The
    // measured growth is the Playwright adapter's; here the draft's line count is kept for the budget.
    remember("codexDraftLines", Number(count));
  },
);

/**
 * The heights the parts of the Codex panel take for the laid-out window and the recorded draft: the header, the
 * composer around the message box, and the message box, capped by the window. The conversation keeps what is left.
 * The header's controls count as one row here; the Playwright adapter measures the real rows of a wrapped header.
 */
function codexPanelBudget(env: Environment): {
  header: number;
  composer: number;
  box: number;
  list: number;
} {
  const [headerTop, headerBottom] = paddingBlockPx(
    declarationsFor(".chat-header", env),
    env,
    "the Codex header",
  );
  const logo = pixels(
    declarationsFor(".brand-logo", env)["height"],
    "the logo height",
    env,
  );
  const header = headerTop + headerBottom + logo + CONTROL_ROW_PX;
  const [composerTop, composerBottom] = paddingBlockPx(
    declarationsFor(".composer", env),
    env,
    "the composer",
  );
  const composer = composerTop + composerBottom + COMPOSER_LABEL_PX;
  const [fieldTop, fieldBottom] = paddingBlockPx(
    declarationsFor(".composer textarea", env),
    env,
    "the message box",
  );
  const cap = pixels(
    declarationsFor(".composer textarea", env)["max-height"],
    "the message box cap",
    env,
  );
  const floor = pixels(
    declarationsFor(".composer textarea", env)["min-height"],
    "the message box min-height",
    env,
  );
  const wanted =
    draftLines() * LINE_OF_TEXT_PX + fieldTop + fieldBottom + 2 * 2;
  const box = Math.max(floor, Math.min(wanted, cap));
  return { header, composer, box, list: env.height - header - composer - box };
}

step("the Codex Send button is on screen", () => {
  // The composer sits at the foot of the panel, so its Send button is in view while the conversation has room left.
  const budget = codexPanelBudget(laidOut());
  expect(
    budget.list,
    "the message box leaves no room for the composer",
  ).toBeGreaterThanOrEqual(0);
});

step("the Codex header is on screen", () => {
  // The header is the panel's first row; it is cut at the top when the composer and the header need more than the panel.
  const env = laidOut();
  const budget = codexPanelBudget(env);
  expect(
    budget.header,
    "the header is taller than the window",
  ).toBeLessThanOrEqual(env.height);
  expect(
    budget.list,
    "the header and the composer need more than the panel",
  ).toBeGreaterThanOrEqual(0);
});

step("the conversation is at least 25 percent of the screen height", () => {
  const env = laidOut();
  const budget = codexPanelBudget(env);
  expect(
    budget.list,
    `the conversation is ${budget.list} px of a ${env.height} px screen`,
  ).toBeGreaterThanOrEqual(CONVERSATION_SHARE_CAPPED * env.height);
});

// --- Then: the repository access state, the header row's end and the message box's cap (round 3) -------------

step("repository writes are {string}", (state) => {
  // The write state changes the access pill's text and colour, not its place or size; the e2e adapter sets it in
  // the browser. The stylesheet is the same for both states, so each state is checked against the same rules.
  remember("codexWrites", state);
});

step(
  "the repository access state is visible without scrolling the header",
  () => {
    // The access state sits in the controls row beside the scrolling row, outside it, and it never shrinks. Its place in
    // the screen is the Playwright adapter's; this step proves the declared rules that keep it out of the scroll box.
    const env = laidOut();
    const access = declarationsFor(".chat-access", env);
    expect(access["flex"], "the access state can shrink").toBe("none");
    expect(scrolls(access, "x"), "the access state scrolls sideways").toBe(
      false,
    );
    expect(
      scrolls(declarationsFor(".chat-actions", env), "x"),
      "the scrolling row does not scroll",
    ).toBe(true);
    expect(
      declarationsFor(".chat-controls", env)["display"],
      "the controls row is not a flex row",
    ).toBe("flex");
  },
);

step("the repository write toggle is at least 44 pixels tall", () => {
  const env = laidOut();
  const height = pixels(
    declarationsFor(".repository-write-toggle", env)["min-height"],
    "the repository write toggle min-height",
    env,
  );
  expect(
    height,
    `the repository write toggle is ${height} px tall on a touch pointer`,
  ).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
});

step("the header's scrolling row ends inside the screen", () => {
  // A flex child may shrink only with min-width 0; without it the row is as wide as its controls, past the screen.
  const env = laidOut();
  expect(
    pixels(
      declarationsFor(".chat-actions", env)["min-width"],
      "the scrolling row min-width",
      env,
    ),
    "the scrolling row cannot shrink to the screen",
  ).toBe(0);
});

step(
  "the last header control clears the edge fade when the row is scrolled to its end",
  () => {
    // The fade covers the row's last stretch, and the row's end padding is at least as wide as that stretch, so a
    // control scrolled to the end sits clear of the fade.
    const env = laidOut();
    const declared = declarationsFor(".chat-actions", env);
    const fade = /calc\(100% - ([\d.]+(?:rem|px))\)/u.exec(
      declared["mask-image"] ?? "",
    );
    expect(fade, "the row's edge fade").not.toBeNull();
    const fadePx = pixels(fade?.[1], "the fade width", env);
    const endPadding = pixels(
      declared["padding-inline-end"],
      "the row's end padding",
      env,
    );
    expect(
      endPadding,
      `the end padding ${endPadding} px is under the ${fadePx} px fade`,
    ).toBeGreaterThanOrEqual(fadePx);
  },
);

/** The message box cap at a window height: the smaller of 12 rem and 22 percent of the window's height. */
function messageBoxCapPx(env: Environment): number {
  return Math.min(12 * 16, 0.22 * env.height);
}

step(
  "the message box stops at its height cap and scrolls the rest of the draft",
  () => {
    // The cap is the value the stylesheet gives the box at this window's height. The draft that overflows it is
    // measured in Chromium by the Playwright adapter; removing the cap makes this step fail, because no value is left.
    const env = laidOut();
    const cap = pixels(
      declarationsFor(".composer textarea", env)["max-height"],
      "the message box cap",
      env,
    );
    expect(cap, "the message box cap").toBeCloseTo(messageBoxCapPx(env), 3);
  },
);

step("the Codex header is at most 160 pixels tall", () => {
  // Its paddings, its logo and the controls row (the picker stack, a label above a select, counted at its tallest).
  const env = laidOut();
  const [top, bottom] = paddingBlockPx(
    declarationsFor(".chat-header", env),
    env,
    "the Codex header",
  );
  const logo = pixels(
    declarationsFor(".brand-logo", env)["height"],
    "the logo height",
    env,
  );
  const header = top + bottom + logo + CONTROL_STACK_PX;
  expect(header, `the header is ${header} px tall`).toBeLessThanOrEqual(160);
});

/** The controls row's height at its tallest: a picker's label above its select, both on a touch pointer. */
const CONTROL_STACK_PX = 64;

step("the message box is named {string}", (name) => {
  // The name is the label's text, which the template sets. Here the stylesheet must keep the label out of sight
  // without removing it from the accessibility tree: `display: none` would remove it.
  expect(name).toBe("Message");
  const declared = declarationsFor(".composer .label", laidOut());
  expect(declared["display"], "the label is removed from the page").not.toBe(
    "none",
  );
  expect(
    declared["visibility"],
    "the label is hidden from the accessibility tree",
  ).not.toBe("hidden");
});

step("the visible Message label takes no space in the composer", () => {
  const declared = declarationsFor(".composer .label", laidOut());
  expect(declared["position"], "the label is taken out of the flow").toBe(
    "absolute",
  );
  expect(
    pixels(declared["width"], "the label width", laidOut()),
    "the label width",
  ).toBeLessThanOrEqual(1);
  expect(
    pixels(declared["height"], "the label height", laidOut()),
    "the label height",
  ).toBeLessThanOrEqual(1);
});

// --- Then: a long unbroken draft keeps the panel, the composer and Send inside the screen ------------------------

step(
  "the visitor types an unbroken {int} character address into the Codex message box",
  (length) => {
    // The Playwright adapter types the address and measures the boxes. The length is kept so the scenario reads as
    // the draft it names; the declared widths below are what keep a long line from widening the panel.
    remember("codexUnbrokenDraft", Number(length));
  },
);

step("the Codex chat panel is inside the screen", () => {
  // The shell's column may not grow to fit its content, and the panel keeps no automatic minimum width, so the
  // panel stays within the window whatever the draft holds.
  const env = laidOut();
  expect(
    declarationsFor(".chat-shell", env)["grid-template-columns"],
    "the shell's column is sized to its content",
  ).toBe("minmax(0, 1fr)");
  expect(
    declarationsFor(".chat-panel", env)["min-width"],
    "the panel keeps an automatic minimum width",
  ).toBe("0");
});

step(
  "the Send button is on screen and is not covered by the message box",
  () => {
    // The message box's inline size may not come from its content: with field-sizing the box would otherwise take the
    // width of its longest unbroken line and cover Send. Its width is the composer's cell, and Send keeps its column.
    const env = laidOut();
    expect(
      declarationsFor(".composer textarea", env)["contain"],
      "the message box's inline size comes from its content",
    ).toBe("inline-size");
    expect(
      declarationsFor(".composer", env)["grid-template-columns"],
      "the composer's columns",
    ).toBe("minmax(0, 1fr) auto");
  },
);

step("the Codex page does not scroll sideways", () => {
  // The page is as wide as its shell, and the shell's column cannot grow past the window, so nothing overflows
  // sideways. The Playwright adapter compares the document's scroll width with its client width.
  const env = laidOut();
  expect(
    declarationsFor(".chat-shell", env)["grid-template-columns"],
    "the shell's column can grow past the window",
  ).toBe("minmax(0, 1fr)");
});
