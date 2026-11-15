// Step bindings for the Family Chat rules of specs/apps/bnest/app-fe/behaviours/family_chat.feature (tag `@fe-vitest-unit`)
// that cover the phone layout budget, the composer hint, and the single light appearance (ADR 005, owner request of
// 2026-11-13). Each Then reads the declared values of the shipped stylesheet for the scenario's viewport and pointer;
// the rendered boxes are measured in Chromium by `bnest-app-fe-e2e`, which owns the same step texts.

import { readFileSync } from "node:fs";
import { expect } from "vitest";
import { activePage, device } from "./support/browser_room";
import {
  recall,
  recallOr,
  remember,
  forgetScenario,
} from "./support/scenario_memory";
import {
  declarationsFor,
  lengthPx,
  type Environment,
} from "../support/shipped_css";
import { FAMILY_TEMPLATE } from "./support/send_hint";
import {
  assertNoDarkPreferenceRule,
  assertNoThemeControl,
  assertPageBackgroundIsLight,
  assertSingleLightAppearance,
  templateFor,
} from "./support/appearance";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

/** Fails the step when the condition does not hold. Vitest's `expect` without a matcher asserts nothing. */
function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

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

export function familyChatPhoneSteps(): readonly StepDefinition[] {
  return registry;
}

/** Forgets what a scenario recorded; `verify.ts` calls this after every scenario. */
export function resetFamilyChatPhone(): void {
  forgetScenario();
}

// --- Pointer, viewport and the layout the page is laid out for --------------------------------

step("the visitor's pointer is a touch pointer", () => {
  remember("familyCoarse", true);
});

step("the visitor's pointer is a fine pointer", () => {
  remember("familyCoarse", false);
});

step("the page is laid out", () => {
  // The layout the Thens read: the viewport the scenario set and the pointer it chose.
  remember("familyLaidOut", {
    viewport: device().viewport,
    coarse: recallOr("familyCoarse", false),
  });
});

// --- The composer hint -----------------------------------------------------------------------

// --- Single light appearance ------------------------------------------------------------------

step("an approved admin opens {string}", (pathname) => {
  check(
    readFileSync(templateFor(pathname), "utf8").length > 0,
    `no template serves ${pathname}`,
  );
  remember("openedPath", pathname);
});

// The dark preference has no effect because no rule answers it (ADR 005, decision 3).
step("the visitor's system prefers a dark color scheme", () => {
  assertNoDarkPreferenceRule();
});

step("the page has no color theme control", () => {
  assertNoThemeControl();
});

step("the page background is light", () => {
  assertSingleLightAppearance();
  assertPageBackgroundIsLight();
});

// --- Budget rows (family_chat.feature, the Rule "Family Chat conversation has most of a phone screen"). The numeric
// budgets are measured in Chromium by `bnest-app-fe-e2e`'s family-chat-composer.steps.ts, which owns the same step texts
// and holds the floors and limits in its own code. The Thens here prove what the declared shell grid and the room
// template give the layout: the history is the one row that takes the room left over, and the header and the composer
// are the rows around it. No height in pixels is asserted here.

const FAMILY_ROOM_TEMPLATE = readFileSync(FAMILY_TEMPLATE, "utf8");

/** The environment the last "the page is laid out" step fixed for the Family Chat room. */
function familyLaidOutEnv(): Environment {
  const laid = recall<{
    viewport: { width: number; height: number };
    coarse: boolean;
  }>("familyLaidOut");
  return {
    width: laid.viewport.width,
    height: laid.viewport.height,
    coarse: laid.coarse,
  };
}

/** The place of a template fragment in room.html.heex, failing when the fragment is missing. */
function familyTemplateIndex(fragment: string): number {
  const index = FAMILY_ROOM_TEMPLATE.indexOf(fragment);
  expect(index, `room.html.heex has no ${fragment}`).toBeGreaterThanOrEqual(0);
  return index;
}

/** The header, the history and the composer come in that order in the template. */
function familyRowsInOrder(): void {
  const header = familyTemplateIndex('class="family-chat-header"');
  const history = familyTemplateIndex('class="family-chat-history"');
  const composer = familyTemplateIndex('class="family-chat-composer"');
  expect(
    header < history && history < composer,
    "the header, the history and the composer are not in that order",
  ).toBe(true);
}

/** The shell's declared rows: auto, auto, the history's `1fr`, auto, with the history on row 3 and the composer on row 4. */
function familyShellRows(env: Environment): string[] {
  const shell = declarationsFor(".family-chat-shell", env);
  const rows = (shell["grid-template-rows"] ?? "").split(/\s+/u);
  expect(rows, "the shell does not declare four rows").toHaveLength(4);
  return rows;
}

// The {int} percentage is not read here: the unit layer proves the row rule (the history takes the rest of the shell).
// The measured share at each viewport is checked in Chromium (bnest-app-fe-e2e, Family composer and layout steps).
step(
  "the history takes at least {int} percent of the screen with an empty draft",
  () => {
    const env = familyLaidOutEnv();
    const rows = familyShellRows(env);
    expect(rows[2], "the history is not the row that takes the rest").toBe(
      "1fr",
    );
    const history = declarationsFor(".family-chat-history", env);
    expect(history["grid-row"], "the history is not on row 3").toBe("3");
    expect(
      history["min-height"],
      "the history can be taller than its row",
    ).toBe("0");
    expect(
      history["overflow-y"],
      "the history does not scroll its messages",
    ).toBe("auto");
    familyRowsInOrder();
  },
);

step(
  "the header and the composer take at most {int} pixels outside the history",
  () => {
    const env = familyLaidOutEnv();
    const rows = familyShellRows(env);
    for (const index of [0, 1, 3]) {
      expect(
        rows[index],
        `row ${index + 1} takes the room the history needs`,
      ).toBe("auto");
    }
    expect(
      declarationsFor(".family-chat-composer", env)["grid-row"],
      "the composer is not on row 4",
    ).toBe("4");
    familyRowsInOrder();
  },
);

// The unit layer proves the composer is in its own row after the history and not taken out of the flow. That the
// newest message sits fully above it on screen is measured in Chromium.
step("the newest message is fully above the composer", () => {
  const env = familyLaidOutEnv();
  familyRowsInOrder();
  expect(
    declarationsFor(".family-chat-composer", env)["grid-row"],
    "the composer is not on the row after the history",
  ).toBe("4");
  expect(
    declarationsFor(".family-chat-composer", env)["position"] ?? "",
    "the composer is taken out of the flow, so it can cover the newest message",
  ).not.toBe("absolute");
});

// --- The actions control: visible, large enough to press, beside its bubble (family_chat.feature) ----------------------
// The declared values of the shipped stylesheet are read for the scenario's viewport and pointer. The rendered boxes are
// measured in Chromium by `bnest-app-fe-e2e`, which owns the same step texts.

/** The actions control the renderer built for the room's committed message. */
function actionsControl(): HTMLElement {
  const control = activePage().document.querySelector<HTMLElement>(
    '[data-role="family-chat-message-more"]',
  );
  if (!control) throw new Error("the room shows no actions control");
  return control;
}

// The control is shown on a fine and on a coarse pointer: no coarse-pointer rule hides it (ADR 005, decision 5). Both
// pointers are checked, so a rule that hides it only on touch fails here.
step("the actions control of that message is visible without a hover", () => {
  for (const coarse of [false, true]) {
    const pointer = coarse ? "a touch" : "a fine";
    const declared = declarationsFor(".family-chat-message-more", {
      ...familyLaidOutEnv(),
      coarse,
    });
    check(
      (declared["opacity"] ?? "1") !== "0",
      `the actions control is declared at opacity ${declared["opacity"]} on ${pointer} pointer`,
    );
    check(
      declared["display"] !== "none",
      `the actions control is declared hidden on ${pointer} pointer`,
    );
  }
});

step(
  "the actions control of that message is at least 44 by 44 CSS pixels",
  () => {
    const env = familyLaidOutEnv();
    const declared = declarationsFor(".family-chat-message-more", env);
    check(
      lengthPx(declared["min-width"] ?? "0", env) >= 44,
      `the actions control's min-width is ${declared["min-width"]}`,
    );
    check(
      lengthPx(declared["min-height"] ?? "0", env) >= 44,
      `the actions control's min-height is ${declared["min-height"]}`,
    );
  },
);

step("the actions control of that message does not overlap its bubble", () => {
  // The control is a grid item in the row under its bubble, so no declared absolute or fixed position can lay it over
  // the bubble. The rendered boxes are measured in Chromium.
  const declared = declarationsFor(
    ".family-chat-message-more",
    familyLaidOutEnv(),
  );
  check(
    !["absolute", "fixed"].includes(declared["position"] ?? ""),
    `the actions control is declared at position ${declared["position"]}`,
  );
});

step("the actions control of that message is inside the history", () => {
  check(
    actionsControl().closest(".family-chat-history") !== null,
    "the actions control is outside the history",
  );
});

step("the actions control of that message has an accessible name", () => {
  const label = actionsControl().getAttribute("aria-label") ?? "";
  check(
    /^Actions for .+'s message$/u.test(label),
    `the actions control is named ${JSON.stringify(label)}`,
  );
});
