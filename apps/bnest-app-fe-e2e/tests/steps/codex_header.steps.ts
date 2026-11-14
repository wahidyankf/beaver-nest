import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Codex chat header row, the composer cap and the Send button on touch and short screens
// (chat.feature, Rule "Codex chat on touch and short screens"). Each Then reads a rendered box in real Chromium; the
// Vitest binding (apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts) proves the declared CSS. The repository
// access state and the message box rules are in codex_header_access.steps.ts. Kept apart from codex_touch.steps.ts so
// each step file stays within its line limit.

const { Then, When } = createBdd();

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

const SEND_BUTTON = ".send-button";
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

Then("the Codex Send button is on screen", async ({ page }) => {
  const send = page.locator(SEND_BUTTON);
  await expect(send).toBeVisible();
  const box = await boxOf(send, "the Send button");
  expect(box.y, "the Send button top edge").toBeGreaterThanOrEqual(0);
  expect(box.y + box.height, "the Send button bottom edge").toBeLessThanOrEqual(
    viewportHeight(page) + 1,
  );
});

Then("the Codex header is on screen", async ({ page }) => {
  const box = await boxOf(page.locator(".chat-header"), "the Codex header");
  expect(box.y, "the Codex header is cut at the top").toBeGreaterThanOrEqual(
    -0.5,
  );
  expect(
    box.y + box.height,
    "the Codex header's bottom edge",
  ).toBeLessThanOrEqual(viewportHeight(page) + 1);
});

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
