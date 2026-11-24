import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

import {
  boxOf,
  CANCEL,
  CLEAR,
  CONFIRM,
  HOSTILE_MESSAGE,
  LINES_MESSAGE,
  MARKDOWN_MESSAGE,
  openOptionsIfCollapsed,
  RAW_TEXT,
  settle,
  TOUCH_TARGET_PX,
  USER_MESSAGE,
  viewportOf,
  visitorMessageCount,
  YES,
} from "../support/chat-ui-steps";
import {
  openChatAsAdmin,
  sendAndWaitForReply,
} from "../support/codex-diagrams";

const { Given, Then, When } = createBdd();

// --- Clear chat (chat.feature, Rules "Clear chat asks before it deletes" and its layout rows) ----
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Clear chat asks for confirmation before it deletes the conversation
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Cancel, Escape and tabbing away keep the conversation
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Confirming clears the conversation
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Escape with focus outside the confirmation closes it and leaves focus where it is
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Reopening the options panel shows no stale Clear chat question
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Clear chat confirmation fits a narrow screen with 44 pixel targets
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The confirmation takes focus and cancel returns focus to Clear chat
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor's message renders Markdown and can show its raw text
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The raw view of a hostile visitor's message shows text, not HTML
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The raw view keeps the typed line breaks and spaces

Given(
  "the Codex conversation holds {string}",
  async ({ page }, text: string) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, text);
  },
);

When("the visitor chooses Clear chat", async ({ page }) => {
  await openOptionsIfCollapsed(page);
  await page.locator(CLEAR).click();
});

Given("the visitor has chosen Clear chat", async ({ page }) => {
  await openOptionsIfCollapsed(page);
  await page.locator(CLEAR).click();
});

Then("the confirmation asks {string}", async ({ page }, question: string) => {
  await expect(page.locator(CONFIRM)).toBeVisible();
  await expect(page.locator(CONFIRM)).toContainText(question);
});

Then(
  "the confirmation offers {string} and {string}",
  async ({ page }, yes: string, cancel: string) => {
    await expect(
      page.locator(CONFIRM).getByRole("button", { name: yes, exact: true }),
    ).toBeVisible();
    await expect(
      page.locator(CONFIRM).getByRole("button", { name: cancel, exact: true }),
    ).toBeVisible();
  },
);

Then(
  "the conversation still shows {string}",
  async ({ page }, text: string) => {
    await expect(
      page.locator(USER_MESSAGE).filter({ hasText: text }).first(),
    ).toBeAttached();
  },
);

// The conversation still holds its messages. The confirmation is not checked here: a scenario that cancelled it has closed it.
Then("nothing is cleared yet", async ({ page }) => {
  // Settle first, so the count is read after the page has finished its pending updates.
  await settle(page);
  await expect.poll(() => visitorMessageCount(page)).toBeGreaterThan(0);
});

When("the visitor chooses Cancel", async ({ page }) => {
  await page.locator(CANCEL).click();
});

Then("the confirmation is closed", async ({ page }) => {
  await expect(page.locator(CONFIRM)).toBeHidden();
});

Then(
  "keyboard focus is on the confirmation's Cancel button",
  async ({ page }) => {
    await expect(page.locator(CANCEL)).toBeFocused();
  },
);

Then("keyboard focus is on the Clear chat button", async ({ page }) => {
  await expect(page.locator(CLEAR)).toBeFocused();
});

When("the visitor chooses Yes, delete", async ({ page }) => {
  await page.locator(YES).click();
});

Then("the conversation shows no messages", async ({ page }) => {
  // The confirmed clear reaches the server, which empties the conversation the page shows.
  await expect(page.locator(USER_MESSAGE)).toHaveCount(0);
});

Then(
  "the confirmation is on screen without scrolling the page",
  async ({ page }) => {
    const viewport = viewportOf(page);
    const box = await boxOf(page.locator(CONFIRM), "the confirmation");
    expect(box.x >= 0 && box.x + box.width <= viewport.width + 0.5).toBe(true);
    expect(box.y >= 0 && box.y + box.height <= viewport.height + 0.5).toBe(
      true,
    );
  },
);

Then(
  "each confirmation button is at least 44 pixels tall and across",
  async ({ page }) => {
    const buttons = page.locator(`${CONFIRM} button`);
    await expect(buttons).toHaveCount(2);
    const boxes = await Promise.all(
      [0, 1].map((index) =>
        boxOf(buttons.nth(index), `confirmation button ${index}`),
      ),
    );
    for (const [index, box] of boxes.entries()) {
      expect(box.height, `button ${index} height`).toBeGreaterThanOrEqual(
        TOUCH_TARGET_PX,
      );
      expect(box.width, `button ${index} width`).toBeGreaterThanOrEqual(
        TOUCH_TARGET_PX,
      );
    }
  },
);

Then("the confirmation is no wider than the screen", async ({ page }) => {
  const box = await boxOf(page.locator(CONFIRM), "the confirmation");
  expect(box.width).toBeLessThanOrEqual(viewportOf(page).width);
});

// The card clips what overflows it, so a popover that runs past the card's edge is cut off even inside the viewport.
// boundingBox reports the unclipped rectangle, which is what a reader would lose.
Then("the confirmation stays inside the Codex card", async ({ page }) => {
  const card = await boxOf(page.locator(".chat-panel"), "the Codex card");
  const box = await boxOf(page.locator(CONFIRM), "the confirmation");
  expect(
    box.y >= card.y - 0.5 && box.y + box.height <= card.y + card.height + 0.5,
    `the confirmation spans ${box.y}..${box.y + box.height} px, the card ${card.y}..${card.y + card.height} px`,
  ).toBe(true);
  expect(
    box.x >= card.x - 0.5 && box.x + box.width <= card.x + card.width + 0.5,
    "the confirmation is inside the card across",
  ).toBe(true);
});

// --- Own messages (chat.feature, Rule "Own messages in the Codex chat") -----------------------

let typedMessage = "";

Given(
  "a visitor's message with Markdown is in the Codex conversation",
  async ({ page }) => {
    await openChatAsAdmin(page);
    typedMessage = MARKDOWN_MESSAGE;
    await sendAndWaitForReply(page, typedMessage);
  },
);

Given(
  "a visitor's message with script and javascript link text is in the Codex conversation",
  async ({ page }) => {
    await openChatAsAdmin(page);
    typedMessage = HOSTILE_MESSAGE;
    await sendAndWaitForReply(page, typedMessage);
  },
);

Given(
  "a visitor's message with line breaks and indentation is in the Codex conversation",
  async ({ page }) => {
    await openChatAsAdmin(page);
    typedMessage = LINES_MESSAGE;
    await sendAndWaitForReply(page, typedMessage);
  },
);

Then("the visitor's message shows its Markdown rendered", async ({ page }) => {
  const rendered = page.locator(USER_MESSAGE).last();
  await expect(rendered.locator("strong")).toHaveCount(1);
  await expect(page.locator(RAW_TEXT).last()).toBeHidden();
});

Then(
  "the visitor's message has a {string} control of at least 44 pixels",
  async ({ page }, label: string) => {
    const control = page
      .getByRole("button", { name: label, exact: true })
      .last();
    await expect(control).toBeVisible();
    const box = await boxOf(control, `the "${label}" control`);
    expect(box.height).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
    expect(box.width).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
  },
);

When(
  "the visitor chooses {string} on the visitor's message",
  async ({ page }, label: string) => {
    await page.getByRole("button", { name: label, exact: true }).last().click();
  },
);

Then("the visitor's message shows the exact typed text", async ({ page }) => {
  const raw = page.locator(RAW_TEXT).last();
  await expect(raw).toBeVisible();
  expect(await raw.textContent()).toBe(typedMessage);
});

Then("the control reads {string}", async ({ page }, label: string) => {
  await expect(
    page.getByRole("button", { name: label, exact: true }).last(),
  ).toBeVisible();
});

Then("the visitor's message contains no script element", async ({ page }) => {
  await expect(
    page.locator(`${USER_MESSAGE} script, ${RAW_TEXT} script`),
  ).toHaveCount(0);
});

// Tab from the confirmation's Cancel button reaches Yes, and the next Tab leaves the confirmation. The Then that follows
// reads whether it closed.
When("the visitor tabs out of the confirmation", async ({ page }) => {
  await page.keyboard.press("Tab");
  await page.keyboard.press("Tab");
});

Then("the visitor's message contains no javascript link", async ({ page }) => {
  // The mailto link must render, so a message with no anchor cannot pass the javascript check.
  await expect(
    page.locator(
      `${USER_MESSAGE} a[href='mailto:test-user-visitor@example.invalid']`,
    ),
  ).toHaveCount(1);
  await expect(
    page.locator(`${USER_MESSAGE} a[href^='javascript:']`),
  ).toHaveCount(0);
});

Then(
  "the visitor's message keeps the typed line breaks and spaces",
  async ({ page }) => {
    const raw = page.locator(RAW_TEXT).last();
    expect(await raw.textContent()).toBe(typedMessage);
    const whiteSpace = await raw.evaluate(
      (element) => getComputedStyle(element).whiteSpace,
    );
    expect(whiteSpace).toBe("pre-wrap");
  },
);

When("the visitor moves focus to the message box", async ({ page }) => {
  await page.locator("[data-role=chat-composer]").focus();
});

Then("keyboard focus is on the message box", async ({ page }) => {
  await expect(page.locator("[data-role=chat-composer]")).toBeFocused();
});
