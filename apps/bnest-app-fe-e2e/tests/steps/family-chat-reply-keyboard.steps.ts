import { expect, type Page } from "@playwright/test";
import { composerInput } from "../support/family-chat";
import { createBdd } from "playwright-bdd";
import { waitForRoomReady } from "../support/family-chat-resume";
import { ensureAtLeast } from "../support/family-chat-seeding";
import {
  expectMenuOpenFor,
  focusedMessageId,
  MESSAGE,
  messageById,
  postMessage,
  QUOTE,
  renderedMessageIds,
  scenario,
  tabbableMessageCount,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import {
  ensureRoomOpen,
  seedOtherMemberMessage,
} from "../support/family-chat-reply-room";

// The keyboard half of family_chat.feature's reply rules: the end-to-end
// journey without a pointer, the history's single tab stop, and the quote's
// computed accessible name (the compatibility revision is in
// `family-chat-rollback-floor.steps.ts`). Split from
// `family-chat-reply-reading.steps.ts` purely to stay under this project's
// max-lines lint budget.

const { Given, Then, When } = createBdd();

// --- The keyboard journey -------------------------------------------------

/** Why the focused element cannot be operated, or null when it can. */
function inoperableFocus(page: Page): Promise<string | null> {
  return page.evaluate(() => {
    const active = document.activeElement as HTMLElement | null;
    if (!active) return "no active element";
    if (active.getAttribute("aria-disabled") === "true") return "aria";
    if ((active as HTMLButtonElement).disabled) return "disabled";
    if (active.hidden || active.closest("[hidden]")) return "hidden";
    return null;
  });
}

/** Presses `key` until `reached` holds, checking focus after every press. */
async function pressUntil(
  page: Page,
  key: string,
  reached: () => Promise<boolean>,
  limit: number,
): Promise<void> {
  for (let presses = 0; presses < limit; presses += 1) {
    // eslint-disable-next-line no-await-in-loop -- each press is judged before the next.
    if (await reached()) return;
    // eslint-disable-next-line no-await-in-loop -- same.
    await page.keyboard.press(key);
    // eslint-disable-next-line no-await-in-loop -- same.
    expect(await inoperableFocus(page), `after ${key}`).toBeNull();
  }
  expect(await reached(), `${key} never got there`).toBe(true);
}

Given(
  "a visitor opens {string} using only a keyboard",
  async ({ page, $testInfo }, _route: string) => {
    await ensureRoomOpen(page, $testInfo);
    await ensureAtLeast(page, 3);
    scenario.targetBody = uniqueBody("Keyboard target");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);
  },
);

When(
  "the visitor moves focus into the history, selects a message, opens the menu, chooses {string}, types, and sends",
  async ({ page }, label: string) => {
    // From the top of the page, Tab until the history's single stop.
    await pressUntil(
      page,
      "Tab",
      async () => (await focusedMessageId(page)) !== null,
      40,
    );
    await page.keyboard.press("End");
    await pressUntil(
      page,
      "ArrowUp",
      async () => (await focusedMessageId(page)) === scenario.targetId,
      60,
    );
    await page.keyboard.press("Enter");
    await expectMenuOpenFor(page, scenario.targetId);
    expect(await inoperableFocus(page)).toBeNull();
    await pressUntil(
      page,
      "Tab",
      () =>
        page.evaluate(
          (text) => document.activeElement?.textContent?.trim() === text,
          label,
        ),
      5,
    );
    await page.keyboard.press("Enter");
    await expect(composerInput(page)).toBeFocused();
    scenario.replyBody = uniqueBody("Keyboard reply");
    await page.keyboard.type(scenario.replyBody);
    await page.keyboard.press("Enter");
    expect(await inoperableFocus(page)).toBeNull();
  },
);

Then(
  "the sent message renders a quote of the selected message",
  async ({ page }) => {
    const sent = page.locator(MESSAGE).filter({ hasText: scenario.replyBody });
    await expect(sent.locator(QUOTE)).toBeVisible({ timeout: 15_000 });
    await expect(sent.locator(QUOTE)).toContainText(
      scenario.targetBody.slice(0, 40),
    );
  },
);

Then(
  "focus is never left on a control the visitor cannot operate",
  async ({ page }) => {
    expect(await inoperableFocus(page)).toBeNull();
  },
);

// --- The history's single tab stop ---------------------------------------

Given(
  "the history holds {int} messages",
  async ({ page, $testInfo }, count: number) => {
    await ensureRoomOpen(page, $testInfo);
    await ensureAtLeast(page, count);
    await expect
      .poll(() => page.locator(MESSAGE).count(), { timeout: 20_000 })
      .toBeGreaterThanOrEqual(count);
  },
);

When(
  "the visitor presses Tab from the control before the history",
  async ({ page }) => {
    await page.locator('[data-role="family-chat-load-older"]').focus();
    await page.keyboard.press("Tab");
  },
);

Then("focus enters the history exactly once", async ({ page }) => {
  // Measured two ways, because either alone can be green while the room is
  // unusable: the DOM offers exactly one stop, and tabbing forward from
  // inside the history leaves it rather than walking to the next message.
  expect(await tabbableMessageCount(page)).toBe(1);
  expect(await focusedMessageId(page)).not.toBeNull();

  await page.keyboard.press("Tab");
  expect(await focusedMessageId(page)).toBeNull();
});

Then("the arrow keys move between messages", async ({ page }) => {
  const ids = await renderedMessageIds(page);
  const newest = ids.at(-1) ?? "";
  await messageById(page, newest).focus();

  await page.keyboard.press("ArrowUp");
  await expect.poll(() => focusedMessageId(page)).toBe(ids.at(-2));
  expect(await tabbableMessageCount(page)).toBe(1);

  await page.keyboard.press("ArrowDown");
  await expect.poll(() => focusedMessageId(page)).toBe(newest);
  expect(await tabbableMessageCount(page)).toBe(1);
});

// --- The quote's accessible name -----------------------------------------

Given(
  "a reply quoting a message from {string} is rendered",
  async ({ page, browser, $testInfo }, _sender: string) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Named original");
    scenario.targetId = await seedOtherMemberMessage(
      page,
      browser,
      scenario.targetBody,
    );
    scenario.replyBody = uniqueBody("Named reply");
    scenario.replyId = await postMessage(
      page,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    scenario.targetSender =
      (await messageById(page, scenario.targetId)
        .locator('[data-role="family-chat-message-sender"]')
        .textContent()) ?? "";
  },
);

When("assistive technology reads that reply", async ({ page }) => {
  await expect(
    messageById(page, scenario.replyId).locator(QUOTE),
  ).toBeVisible();
});

Then(
  "the quote exposes an accessible name naming {string}",
  async ({ page }, _sender: string) => {
    // The browser's own computed accessible name, not the attribute source
    // -- computing it is the whole reason this scenario needs a real
    // accessibility tree rather than the unit layer's markup assertion.
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toHaveAccessibleName(
      `Reply to ${scenario.targetSender}: ${scenario.targetBody}. Go to that message.`,
    );
  },
);

Then("the quote is exposed as an activatable control", async ({ page }) => {
  await expect(messageById(page, scenario.replyId).locator(QUOTE)).toHaveRole(
    "button",
  );
});
