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

Then("the clear request is sent to Codex", async ({ page }) => {
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
