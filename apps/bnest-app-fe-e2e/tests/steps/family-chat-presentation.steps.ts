import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { openFamilyChatRoom, ROOM_ROUTE } from "../support/family-chat";
import {
  expectCommitted,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { expectServiceWorkerControl } from "../support/family-chat-outbox-store";
import { uniqueBody } from "../support/family-chat-reply";

// family_chat.feature's "offline opening" and "Responsive and accessible
// presentation" scenarios: what the service worker answers when the room is
// opened offline, and the room's real focus order and focus indicators at
// each viewport.

const { Given, Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A table or code block that fits is not a tab stop
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A wide table, code block or diagram can be scrolled from the keyboard
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Escape returns focus from message content to the message
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Every control in the room is reachable by keyboard with a visible focus indicator
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Opening the room offline shows no signed-in messages from the device's saved copy
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Tab and Shift+Tab pass through message content without a trap
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room does not scroll the whole page vertically
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The room has no horizontal page scroll

const MAX_TAB_STOPS = 60;

let probeBody = "";

Then("the send shortcut hint takes a row", async ({ page }) => {
  // A fine pointer's hint keeps its row: it is laid out in the flow with a visible box, not a one-pixel box.
  const hint = page.locator(".family-chat-composer-hint").first();
  await expect(hint).toBeVisible();
  const box = await hint.boundingBox();
  expect(
    box !== null && box.height > 1,
    `the hint is ${JSON.stringify(box)}`,
  ).toBe(true);
});

Given("a visitor has exchanged messages", async ({ page }) => {
  await openFamilyChatRoom(page);
  expect(new URL(page.url()).pathname).toBe(ROOM_ROUTE);
  probeBody = uniqueBody("Cache inspection probe");
  await sendThroughComposer(page, probeBody);
  // Exchanged: the server committed it and the room shows it.
  await expectCommitted(page, probeBody);
});

When("the visitor opens the room while offline", async ({ page }) => {
  // Reopening offline only reaches the worker if it already controls the page.
  await expectServiceWorkerControl(page);
  await page.context().setOffline(true);
  await page.goto(ROOM_ROUTE);
});

Then(
  "the page shows no messages and no signed-in content",
  async ({ page }) => {
    // The worker's offline page: no room, no message, and no signed-in markup.
    await expect(page.getByText("You are offline.")).toBeVisible();
    await expect(page.locator('[data-role="family-chat-message"]')).toHaveCount(
      0,
    );
    await expect(page.getByText(probeBody)).toHaveCount(0);
    await expect(page.locator("[data-current-user-id]")).toHaveCount(0);
  },
);

Given("the viewport is set to {string}", async ({ page }, viewport: string) => {
  const size = parseViewport(viewport);
  await page.setViewportSize(size);
});

// The Responsive Outline's "When a visitor opens {string}" step reuses the
// generic binding in browser.steps.ts.

interface TabStop {
  key: string;
  inRoom: boolean;
  role: string;
  visible: boolean;
  indicated: boolean;
}

/** What the browser says about the element keyboard focus is on now. */
function currentStop(page: Page): Promise<TabStop | null> {
  return page.evaluate(() => {
    const active = document.activeElement as HTMLElement | null;
    if (!active || active === document.body) return null;
    const style = getComputedStyle(active);
    const box = active.getBoundingClientRect();
    const outlined =
      style.outlineStyle !== "none" && style.outlineWidth !== "0px";
    return {
      // Where the element sits in the document: two icon buttons share a
      // tag and an empty text, but never a position.
      key: `${active.tagName}#${[...document.querySelectorAll("*")].indexOf(active)}`,
      inRoom: active.closest('[data-role="family-chat-room"]') !== null,
      role: active.dataset["role"] ?? active.tagName.toLowerCase(),
      visible: box.width > 0 && box.height > 0 && style.visibility !== "hidden",
      indicated: outlined || style.boxShadow !== "none",
    };
  });
}

/**
 * Every control in the room that is in the tab order: visible, enabled, and
 * not taken out of it with a negative tabindex (the history's messages share
 * one roving stop, and their per-message controls open from the menu).
 */
function roomTabOrder(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const room = document.querySelector('[data-role="family-chat-room"]');
    if (!room) throw new Error("the room is not rendered");
    const all = [...document.querySelectorAll("*")];
    return [
      ...room.querySelectorAll<HTMLElement>(
        "a[href], button, input, select, textarea, [tabindex]",
      ),
    ]
      .filter((element) => {
        const box = element.getBoundingClientRect();
        return (
          element.tabIndex >= 0 &&
          !(element as HTMLButtonElement).disabled &&
          box.width > 0 &&
          box.height > 0 &&
          getComputedStyle(element).visibility !== "hidden"
        );
      })
      .map((element) => `${element.tagName}#${all.indexOf(element)}`);
  });
}

/** Tabs from the top of the page until focus comes round again. */
async function tabThroughPage(page: Page): Promise<TabStop[]> {
  const stops: TabStop[] = [];
  for (let presses = 0; presses < MAX_TAB_STOPS; presses += 1) {
    // eslint-disable-next-line no-await-in-loop -- each stop is read where the previous press left focus.
    await page.keyboard.press("Tab");
    // eslint-disable-next-line no-await-in-loop -- same.
    const stop = await currentStop(page);
    if (stop === null || stops.some((seen) => seen.key === stop.key)) break;
    stops.push(stop);
  }
  return stops;
}

Then(
  "every control is reachable by keyboard with a visible focus indicator",
  async ({ page }) => {
    // The composer starts disabled until the room has loaded; a disabled
    // control is not in the tab order at all.
    await expect(
      page.locator('[data-role="family-chat-room"]'),
    ).toHaveAttribute("data-connection-state", "ready", { timeout: 10_000 });
    const controls = await roomTabOrder(page);
    const walked = await tabThroughPage(page);
    const stops = walked.filter((stop) => stop.inRoom);
    const roles = stops.map((stop) => stop.role);
    // A positive control: the composer is among what Tab reached, so an
    // empty walk cannot pass the comparison below.
    for (const required of ["family-chat-message-input", "family-chat-send"]) {
      expect(roles, `reached ${JSON.stringify(walked)}`).toContain(required);
    }
    const reached = new Set(stops.map((stop) => stop.key));
    const missed = controls.filter((control) => !reached.has(control));
    expect(missed, `not reached by Tab: ${JSON.stringify(missed)}`).toEqual([]);
    const unmarked = stops.filter((stop) => !stop.visible || !stop.indicated);
    expect(unmarked, JSON.stringify(unmarked)).toEqual([]);
  },
);

Then("no vertical page scroll is present", async ({ page }) => {
  const [scrollHeight, clientHeight] = await page.evaluate(() => [
    document.documentElement.scrollHeight,
    document.documentElement.clientHeight,
  ]);
  expect(
    scrollHeight,
    "the page is taller than the screen",
  ).toBeLessThanOrEqual(clientHeight);
});

Then("no horizontal page scroll is present", async ({ page }) => {
  const [scrollWidth, clientWidth] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scrollWidth).toBeLessThanOrEqual(clientWidth);
});

function parseViewport(spec: string): { width: number; height: number } {
  const match = /^(\w+) (\d+)x(\d+)(?: (\d+)%)?$/u.exec(spec);
  if (!match) throw new Error(`unrecognized viewport spec: ${spec}`);
  const [, , widthText, heightText, zoomText] = match;
  const width = Number(widthText);
  const height = Number(heightText);
  const zoom = zoomText ? Number(zoomText) / 100 : 1;
  return { width: Math.round(width / zoom), height: Math.round(height / zoom) };
}
