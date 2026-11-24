import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  boxOf,
  EDGE_TOLERANCE_PX,
  saveScrolledRoom,
  screenOf,
} from "../support/sticky-room";

const { Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A smaller screen from the soft keyboard keeps the Family Chat header, composer and newest message on screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat header and composer stay in place while the messages scroll
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat header and composer stay in place with a fine pointer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The Family Chat message list keeps its overscroll inside itself
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The last Family Chat message is not hidden behind the composer

// --- Family Chat (family_chat.feature, Rule "Family Chat header and composer stay in place while the messages scroll") ---

const FAMILY_HISTORY = '[data-role="family-chat-history"]';
const FAMILY_HEADER = ".family-chat-header";
const FAMILY_COMPOSER = "form.family-chat-composer";
const FAMILY_SEND = '[data-role="family-chat-send"]';
const FAMILY_NEWEST = '[data-role="family-chat-message"]';

Then(
  "the Family Chat message list keeps its overscroll inside itself",
  async ({ page }) => {
    const overscroll = await page
      .locator(FAMILY_HISTORY)
      .evaluate((element) => getComputedStyle(element).overscrollBehaviorY);
    expect(overscroll, "the Family Chat message list's overscroll").toBe(
      "contain",
    );
  },
);

When(
  "the visitor scrolls the family conversation to the middle",
  async ({ page, $testInfo }) => {
    const history = page.locator(FAMILY_HISTORY);
    const overflows = await history.evaluate(
      (element) => element.scrollHeight > element.clientHeight,
    );
    if (!overflows) throw new Error("the history does not overflow its box");
    await history.evaluate((element) => {
      element.scrollTop = Math.floor(
        (element.scrollHeight - element.clientHeight) / 2,
      );
    });
    await expect
      .poll(() => history.evaluate((element) => element.scrollTop))
      .toBeGreaterThan(0);
    await saveScrolledRoom(page, $testInfo, "family", {
      scroller: FAMILY_HISTORY,
      header: FAMILY_HEADER,
      composer: FAMILY_COMPOSER,
    });
  },
);

Then("the Family Chat header is at the top of the screen", async ({ page }) => {
  const header = await boxOf(page, FAMILY_HEADER);
  expect(header.y, "header top").toBeLessThanOrEqual(EDGE_TOLERANCE_PX);
  expect(header.y, "header top on screen").toBeGreaterThanOrEqual(0);
});

Then(
  "the Family Chat composer is at the bottom of the screen",
  async ({ page }) => {
    const composer = await boxOf(page, FAMILY_COMPOSER);
    const { height } = screenOf(page);
    const bottom = composer.y + composer.height;
    expect(bottom, "composer bottom on screen").toBeLessThanOrEqual(height);
    expect(height - bottom, "gap below the composer").toBeLessThanOrEqual(
      EDGE_TOLERANCE_PX,
    );
  },
);

Then(
  "the newest Family Chat message ends above the composer",
  async ({ page }) => {
    const newest = await boxOf(page, FAMILY_NEWEST);
    const composer = await boxOf(page, FAMILY_COMPOSER);
    expect(
      newest.y + newest.height,
      "newest message bottom",
    ).toBeLessThanOrEqual(composer.y);
  },
);

Then(
  "the Family Chat Send button and header are on screen",
  async ({ page }) => {
    const { height } = screenOf(page);
    const send = await boxOf(page, FAMILY_SEND);
    const header = await boxOf(page, FAMILY_HEADER);
    expect(send.y + send.height, "Send bottom").toBeLessThanOrEqual(height);
    expect(header.y, "header top").toBeGreaterThanOrEqual(0);
  },
);
