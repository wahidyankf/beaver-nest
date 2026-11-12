// Step bindings for the Codex conversation rule of specs/apps/bnest/app-fe/behaviours/chat.feature that follows the
// newest message, and for the accessible names of its scrollable tables and code blocks (tag `@fe-vitest-unit`).
//
// The conversation is the shared scrolling region of `js/scroll_follow.js`, modelled in happy-dom (`support/
// scroll_scene.ts`): a scenario changes its content the way a reply, a drawn diagram or a loaded picture does, and the
// Then checks where the reader is. The names come from `js/scroll_region_names.js`, the module the room runs. The
// rendered positions and the real scroll of a streamed reply are measured in Chromium by `bnest-app-fe-e2e`.

import { expect } from "vitest";
import { syncScrollRegionNames } from "../../js/scroll_region_names.js";
import {
  closeRegion,
  currentRegion,
  followRegion,
  hasRegion,
  openRegion,
  readerScrollsTo,
  settle,
} from "./support/scroll_scene";
import { forgetScenario } from "./support/scenario_memory";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

const CONVERSATION_CONTENT_PX = 1000;
const CONVERSATION_BOX_PX = 300;
const REPLY_PX = 200;
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

export function codexFollowSteps(): readonly StepDefinition[] {
  return registry;
}

/** Forgets the conversation a scenario opened; `verify.ts` calls this after every scenario. */
export function resetCodexFollow(): void {
  closeRegion();
  forgetScenario();
}

/** Whether the reader is at the newest content: its position is the largest one the content allows. */
function atNewest(): boolean {
  const { metrics } = currentRegion();
  return metrics.top === metrics.content - metrics.box;
}

/** The conversation as the page opens it: a long one, the reader at its newest message. */
function openConversation(): void {
  openRegion(CONVERSATION_CONTENT_PX, CONVERSATION_BOX_PX);
  followRegion();
}

/** Codex sends a reply part: the content grows by the reply's height under the reader. */
async function codexStreams(pixels: number): Promise<void> {
  const current = currentRegion();
  current.metrics.content += pixels;
  current.region.append(document.createElement("p"));
  await settle();
}

// --- Given ---------------------------------------------------------------------------

// A long conversation with its older replies above the reader: the region is open, and nothing follows it yet.
step("the visitor has a Codex conversation with older replies", () => {
  openRegion(CONVERSATION_CONTENT_PX, CONVERSATION_BOX_PX);
});

step("the visitor is at the bottom of the Codex conversation", () => {
  openConversation();
  readerScrollsTo(
    currentRegion().metrics.content - currentRegion().metrics.box,
  );
});

step(
  "the visitor has sent a message and Codex is still streaming its reply",
  () => {
    // The submit pins the reader to the bottom (the chat hook), and the reply is still streaming.
    openConversation();
  },
);

step("the visitor has scrolled up in the Codex conversation", () => {
  if (!hasRegion()) openConversation();
  readerScrollsTo(100);
});

step("a Codex reply holds a diagram that is not yet drawn", () => {
  if (!hasRegion()) openConversation();
  const current = currentRegion();
  const marker = document.createElement("pre");
  marker.dataset["bnestDiagram"] = "mermaid";
  current.region.append(marker);
});

// --- When ----------------------------------------------------------------------------

// The page starts its follower, which moves the reader to the newest reply.
step("the visitor opens the Codex chat page", () => {
  if (!hasRegion()) openRegion(CONVERSATION_CONTENT_PX, CONVERSATION_BOX_PX);
  followRegion({ startAtBottom: true });
});

step("the visitor sends a message and Codex streams the reply", async () => {
  // The composer's submit pins the reader to the bottom before the reply starts (the chat hook's submit listener).
  currentRegion().follower?.pin();
  await codexStreams(REPLY_PX);
});

step("Codex streams more of the reply", async () => {
  await codexStreams(REPLY_PX);
});

step("the diagram is drawn", async () => {
  // The marker is replaced by its drawing, which is taller than the source it stood for.
  const current = currentRegion();
  const marker = current.region.querySelector(
    'pre[data-bnest-diagram="mermaid"]',
  );
  expect(marker !== null, "no diagram is waiting to be drawn").toBe(true);
  const figure = document.createElement("figure");
  marker?.replaceWith(figure);
  current.metrics.content += DIAGRAM_PX;
  await settle();
});

// --- Then ----------------------------------------------------------------------------

step("the newest reply is at the bottom of the conversation", () => {
  expect(atNewest(), "the reader is not at the newest reply").toBe(true);
});

step("the newest part of the reply is in view", () => {
  expect(atNewest(), "the newest part of the reply is below the fold").toBe(
    true,
  );
});

step("the newest reply is in view above the composer", () => {
  expect(atNewest(), "the newest reply is below the fold").toBe(true);
});

step("the visitor's position in the conversation does not change", () => {
  expect(currentRegion().metrics.top, "the reader was moved").toBe(100);
});

// --- Then: accessible names of scrollable regions ------------------------------------

/** Lays out a wide table and a wide code block in the conversation, as a Codex reply renders them, and names them. */
function nameRegionsOfReply(): { table: HTMLElement; code: HTMLElement } {
  if (!hasRegion()) openConversation();
  const current = currentRegion();
  const body = document.createElement("div");
  body.className = "markdown-body";
  body.innerHTML =
    "<table><tr><td>Menu</td></tr></table><pre><code>wide code</code></pre>";
  current.region.append(body);
  const table = body.querySelector("table") as HTMLElement;
  const code = body.querySelector("pre") as HTMLElement;
  for (const region of [table, code]) {
    Object.defineProperty(region, "scrollWidth", {
      configurable: true,
      value: 1000,
    });
    Object.defineProperty(region, "clientWidth", {
      configurable: true,
      value: 300,
    });
  }
  syncScrollRegionNames(body);
  return { table, code };
}

step("the wide table is named {string}", (name) => {
  const { table } = nameRegionsOfReply();
  expect(table.getAttribute("aria-label")).toBe(name);
});

step("the wide code block is named {string}", (name) => {
  const { code } = nameRegionsOfReply();
  expect(code.getAttribute("aria-label")).toBe(name);
  expect(code.getAttribute("role")).toBe("group");
});
