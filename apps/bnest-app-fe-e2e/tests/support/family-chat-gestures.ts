// The gestures family_chat.feature's reply scenarios need from a real
// browser: a held pointer whose event stream the application actually sees,
// and the keyboard route to the same menu.
//
// Split from `family-chat-reply.ts` because that file reached its 300-line
// budget, and because these three are the only helpers here that depend on
// a live layout settling rather than on the room's markup.

import { type Locator, type Page } from "@playwright/test";

export const MESSAGE = "[data-role=family-chat-message]";

export function messageById(page: Page, messageId: string) {
  return page.locator(`${MESSAGE}[data-message-id="${messageId}"]`);
}

/**
 * The press-and-hold gesture, as a real pointer event stream rather than a
 * synthesised one: `mouse.down`, a wait longer than the 500 ms threshold
 * with the pointer genuinely held, then `mouse.up`.
 */
/**
 * The element's box once two consecutive reads agree, so a press is aimed at
 * where the message is rather than where it was.
 */
async function settledBoundingBox(
  locator: Locator,
): Promise<{ height: number; width: number; x: number; y: number }> {
  let previous = await locator.boundingBox();
  for (let attempt = 0; attempt < 40; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop -- each read must follow the one it is compared against.
    await locator.page().waitForTimeout(50);
    // eslint-disable-next-line no-await-in-loop -- same.
    const current = await locator.boundingBox();
    if (
      previous &&
      current &&
      previous.x === current.x &&
      previous.y === current.y &&
      previous.height === current.height
    ) {
      return current;
    }
    previous = current;
  }
  throw new Error("message box never settled");
}

export async function pressAndHold(
  page: Page,
  messageId: string,
  holdMs: number,
): Promise<void> {
  const message = messageById(page, messageId);
  await message.scrollIntoViewIfNeeded();
  // A box read while the room is still settling is a box the press misses:
  // the room scrolls itself on resume, on a newly rendered page, and on an
  // arrival, and a pointer put down on the coordinates a message used to
  // occupy lands on whatever is there now -- which opens no menu at all,
  // and reports as "the menu never opened". Two agreeing reads mean the
  // layout has stopped moving.
  const box = await settledBoundingBox(message);
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(holdMs + 50);
  await page.mouse.up();
}

export async function openMenuWithKeyboard(
  page: Page,
  messageId: string,
): Promise<void> {
  await messageById(page, messageId).focus();
  await page.keyboard.press("Enter");
}
