import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Codex chat header row, the composer cap and the Send button on touch and short screens
// (chat.feature, Rule "Codex chat on touch and short screens"). Each Then reads a rendered box in real Chromium; the
// Vitest binding (apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts) proves the declared CSS. The repository
// access state and the message box rules are in codex_header_access.steps.ts. Kept apart from codex_touch.steps.ts so
// each step file stays within its line limit.

const { Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A long Codex draft grows the message box to its cap and keeps Send and the header on screen

// --- Header row and the composer's cap (chat.feature, Rule "Codex chat on touch and short screens") ---

type Box = { x: number; y: number; width: number; height: number };

async function boxOf(locator: Locator, label: string): Promise<Box> {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

function viewportHeight(page: Page): number {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  return viewport.height;
}

const CHAT_CONVERSATION = "#chat-conversation";
const CONVERSATION_SHARE_CAPPED = 0.25;

When(
  "the visitor types a draft of {int} lines into the Codex message box",
  async ({ page }, count: number) => {
    const input = page.locator('[data-role="chat-composer"]');
    await expect(input).toBeEnabled();
    await input.fill(
      Array.from(
        { length: count },
        (_unused, index) => `line ${index + 1}`,
      ).join("\n"),
    );
  },
);

Then(
  "the conversation is at least 25 percent of the screen height",
  async ({ page }) => {
    const box = await boxOf(
      page.locator(CHAT_CONVERSATION),
      "the conversation",
    );
    const height = viewportHeight(page);
    expect(
      box.height,
      `the conversation is ${box.height} px of a ${height} px screen`,
    ).toBeGreaterThanOrEqual(CONVERSATION_SHARE_CAPPED * height);
  },
);
