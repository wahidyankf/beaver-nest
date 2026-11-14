import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { sendThroughComposer } from "../support/family-chat-delivery";
import {
  asAnotherMember,
  postMessage,
  uniqueBody,
} from "../support/family-chat-reply";
import { openFamilyChatRoom } from "../support/family-chat";
import { instanceIdentities } from "../support/instance-identities";
import {
  holdDiagramEngine,
  MARKED_DIAGRAM,
  DRAWN_FIGURE,
} from "../support/codex-diagrams";

// family_chat.feature's diagram re-stick scenario and the room header's place, in Chromium at the
// served origin. The Vitest bindings (family_chat_follow.steps.ts, family_chat_layout.steps.ts) prove the follow contract
// and the declared CSS; these read the rendered boxes.

const { Given, Then } = createBdd();

const HISTORY = '[data-role="family-chat-history"]';
const MESSAGE = '[data-role="family-chat-message"]';
const COMPOSER = ".family-chat-composer";
const FLOWCHART = "```mermaid\nflowchart TD\n  A --> B\n```";
const ROUNDS_TO_OVERFLOW = 14;
// The engine is held this long, so the marked diagram is still undrawn when the room is measured.
const NOT_YET_DRAWN_MS = 8000;
// The history's size just before the diagram draws, per page: the draw must make it taller. It is keyed by page and
// held in a WeakMap, not in module state, so a failed scenario leaves no baseline for the next one.
const beforeDrawByPage = new WeakMap<Page, { scrollHeight: number }>();

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
