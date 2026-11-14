import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { BODY, HISTORY, MESSAGE } from "../support/family-chat-keyboard";
import { MENU } from "../support/family-chat-reply";
import { ensureAtLeast } from "../support/family-chat-seeding";
import {
  ensureRoomOpen,
  seedOtherMemberMessage,
} from "../support/family-chat-reply-room";

// The keyboard scroll rows of family_chat.feature (the Rule "Keyboard reach of the message history"). Focus moves
// with the arrow keys, Home and End, and each Then measures the rendered boxes in real Chromium. The Vitest binding
// (apps/bnest-app/assets/test/behaviour/family_chat_keyboard.steps.ts) reads the same positions from the room's
// layout model.

const { Given, Then, When } = createBdd();

// The menu's gap from its message, as menu_anchor.js places it, with the slack a real menu needs for its border.
const MENU_GAP_PX = 16;

// A message taller than the landscape phone's history: a long code block. Its box is capped and scrolls inside itself,
// so the cap is what keeps the message's height at least the window's, and the tall row's own top edge is measured.
const TALL_BODY = [
  "Tall note",
  "",
  "```text",
  ...Array.from({ length: 60 }, (_, index) => `line ${index + 1}`),
  "```",
].join("\n");

// The history's scroll position each scenario noted, per page, so a scenario's own page is the one compared.
const notedPosition = new WeakMap<Page, number>();

async function historyScrollTop(page: Page): Promise<number> {
  const value = await page.evaluate(
    (selector) =>
      document.querySelector<HTMLElement>(selector)?.scrollTop ?? null,
    HISTORY,
  );
  if (value === null) throw new Error("the history is not rendered");
  return value;
}

Given("the history is laid out on the screen", async ({ page }) => {
  // The rows render after the page opens, and the room scrolls to its newest message once they do, so both are polled.
  const read = () =>
    page.evaluate((selector) => {
      const history = document.querySelector<HTMLElement>(selector);
      if (!history) return null;
      return {
        atNewest:
          history.scrollTop + history.clientHeight >= history.scrollHeight - 2,
        overflows: history.scrollHeight > history.clientHeight,
      };
    }, HISTORY);
  await expect
    .poll(async () => (await read())?.overflows ?? false, { timeout: 15_000 })
    .toBe(true);
  await expect
    .poll(async () => (await read())?.atNewest ?? false, { timeout: 15_000 })
    .toBe(true);
});

When(
  "the visitor presses {string} {int} times",
  async ({ page }, key: string, count: number) => {
    for (let press = 0; press < count; press += 1) {
      // eslint-disable-next-line no-await-in-loop -- each press moves focus before the next one is judged.
      await page.keyboard.press(key);
    }
  },
);

Given(
  "the history holds {int} messages and a message taller than the window follows them",
  async ({ browser, page }, count: number) => {
    await ensureRoomOpen(page);
    await ensureAtLeast(page, count);
    await seedOtherMemberMessage(page, browser, TALL_BODY);
    await expect(page.locator(MESSAGE).last().locator("pre")).toBeVisible({
      timeout: 15_000,
    });
    // The scenario is about a message taller than the window. If the code block's cap or the window's size ever makes
    // the newest message shorter than the history, the scenario would prove nothing, so it fails here instead.
    const sizes = await page.evaluate(
      ({ history, message }) => {
        const frame = document.querySelector(history);
        const rows = Array.from(document.querySelectorAll(message));
        const newest = rows.at(-1);
        return {
          history: frame?.getBoundingClientRect().height ?? null,
          tall: newest?.getBoundingClientRect().height ?? null,
        };
      },
      { history: HISTORY, message: MESSAGE },
    );
    expect(sizes.tall, "the newest message is not rendered").not.toBeNull();
    expect(
      sizes.tall ?? 0,
      `the tall message is ${sizes.tall} px, not taller than the ${sizes.history} px history`,
    ).toBeGreaterThan(sizes.history ?? Number.POSITIVE_INFINITY);
  },
);

When("the history's position is noted", async ({ page }) => {
  notedPosition.set(page, await historyScrollTop(page));
});

Then(
  "the history has not moved since its position was noted",
  async ({ page }) => {
    const noted = notedPosition.get(page);
    if (noted === undefined) throw new Error("no position was noted");
    const now = await historyScrollTop(page);
    expect(now, `the history moved from ${noted} to ${now}`).toBe(noted);
  },
);

Then(
  "the top of the focused message is inside the visible history",
  async ({ page }) => {
    // A message taller than the window cannot fit in it, so its top edge is what the reader must see first.
    const boxes = await page.evaluate((selector) => {
      const active = document.activeElement;
      const history = document.querySelector<HTMLElement>(selector);
      if (!(active instanceof HTMLElement) || !history) return null;
      const row = active.getBoundingClientRect();
      const frame = history.getBoundingClientRect();
      return {
        frameBottom: frame.bottom,
        frameTop: frame.top,
        rowTop: row.top,
      };
    }, HISTORY);
    if (boxes === null) throw new Error("no message holds keyboard focus");
    expect(
      boxes.rowTop >= boxes.frameTop - 0.5 && boxes.rowTop < boxes.frameBottom,
      `the focused message's top is ${boxes.rowTop}, outside a history from ${boxes.frameTop} to ${boxes.frameBottom}`,
    ).toBe(true);
  },
);

Then(
  "the focused message is the message with the number {int}",
  async ({ page }, number: number) => {
    const actual = await page.evaluate(
      ({ body, message }) => {
        const active = document.activeElement;
        // The focused element must itself be a message: <body>, or a control inside a message, does not count.
        if (!(active instanceof HTMLElement) || !active.matches(message))
          return null;
        const text = active.querySelector(body)?.textContent ?? "";
        const match = /(\d+)\s*$/u.exec(text.trim());
        return match?.[1] === undefined ? null : Number(match[1]);
      },
      { body: BODY, message: MESSAGE },
    );
    expect(
      actual,
      `the focused message is number ${actual}, not ${number}`,
    ).toBe(number);
  },
);

Then("the focused message is not the newest message", async ({ page }) => {
  // The arrow presses before this step must have moved focus off the newest message.
  const result = await page.evaluate((message) => {
    const rows = [...document.querySelectorAll(message)];
    const active = document.activeElement;
    return {
      count: rows.length,
      focusIsMessage: active !== null && rows.includes(active as HTMLElement),
      focusedIsNewest:
        active !== null && rows.length > 0 && active === rows.at(-1),
    };
  }, MESSAGE);
  expect(
    result.focusIsMessage && !result.focusedIsNewest && result.count > 1,
    `keyboard focus is not on a message other than the newest of ${result.count} messages`,
  ).toBe(true);
});

Then("the focused message is the newest message", async ({ page }) => {
  const result = await page.evaluate((message) => {
    const rows = [...document.querySelectorAll(message)];
    const active = document.activeElement;
    return {
      count: rows.length,
      focusedIsNewest:
        active !== null && rows.length > 0 && active === rows.at(-1),
    };
  }, MESSAGE);
  expect(
    result.focusedIsNewest,
    `keyboard focus is not on the newest of ${result.count} messages`,
  ).toBe(true);
});

Then("the focused message is the tall message", async ({ page }) => {
  const body = await page.evaluate(
    (selector) =>
      document.activeElement?.querySelector(selector)?.textContent ?? "",
    BODY,
  );
  expect(
    body.includes("Tall note"),
    `keyboard focus is not on the tall message, its body is ${JSON.stringify(body)}`,
  ).toBe(true);
});

Then("the focused message is inside the visible history", async ({ page }) => {
  const boxes = await page.evaluate((selector) => {
    const active = document.activeElement;
    const history = document.querySelector<HTMLElement>(selector);
    if (!(active instanceof HTMLElement) || !history) return null;
    const row = active.getBoundingClientRect();
    const frame = history.getBoundingClientRect();
    return {
      frameBottom: frame.bottom,
      frameTop: frame.top,
      rowBottom: row.bottom,
      rowTop: row.top,
    };
  }, HISTORY);
  if (boxes === null) throw new Error("no message holds keyboard focus");
  expect(
    boxes.rowTop >= boxes.frameTop - 0.5 &&
      boxes.rowBottom <= boxes.frameBottom + 0.5,
    `the focused message spans ${boxes.rowTop} to ${boxes.rowBottom} in a history from ${boxes.frameTop} to ${boxes.frameBottom}`,
  ).toBe(true);
});

Then(
  "the message action menu is beside the focused message inside the screen",
  async ({ page }) => {
    // Enter moves focus into the menu, so the message is read as the history's tab stop.
    const boxes = await page.evaluate(
      ({ menu, message }) => {
        const host = document.querySelector<HTMLElement>(menu);
        const stop = document.querySelector<HTMLElement>(
          `${message}[tabindex="0"]`,
        );
        if (!host || !stop) return null;
        const box = host.getBoundingClientRect();
        const row = stop.getBoundingClientRect();
        return {
          menuBottom: box.bottom,
          menuTop: box.top,
          messageBottom: row.bottom,
          messageTop: row.top,
          viewportHeight: window.innerHeight,
        };
      },
      { menu: MENU, message: MESSAGE },
    );
    if (boxes === null) throw new Error("no action menu is open");
    expect(
      boxes.menuTop >= 0 && boxes.menuBottom <= boxes.viewportHeight,
      `the menu spans ${boxes.menuTop} to ${boxes.menuBottom} on a ${boxes.viewportHeight} px screen`,
    ).toBe(true);
    expect(
      boxes.menuTop <= boxes.messageBottom + MENU_GAP_PX &&
        boxes.menuBottom >= boxes.messageTop - MENU_GAP_PX,
      `the menu spans ${boxes.menuTop} to ${boxes.menuBottom}, away from a message that spans ${boxes.messageTop} to ${boxes.messageBottom}`,
    ).toBe(true);
  },
);
