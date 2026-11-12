import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Codex chat header row, its theme buttons, the composer cap and the Send button on touch and short screens
// (chat.feature, Rule "Codex chat on touch and short screens"). Each Then reads a rendered box in real Chromium; the
// Vitest binding (apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts) proves the declared CSS. The repository
// access state and the message box rules are in codex_header_access.steps.ts. Kept apart from codex_touch.steps.ts so
// each step file stays within its line limit.

const { Then, When } = createBdd();

const TOUCH_TARGET_PX = 44;

// --- Header row, theme buttons and the composer's cap (chat.feature, Rule "Codex chat on touch and short screens") ---

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

const HEADER_ROW = ".chat-actions";
const SEND_BUTTON = ".send-button";
const CHAT_CONVERSATION = "#chat-conversation";
const CONVERSATION_SHARE_CAPPED = 0.25;

Then("the header controls start inside the header", async ({ page }) => {
  // A landscape phone's row starts at the header's left edge, so its first control is not clipped there, and the row
  // scrolls to its last control, which is then inside the header.
  const header = await boxOf(page.locator(".chat-header"), "the Codex header");
  const row = page.locator(HEADER_ROW);
  const controls = page.locator(`${HEADER_ROW} > *`);
  const count = await controls.count();
  expect(count, "header controls rendered").toBeGreaterThanOrEqual(5);
  const boxes = await Promise.all(
    Array.from({ length: count }, (_unused, index) =>
      boxOf(controls.nth(index), `header control ${index}`),
    ),
  );
  for (const [index, box] of boxes.entries()) {
    expect(
      box.x,
      `header control ${index} starts left of the header`,
    ).toBeGreaterThanOrEqual(header.x - 0.5);
  }
  await row.evaluate((element) => {
    element.scrollLeft = element.scrollWidth;
  });
  const last = await boxOf(controls.nth(count - 1), "the last header control");
  expect(
    last.x + last.width,
    "the last header control is not reachable by scrolling",
  ).toBeLessThanOrEqual(header.x + header.width + 0.5);
});

Then("the repository write toggle is one line tall", async ({ page }) => {
  // The label is on one line when all of its text rectangles share one top edge. The control's height is not used: on
  // a touch pointer the control is at least 44 pixels tall whatever its label does.
  const toggle = page.locator("[data-role=repository-write-toggle]");
  await expect(toggle).toBeVisible();
  const lines = await toggle.evaluate((element) => {
    const range = document.createRange();
    range.selectNodeContents(element);
    return new Set(
      Array.from(range.getClientRects(), (rect) => Math.round(rect.top)),
    ).size;
  });
  expect(lines, "the lines of the repository write toggle's label").toBe(1);
});

Then(
  "every header control is reachable by scrolling the header",
  async ({ page }) => {
    // A control reaches the reader when the row can scroll its start and its end into the header. A control wider
    // than the visible part of the row (the model select on a phone) cannot show both at once, so each edge is
    // scrolled to and measured on its own, as a keyboard reader's focus does.
    const header = await boxOf(
      page.locator(".chat-header"),
      "the Codex header",
    );
    const controls = page.locator(`${HEADER_ROW} > *`);
    const count = await controls.count();
    expect(count, "header controls rendered").toBeGreaterThanOrEqual(5);
    // Each control is scrolled to and measured before the next one, so the steps run in order.
    await Array.from({ length: count }, (_unused, index) => index).reduce(
      async (previous, index) => {
        await previous;
        const control = controls.nth(index);
        await control.evaluate((element) =>
          element.scrollIntoView({ block: "nearest", inline: "start" }),
        );
        const start = await boxOf(control, `header control ${index}`);
        expect(
          start.x,
          `header control ${index} starts left of the header`,
        ).toBeGreaterThanOrEqual(header.x - 0.5);
        expect(
          start.x,
          `header control ${index} starts right of the header`,
        ).toBeLessThanOrEqual(header.x + header.width);
        await control.evaluate((element) =>
          element.scrollIntoView({ block: "nearest", inline: "end" }),
        );
        const end = await boxOf(control, `header control ${index}`);
        expect(
          end.x + end.width,
          `header control ${index} ends right of the header`,
        ).toBeLessThanOrEqual(header.x + header.width + 0.5);
      },
      Promise.resolve(),
    );
  },
);

Then(
  "the header row fades at its edge to show more controls",
  async ({ page }) => {
    const fade = await page
      .locator(HEADER_ROW)
      .evaluate((element) => getComputedStyle(element).maskImage);
    expect(fade, "the header row's edge fade").toContain("linear-gradient");
  },
);

Then("each theme button is at least 44 pixels across", async ({ page }) => {
  const buttons = page.locator(".chat-theme-control button");
  await expect(buttons).toHaveCount(3);
  const boxes = await Promise.all(
    [0, 1, 2].map((index) =>
      boxOf(buttons.nth(index), `theme button ${index}`),
    ),
  );
  for (const [index, box] of boxes.entries()) {
    expect(box.width, `theme button ${index} width`).toBeGreaterThanOrEqual(
      TOUCH_TARGET_PX,
    );
  }
});

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
