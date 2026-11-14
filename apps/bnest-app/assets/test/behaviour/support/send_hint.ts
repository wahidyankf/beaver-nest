// The send shortcut hint as a visitor sees it (ADR 005, decision 1). The two wordings come from the production template,
// and the shipped stylesheet decides which one shows for the visitor's pointer. Nothing here is copied from the feature.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect } from "vitest";
import {
  declarationsFor,
  lengthPx,
  resolveVars,
  type Environment,
} from "../../support/shipped_css";

const here = path.dirname(fileURLToPath(import.meta.url));
const APP_ROOT = path.resolve(here, "../../../..");

export const CODEX_TEMPLATE = path.join(
  APP_ROOT,
  "lib/bnest_app_web/live/chat_live.ex",
);
export const FAMILY_TEMPLATE = path.join(
  APP_ROOT,
  "lib/bnest_app_web/controllers/family_chat_html/room.html.heex",
);

/** The text of one hint span in the template. A missing span fails: the wording must come from production. */
function spanText(source: string, role: string): string {
  const match = new RegExp(`<span class="${role}">([^<]*)</span>`, "u").exec(
    source,
  );
  if (!match?.[1]) throw new Error(`the template has no ${role} span`);
  return match[1].trim();
}

/** The wordings a visitor sees: a span shows unless the shipped stylesheet sets its display to none for this pointer. */
export function hintAsSeen(template: string, env: Environment): string[] {
  const source = readFileSync(template, "utf8");
  const shown: string[] = [];
  if (declarationsFor(".hint-keyboard", env)["display"] !== "none") {
    shown.push(spanText(source, "hint-keyboard"));
  }
  if (declarationsFor(".hint-touch", env)["display"] !== "none") {
    shown.push(spanText(source, "hint-touch"));
  }
  return shown;
}

/** Asserts the hint box takes no row: the shipped stylesheet takes it out of flow and sizes it to at most one pixel. */
export function assertHintTakesNoRow(selector: string, env: Environment): void {
  const declared = declarationsFor(selector, env);
  expect(declared["position"], `${selector} is in the flow`).toBe("absolute");
  for (const property of ["width", "height"]) {
    const value = lengthPx(resolveVars(declared[property] ?? ""), env);
    expect(
      value,
      `${selector} ${property} is ${declared[property]}`,
    ).toBeLessThanOrEqual(1);
  }
}

/**
 * The viewport and pointer a hint step reads. The hint's display rules depend on the pointer alone, so when a scenario
 * never laid the page out, a desktop viewport is enough.
 */
export function hintEnvironment(
  laidOut: { viewport: { width: number; height: number } } | null,
  coarse: boolean,
): Environment {
  return {
    width: laidOut?.viewport.width ?? 1024,
    height: laidOut?.viewport.height ?? 768,
    coarse,
  };
}
