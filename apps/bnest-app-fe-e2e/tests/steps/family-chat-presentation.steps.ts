import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  inspectCacheStorageEntries,
  openFamilyChatRoom,
} from "../support/family-chat";
import {
  expectCommitted,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { uniqueBody } from "../support/family-chat-reply";

// family_chat.feature's "no authenticated caching" and "Responsive and
// accessible presentation" scenarios: what the service worker really holds
// in Cache Storage, and the room's real focus order and focus indicators at
// each viewport.

const { Given, Then, When } = createBdd();

// The worker's install-time shell (`priv/static/service-worker.js`
// `APP_SHELL`) beyond `/assets/` and `/images/`: one static, unauthenticated
// file. No page path belongs here -- the shell no longer precaches `/`.
const PRECACHED_STATIC_ENTRIES = new Set(["/manifest.webmanifest"]);
const MAX_TAB_STOPS = 60;

let cacheEntries: string[] = [];

Given(
  "a visitor opens {string} and exchanges messages",
  async ({ page, $testInfo }, route: string) => {
    await openFamilyChatRoom(page, $testInfo);
    expect(new URL(page.url()).pathname).toBe(route);
    const body = uniqueBody("Cache inspection probe");
    await sendThroughComposer(page, body);
    // Exchanged: the server committed it and the room shows it.
    await expectCommitted(page, body);
  },
);

When("the service worker's Cache Storage is inspected", async ({ page }) => {
  cacheEntries = await inspectCacheStorageEntries(page);
});

Then("it contains only static build assets", () => {
  const nonStatic = cacheEntries.filter(
    (entry) =>
      !entry.startsWith("/assets/") &&
      !entry.startsWith("/images/") &&
      !PRECACHED_STATIC_ENTRIES.has(entry),
  );
  expect(nonStatic, JSON.stringify(nonStatic)).toEqual([]);
});

Then("it contains no navigation response, message, or GraphQL response", () => {
  const forbidden = cacheEntries.filter(
    (entry) =>
      entry === "/" ||
      entry.includes("family-chat") ||
      entry.includes("/api/graphql") ||
      entry.includes("/login"),
  );
  expect(forbidden, JSON.stringify(forbidden)).toEqual([]);
});

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
