import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then } = createBdd();

// The newest Codex reply, the same reply codex_markdown.steps.ts checks.
function latestReply(page: Page) {
  return page.locator("[data-role=assistant-message]").last();
}

// ADR 004, Decision 2: the server keeps a diagram as an ordinary code block while the reply streams, and
// marks it for drawing once the reply is complete. The browser then replaces the marker with a drawn picture,
// so the marked state is read as the drawn state: a figure the browser drew (codex_diagrams.steps.ts proves the
// picture itself).
const PLAIN_DIAGRAM = "pre:not([data-bnest-diagram]) > code.language-mermaid";
const MARKED_OR_DRAWN =
  'pre[data-bnest-diagram="mermaid"], figure.bnest-diagram';
const DRAWN = 'figure.bnest-diagram[data-bnest-diagram-state="drawn"]';
const MARKER = 'pre[data-bnest-diagram="mermaid"]';

// Waits until `count` diagrams are marked or drawn, then scrolls each waiting marker into view so it draws.
async function expectMarkedForDrawing(page: Page, count: number) {
  // ADR 004, Decision 3: a diagram is drawn only when it is within `prefetchMarginPx` of the viewport. On a small
  // viewport the last marker sits below that margin, so the visitor scrolls to it, as a reader does, and the
  // browser draws it. First the server's claim: `count` diagrams are marked (or already drawn).
  await expect(latestReply(page).locator(MARKED_OR_DRAWN)).toHaveCount(count);
  // Each marker still waiting is scrolled to in turn, as a reader scrolling down would reach it, until none is left.
  // The scroll runs in the page on the reply, not on a handle: a marker is replaced by its picture while the scroll
  // starts, and a handle to a replaced node would fail with "not attached".
  // Several pictures wait for one cold engine start and then draw in turn; on mobile that can pass the default
  // 5 s wait. 28 s is the cold-draw bound (diagram_limits.js: engine start 20 s plus render 8 s).
  await expect
    .poll(
      async () => {
        await latestReply(page).evaluate((reply, selector) => {
          reply.querySelector(selector)?.scrollIntoView({ block: "center" });
        }, MARKER);
        return latestReply(page).locator(MARKER).count();
      },
      { timeout: 28_000 },
    )
    .toBe(0);
  await expect(latestReply(page).locator(DRAWN)).toHaveCount(count, {
    timeout: 28_000,
  });
}

Then(
  "the latest Codex reply keeps the diagram as a plain code block",
  async ({ page }) => {
    await expect(latestReply(page).locator(PLAIN_DIAGRAM)).toHaveCount(1);
  },
);

Then(
  "the latest Codex reply keeps {int} diagrams as plain code blocks",
  async ({ page }, count: number) => {
    await expect(latestReply(page).locator(PLAIN_DIAGRAM)).toHaveCount(count);
  },
);

Then(
  "the latest Codex reply does not mark a diagram for drawing",
  async ({ page }) => {
    await expect(latestReply(page).locator(MARKED_OR_DRAWN)).toHaveCount(0);
  },
);

Then(
  "the latest Codex reply marks the diagram for drawing",
  async ({ page }) => {
    await expectMarkedForDrawing(page, 1);
  },
);

Then(
  "the latest Codex reply marks {int} diagrams for drawing",
  async ({ page }, count: number) => {
    await expectMarkedForDrawing(page, count);
  },
);
