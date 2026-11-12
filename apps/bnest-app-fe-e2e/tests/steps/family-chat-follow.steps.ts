import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { sendThroughComposer } from "../support/family-chat-delivery";
import {
  asAnotherMember,
  postMessage,
  uniqueBody,
} from "../support/family-chat-reply";
import { openFamilyChatRoom } from "../support/family-chat";
import { instanceIdentities } from "../support/instance-identities";
import { emulateTouchPointer } from "../support/touch-pointer";
import {
  holdDiagramEngine,
  MARKED_DIAGRAM,
  DRAWN_FIGURE,
} from "../support/codex-diagrams";

// family_chat.feature's diagram re-stick scenario and the theme control's place in the room header, in Chromium at the
// served origin. The Vitest bindings (family_chat_follow.steps.ts, family_chat_layout.steps.ts) prove the follow contract
// and the declared CSS; these read the rendered boxes.

const { Given, Then } = createBdd();

const HISTORY = '[data-role="family-chat-history"]';
const MESSAGE = '[data-role="family-chat-message"]';
const COMPOSER = ".family-chat-composer";
const HEADER = "header.family-chat-header";
const TITLE = "#family-chat-room-title";
const THEME = `${HEADER} .family-chat-theme`;
const FLOWCHART = "```mermaid\nflowchart TD\n  A --> B\n```";
const ROUNDS_TO_OVERFLOW = 14;
// The engine is held this long, so the marked diagram is still undrawn when the room is measured.
const NOT_YET_DRAWN_MS = 8000;
// The history's size just before the diagram draws, per page: the draw must make it taller. It is keyed by page and
// held in a WeakMap, not in module state, so a failed scenario leaves no baseline for the next one.
const beforeDrawByPage = new WeakMap<Page, { scrollHeight: number }>();

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

function overlaps(
  first: { x: number; y: number; width: number; height: number },
  second: { x: number; y: number; width: number; height: number },
): boolean {
  return (
    first.x < second.x + second.width &&
    second.x < first.x + first.width &&
    first.y < second.y + second.height &&
    second.y < first.y + first.height
  );
}

/** The history's full height, and the distance the reader is above its newest content. */
function sizeOf(page: Page) {
  return page.locator(HISTORY).evaluate((element) => ({
    scrollHeight: element.scrollHeight,
    gap: element.scrollHeight - element.scrollTop - element.clientHeight,
  }));
}

/**
 * Whether the newest message's bottom edge sits above the composer, inside the visible history. Returns `true` when it
 * does, and otherwise what the page showed. This runs inside `expect.poll`, which retries a returned value but not a
 * thrown one, so a box that is missing for a moment (the room re-renders) is "not settled yet", not a failure.
 */
async function newestAboveComposer(page: Page): Promise<true | string> {
  if ((await page.locator(MESSAGE).count()) === 0) {
    return "the room has no message yet";
  }
  const [message, composer, history] = await Promise.all([
    page.locator(MESSAGE).last().boundingBox(),
    page.locator(COMPOSER).boundingBox(),
    page.locator(HISTORY).boundingBox(),
  ]);
  if (message === null) return "the newest message has no box yet";
  if (composer === null) return "the composer has no box yet";
  if (history === null) return "the history has no box yet";
  if (message.y + message.height > composer.y + 1) {
    return "the newest message's bottom edge is below the composer";
  }
  if (message.y + message.height <= history.y) {
    return "the newest message is above the visible history";
  }
  return true;
}

/** The newest message's bottom edge sits above the composer, inside the visible history, once the page settles. */
async function expectNewestAboveComposer(page: Page): Promise<void> {
  await expect
    .poll(() => newestAboveComposer(page), {
      message: "the newest message is above the composer",
      timeout: 10_000,
    })
    .toBe(true);
}

Given(
  "a visitor is at the bottom of the family chat conversation",
  async ({ page }) => {
    await holdDiagramEngine(page.context(), NOT_YET_DRAWN_MS);
    await openFamilyChatRoom(page);
    // Each message is committed before the next is sent, so the room receives them in order.
    await Array.from(
      { length: ROUNDS_TO_OVERFLOW },
      (_, round) => round,
    ).reduce(async (previous, round) => {
      await previous;
      await sendThroughComposer(page, uniqueBody(`Follow probe ${round}`));
    }, Promise.resolve());
    await page.locator(HISTORY).evaluate((element) => {
      element.scrollTop = element.scrollHeight;
    });
    await expectNewestAboveComposer(page);
    const overflow = await page
      .locator(HISTORY)
      .evaluate((element) => element.scrollHeight - element.clientHeight);
    expect(
      overflow,
      "the history does not overflow, so the reader cannot be at its bottom",
    ).toBeGreaterThan(0);
  },
);

Given(
  "{word} has sent a family chat message with a mermaid flowchart that is not yet drawn",
  async ({ browser, page }, _sender: string) => {
    await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, FLOWCHART),
    );
    // The message arrives live. Its diagram is marked and not yet drawn, and the reader is measured in that state.
    const newest = page.locator(MESSAGE).last();
    await expect(newest.locator(MARKED_DIAGRAM)).toHaveCount(1, {
      timeout: 15_000,
    });
    await expect(newest.locator(DRAWN_FIGURE)).toHaveCount(0);
    await expectNewestAboveComposer(page);
    beforeDrawByPage.set(page, await sizeOf(page));
  },
);

Then("the newest message is in view above the composer", async ({ page }) => {
  // After a diagram draws, the draw must have grown the history (the picture is taller than the source it replaced).
  // Other steps, such as a draft that shrinks the history, only need the newest message above the composer.
  const before = beforeDrawByPage.get(page);
  if (before !== undefined) {
    await expect
      .poll(async () => (await sizeOf(page)).scrollHeight, {
        message: "the draw did not grow the history",
        timeout: 15_000,
      })
      .toBeGreaterThan(before.scrollHeight);
    beforeDrawByPage.delete(page);
  }
  await expectNewestAboveComposer(page);
});

Then("the theme control is inside the room header", async ({ page }) => {
  await expect(page.locator(THEME)).toHaveCount(1);
  await expect(page.locator(".theme-dock")).toBeHidden();
  const [header, control] = await Promise.all([
    boxOf(page.locator(HEADER), "The room header"),
    boxOf(page.locator(THEME), "The theme control"),
  ]);
  expect(control.x).toBeGreaterThanOrEqual(header.x);
  expect(control.x + control.width).toBeLessThanOrEqual(
    header.x + header.width + 0.5,
  );
  expect(control.y).toBeGreaterThanOrEqual(header.y);
  expect(control.y + control.height).toBeLessThanOrEqual(
    header.y + header.height + 0.5,
  );
});

Then("the theme control does not cover the room title", async ({ page }) => {
  const [title, control] = await Promise.all([
    boxOf(page.locator(TITLE), "The room title"),
    boxOf(page.locator(THEME), "The theme control"),
  ]);
  expect(
    overlaps(title, control),
    "the theme control covers the room title",
  ).toBe(false);
  const viewport = page.viewportSize();
  expect(control.x + control.width).toBeLessThanOrEqual(
    (viewport?.width ?? 0) + 0.5,
  );
});

Then(
  "the theme control is at least 44 pixels across on a touch screen",
  async ({ page }) => {
    await emulateTouchPointer(page);
    const control = await boxOf(page.locator(THEME), "The theme control");
    expect(control.width).toBeGreaterThanOrEqual(44);
    const buttons = page.locator(`${THEME} button`);
    await expect(buttons).toHaveCount(3);
    const heights = await Promise.all(
      [0, 1, 2].map(
        async (index) =>
          (await boxOf(buttons.nth(index), `Theme button ${index}`)).height,
      ),
    );
    for (const height of heights) expect(height).toBeGreaterThanOrEqual(44);
  },
);

Then(
  "each theme button is at least 44 pixels across on a touch screen",
  async ({ page }) => {
    // Each of the three theme buttons is a touch target of its own; the control's width is checked by the step above.
    await emulateTouchPointer(page);
    const buttons = page.locator(`${THEME} button`);
    await expect(buttons).toHaveCount(3);
    const boxes = await Promise.all(
      [0, 1, 2].map((index) =>
        boxOf(buttons.nth(index), `Theme button ${index}`),
      ),
    );
    for (const [index, box] of boxes.entries()) {
      expect(box.width, `Theme button ${index} width`).toBeGreaterThanOrEqual(
        44,
      );
    }
  },
);
