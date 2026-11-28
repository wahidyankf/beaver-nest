import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { messageById } from "../support/family-chat-gestures";
import { scenario } from "../support/family-chat-reply";

// family_chat.feature's "The actions control is visible and large enough to press" and the press that clears a native
// selection. Boxes and computed styles are read in Chromium at the served origin, at every viewport the Outline names.

const { Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The actions control is visible, large enough to press, beside its bubble and inside the history

const MORE = '[data-role="family-chat-message-more"]';
// The bubble is marked by its class alone; it carries no data-role.
const BUBBLE = ".family-chat-message-bubble";
const BODY = '[data-role="family-chat-message-body"]';
const HISTORY = '[data-role="family-chat-history"]';

interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

async function boxOf(page: Page, selector: string): Promise<Box> {
  const element = messageById(page, scenario.targetId)
    .locator(selector)
    .first();
  // A selector that matches nothing fails here with its name, not at the test timeout.
  await element.waitFor({ state: "attached", timeout: 5000 });
  const box = await element.boundingBox();
  if (!box) throw new Error(`no box for ${selector}`);
  return box;
}

async function historyBox(page: Page): Promise<Box> {
  const box = await page.locator(HISTORY).boundingBox();
  if (!box) throw new Error("no box for the history");
  return box;
}

function overlaps(a: Box, b: Box): boolean {
  return (
    a.x < b.x + b.width &&
    a.x + a.width > b.x &&
    a.y < b.y + b.height &&
    a.y + a.height > b.y
  );
}

Then(
  "the actions control of that message is visible without a hover",
  async ({ page }) => {
    // Read before the pointer is moved over the room: a hover cannot be what makes the control show.
    const more = messageById(page, scenario.targetId).locator(MORE).first();
    await expect(more).toBeVisible();
    const opacity = await more.evaluate((element) =>
      Number(getComputedStyle(element).opacity),
    );
    expect(opacity, "opacity of the actions control at rest").toBe(1);
  },
);

Then(
  "the actions control of that message is at least 44 by 44 CSS pixels",
  async ({ page }) => {
    const box = await boxOf(page, MORE);
    expect(box.width, "actions control width").toBeGreaterThanOrEqual(44);
    expect(box.height, "actions control height").toBeGreaterThanOrEqual(44);
  },
);

Then(
  "the actions control of that message does not overlap its bubble",
  async ({ page }) => {
    const more = await boxOf(page, MORE);
    const bubble = await boxOf(page, BUBBLE);
    expect(overlaps(more, bubble), "actions control over its bubble").toBe(
      false,
    );
  },
);

Then(
  "the actions control of that message is inside the history",
  async ({ page }) => {
    const more = await boxOf(page, MORE);
    const history = await historyBox(page);
    expect(more.x, "left edge").toBeGreaterThanOrEqual(history.x);
    expect(more.x + more.width, "right edge").toBeLessThanOrEqual(
      history.x + history.width,
    );
    expect(more.y, "top edge").toBeGreaterThanOrEqual(history.y);
    expect(more.y + more.height, "bottom edge").toBeLessThanOrEqual(
      history.y + history.height,
    );
  },
);

Then(
  "the actions control of that message has an accessible name",
  async ({ page }) => {
    await expect(
      messageById(page, scenario.targetId).locator(MORE).first(),
    ).toHaveAttribute("aria-label", /^Actions for .+'s message$/u);
  },
);

// A long press in a browser selects text under the pointer while the button stays down. The press below makes that
// selection the same way, with the pointer still held, so the menu's clearing is what the Then step judges.
When(
  "the visitor presses and holds for {int} milliseconds on that message while the browser selects its text",
  async ({ page }, holdMs: number) => {
    const message = messageById(page, scenario.targetId);
    await message.scrollIntoViewIfNeeded();
    const box = await message.boundingBox();
    if (!box) throw new Error("the message has no box to press");
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await message.locator(BODY).evaluate((body) => {
      const range = document.createRange();
      range.selectNodeContents(body);
      const selection = globalThis.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
    });
    await page.evaluate(
      (ms) =>
        new Promise<void>((resolve) => {
          setTimeout(resolve, ms);
        }),
      holdMs + 100,
    );
    await page.mouse.up();
  },
);

Then("no text is selected in the room", async ({ page }) => {
  await expect
    .poll(() =>
      page.evaluate(() => globalThis.getSelection()?.toString() ?? ""),
    )
    .toBe("");
});
