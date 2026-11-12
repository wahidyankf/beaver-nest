// Step bindings for the Family Chat scenario that keeps the newest message in view when a diagram draws (tag
// `@fe-vitest-unit` in specs/apps/bnest/app-fe/behaviours/family_chat.feature).
//
// The history is the shared scrolling region of `js/scroll_follow.js`, modelled in happy-dom (`support/scroll_scene.ts`).
// The room places its reader at their last read position, so the follower waits for the reader's first scroll
// (`startAtBottom: false`, as `family_chat/mount_browser.js` starts it). The rendered positions are measured in
// Chromium by `bnest-app-fe-e2e`.

import { expect } from "vitest";
import {
  closeRegion,
  currentRegion,
  followRegion,
  hasRegion,
  openRegion,
  readerScrollsTo,
  settle,
} from "./support/scroll_scene";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

const HISTORY_CONTENT_PX = 1000;
const HISTORY_BOX_PX = 300;
const DIAGRAM_PX = 150;

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

export function familyChatFollowSteps(): readonly StepDefinition[] {
  return registry;
}

/** Forgets the history a scenario opened; `verify.ts` calls this after every scenario. */
export function resetFamilyChatFollow(): void {
  closeRegion();
}

/** Whether the reader is at the newest message: their position is the largest the history allows. */
function atNewest(): boolean {
  const { metrics } = currentRegion();
  return metrics.top === metrics.content - metrics.box;
}

step("a visitor is at the bottom of the family chat conversation", () => {
  openRegion(HISTORY_CONTENT_PX, HISTORY_BOX_PX);
  followRegion({ startAtBottom: false });
  readerScrollsTo(
    currentRegion().metrics.content - currentRegion().metrics.box,
  );
});

step(
  "Ayah has sent a family chat message with a mermaid flowchart that is not yet drawn",
  () => {
    if (!hasRegion()) openRegion(HISTORY_CONTENT_PX, HISTORY_BOX_PX);
    const current = currentRegion();
    const marker = document.createElement("pre");
    marker.dataset["bnestDiagram"] = "mermaid";
    current.region.append(marker);
  },
);

step("the diagram is drawn", async () => {
  const current = currentRegion();
  const marker = current.region.querySelector(
    'pre[data-bnest-diagram="mermaid"]',
  );
  expect(marker !== null, "no diagram is waiting to be drawn").toBe(true);
  marker?.replaceWith(document.createElement("figure"));
  current.metrics.content += DIAGRAM_PX;
  await settle();
});

step("the newest message is in view above the composer", () => {
  expect(atNewest(), "the newest message is below the fold").toBe(true);
});
