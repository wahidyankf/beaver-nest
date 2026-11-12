import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { composerInput } from "../support/family-chat";

// The layout scenarios of family_chat.feature's "Responsive and accessible presentation" rule that are tagged
// `@fe-vitest-unit`: a short screen keeps its conversation, a narrow phone's message takes most of the width, the
// composer grows with its draft and stops at six lines, and the Send button's text passes contrast. Each Then reads
// a rendered box or a computed style in real Chromium. Their unit proof is the Vitest binding in
// apps/bnest-app/assets/test/behaviour/family_chat_layout.steps.ts.

const { Then, When } = createBdd();

// One composer line is 1.5 em of 16 pixels; the composer adds 0.7 rem of padding and 2 pixels of border on each side.
const LINE_PX = 24;
const COMPOSER_CHROME_PX = 2 * 11.2 + 2 * 2;
const SIX_LINES_PX = 6 * LINE_PX + COMPOSER_CHROME_PX;
const CONVERSATION_SHARE = 0.5;
const MESSAGE_SHARE = 0.8;
const CONTRAST_TARGET = 4.5;

function channel(value: number): number {
  const scaled = value / 255;
  return scaled <= 0.03928 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4;
}

/** The WCAG contrast ratio of two colours in the `rgb(r, g, b)` form the browser reports. */
function contrastOf(first: string, second: string): number {
  const luminance = (rgb: string): number => {
    const parts = /rgba?\((\d+),\s*(\d+),\s*(\d+)/u.exec(rgb);
    if (!parts) throw new Error(`not an rgb colour: ${rgb}`);
    const [red = 0, green = 0, blue = 0] = [parts[1], parts[2], parts[3]].map(
      Number,
    );
    return (
      0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    );
  };
  const [light, dark] = [luminance(first), luminance(second)].toSorted(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

function viewportOf(page: Page): { width: number; height: number } {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  return viewport;
}

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

async function expectOnScreen(
  page: Page,
  locator: Locator,
  label: string,
): Promise<void> {
  await expect(locator, `${label} is rendered`).toBeVisible();
  const box = await boxOf(locator, label);
  const viewport = viewportOf(page);
  expect(box.y, `${label} top edge`).toBeGreaterThanOrEqual(0);
  expect(box.y + box.height, `${label} bottom edge`).toBeLessThanOrEqual(
    viewport.height + 1,
  );
}

Then(
  "the conversation list is at least half the viewport height",
  async ({ page }) => {
    const history = page.locator('[data-role="family-chat-history"]');
    const box = await boxOf(history, "the conversation list");
    const viewport = viewportOf(page);
    expect(box.height, "the conversation list height").toBeGreaterThanOrEqual(
      CONVERSATION_SHARE * viewport.height,
    );
    await expectOnScreen(
      page,
      page.locator('[data-role="family-chat-composer"]'),
      "the composer",
    );
  },
);

Then("the message composer is on screen", async ({ page }) => {
  await expectOnScreen(
    page,
    page.locator('[data-role="family-chat-composer"]'),
    "the composer",
  );
  await expectOnScreen(page, composerInput(page), "the message input");
});

Then(
  "the message takes at least 80 percent of the viewport width",
  async ({ page }) => {
    const message = page.locator('[data-role="family-chat-message"]').last();
    await expect(message).toBeVisible();
    const box = await boxOf(message, "the message");
    const viewport = viewportOf(page);
    expect(
      box.width / viewport.width,
      "the message share of the viewport",
    ).toBeGreaterThanOrEqual(MESSAGE_SHARE);
  },
);

When(
  "the visitor types a draft of {int} lines into the composer",
  async ({ page }, count: number) => {
    const input = composerInput(page);
    await expect(input).toBeEnabled();
    // Playwright's fill sets the value and fires the input event the composer listens to.
    await input.fill(
      Array.from(
        { length: count },
        (_unused, index) => `line ${index + 1}`,
      ).join("\n"),
    );
  },
);

Then("the message composer is at least two lines tall", async ({ page }) => {
  const box = await boxOf(composerInput(page), "the message input");
  expect(box.height, "the composer height").toBeGreaterThanOrEqual(
    2 * LINE_PX + COMPOSER_CHROME_PX - 1,
  );
});

Then(
  "the message composer is at most 22 percent of the screen height",
  async ({ page }) => {
    // A short window keeps most of its height for the conversation, so the box stops at a share of the window.
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const box = await boxOf(composerInput(page), "the message input");
    expect(
      box.height,
      `the composer is ${box.height} px of a ${viewport.height} px screen`,
    ).toBeLessThanOrEqual(0.22 * viewport.height + 1);
  },
);

Then("the message composer is at most six lines tall", async ({ page }) => {
  const box = await boxOf(composerInput(page), "the message input");
  expect(box.height, "the composer height").toBeLessThanOrEqual(
    SIX_LINES_PX + 1,
  );
  // Past the cap the draft scrolls inside the composer rather than pushing the Send button off screen.
  const overflow = await composerInput(page).evaluate(
    (element) => getComputedStyle(element).overflowY,
  );
  expect(overflow, "the composer scrolls past its cap").toBe("auto");
});

Then("the Send button is on screen", async ({ page }) => {
  await expectOnScreen(
    page,
    page.locator('[data-role="family-chat-send"]'),
    "the Send button",
  );
});

Then(
  "the Send button text has a contrast ratio of at least 4.5 to 1",
  async ({ page }) => {
    const style = await page
      .locator('[data-role="family-chat-send"]')
      .evaluate((element) => {
        const computed = getComputedStyle(element);
        return { text: computed.color, background: computed.backgroundColor };
      });
    const ratio = contrastOf(style.text, style.background);
    expect(
      ratio,
      `${style.text} on ${style.background}`,
    ).toBeGreaterThanOrEqual(CONTRAST_TARGET);
  },
);
