import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

import {
  boxOf,
  CLEAR,
  COMPOSER_FORM,
  HEADER,
  OPTIONS_TOGGLE,
  openOptionsIfCollapsed,
  TOUCH_TARGET_PX,
  viewportOf,
  inScreenOrder,
  measureCodexRoom,
} from "../support/chat-ui-steps";
import {
  openChatAsAdmin,
  sendAndWaitForReply,
} from "../support/codex-diagrams";

const { Given, Then, When } = createBdd();

// --- Phone layout (chat.feature, Rules "Codex chat conversation has most of a phone screen" and the header and
// options rows) ------------------------------------------------------------------------------

Given("a Codex conversation holds three short messages", async ({ page }) => {
  await openChatAsAdmin(page);
  for (const text of ["Short one", "Short two", "Short three"]) {
    // eslint-disable-next-line no-await-in-loop -- each reply must finish before the next message is sent.
    await sendAndWaitForReply(page, text);
  }
});

Then(
  "the conversation takes at least {int} percent of the screen with an empty draft",
  async ({ page }, percent: number) => {
    const measure = await measureCodexRoom(page);
    expect(
      measure.conversation,
      `the conversation is ${measure.conversation} px of ${measure.height} px`,
    ).toBeGreaterThanOrEqual((percent / 100) * measure.height);
  },
);

// The space the header and the composer take, in CSS pixels (chat.feature, the typical Codex phone view).
Then(
  "the header and the composer take at most {int} pixels outside the conversation",
  async ({ page }, limit: number) => {
    const { space } = await measureCodexRoom(page);
    expect(
      space,
      `the space that is not conversation is ${space} px`,
    ).toBeLessThanOrEqual(limit);
  },
);

Then("the newest message is fully above the composer", async ({ page }) => {
  // Works for Codex and Family Chat: the newest message is the last message in document order.
  const newest = page
    .locator(
      '[data-role="family-chat-message"], #chat-conversation [data-role="assistant-message"], #chat-conversation [data-role="user-message"]',
    )
    .last();
  const composer = await boxOf(
    page.locator(`${COMPOSER_FORM}, .family-chat-composer`).first(),
    "the composer",
  );
  const message = await boxOf(newest, "the newest message");
  expect(
    message.y + message.height,
    "the newest message runs under the composer",
  ).toBeLessThanOrEqual(composer.y + 0.5);
});

// The header's controls as they are drawn. Two controls on one line share a centre (within a few pixels), and a second line
// sits a whole control lower, so counting the distinct centres counts the rows.
const HEADER_CONTROLS = [
  ".brand-identity",
  OPTIONS_TOGGLE,
  "[data-role=repository-access]",
  ".model-badge",
].join(", ");

Then("the Codex header has at most two rows", async ({ page }) => {
  const controls = page.locator(`${HEADER} :is(${HEADER_CONTROLS})`);
  const count = await controls.count();
  const centres: number[] = [];
  for (let index = 0; index < count; index += 1) {
    // eslint-disable-next-line no-await-in-loop -- each control is measured in turn, in the page's layout order.
    if (!(await controls.nth(index).isVisible())) continue;
    // eslint-disable-next-line no-await-in-loop -- see above.
    const box = await boxOf(controls.nth(index), `header control ${index}`);
    centres.push(box.y + box.height / 2);
  }
  expect(centres.length, "no visible header controls").toBeGreaterThan(0);
  centres.sort((first, second) => first - second);
  let rows = 1;
  for (let index = 1; index < centres.length; index += 1) {
    if ((centres[index] ?? 0) - (centres[index - 1] ?? 0) > 16) rows += 1;
  }
  expect(rows, `the Codex header has ${rows} rows`).toBeLessThanOrEqual(2);
  const overflows = await page
    .locator(HEADER)
    .evaluate((element) => element.scrollWidth > element.clientWidth + 1);
  expect(overflows, "the header row overflows sideways").toBe(false);
});

Then(
  "the brand link is not covered by any header control",
  async ({ page }) => {
    // The brand link's centre and its left edge must hit the link itself, not a control drawn over it.
    const brand = await boxOf(
      page.locator(".brand-identity"),
      "the brand link",
    );
    const middle = brand.y + brand.height / 2;
    for (const x of [brand.x + brand.width / 2, brand.x + 4]) {
      // eslint-disable-next-line no-await-in-loop -- two points, checked in turn.
      const covered = await page.evaluate(
        ({ pointX, pointY }) =>
          !document
            .elementFromPoint(pointX, pointY)
            ?.closest(".brand-identity"),
        { pointX: x, pointY: middle },
      );
      expect(covered, `a control covers the brand link at x ${x}`).toBe(false);
    }
  },
);

Then(
  "the repository access state and the model badge are visible without opening Options",
  async ({ page }) => {
    await expect(page.locator("[data-role=repository-access]")).toBeVisible();
    await expect(page.locator(".model-badge").first()).toBeVisible();
    expect(
      await page.locator("#chat-options .model-badge").count(),
      "the model badge is inside the Options panel",
    ).toBe(0);
  },
);

Then(
  "the options panel keeps 12 pixels from the right edge of the screen",
  async ({ page }) => {
    const panel = await boxOf(
      page.locator("#chat-options"),
      "the options panel",
    );
    const gap = viewportOf(page).width - (panel.x + panel.width);
    expect(
      gap,
      "the gap from the options panel to the right edge",
    ).toBeGreaterThanOrEqual(11.5);
    expect(
      gap,
      "the gap from the options panel to the right edge",
    ).toBeLessThanOrEqual(12.5);
  },
);

Then("the options panel has no fade over its controls", async ({ page }) => {
  const mask = await page
    .locator("#chat-options")
    .evaluate((element) => getComputedStyle(element).maskImage);
  expect(mask, "the options panel keeps an edge fade").toBe("none");
});

Then(
  "the options panel does not cover the repository access state",
  async ({ page }) => {
    const access = await boxOf(
      page.locator("[data-role=repository-access]"),
      "the repository access state",
    );
    const panel = await boxOf(
      page.locator("#chat-options"),
      "the options panel",
    );
    expect(
      panel.y,
      "the options panel starts over the repository access state",
    ).toBeGreaterThanOrEqual(access.y + access.height - 0.5);
  },
);

Then("the Codex options panel is closed", async ({ page }) => {
  await expect(page.locator("#chat-options")).not.toHaveClass(/is-open/u);
  await expect(page.locator("#chat-options")).toBeHidden();
});

Then("the Options button reports it is closed", async ({ page }) => {
  await expect(page.locator(OPTIONS_TOGGLE)).toHaveAttribute(
    "aria-expanded",
    "false",
  );
});

When("the visitor taps the message box", async ({ page }) => {
  // A click is the tap a touch screen sends, and it is the event the page listens to on every project.
  await page.locator("[data-role=chat-composer]").click();
});

Then(
  "the header holds the brand, the repository access state and the options button",
  async ({ page }) => {
    await expect(page.locator(".brand-identity")).toBeVisible();
    await expect(page.locator("[data-role=repository-access]")).toBeVisible();
    await expect(page.locator(OPTIONS_TOGGLE)).toBeVisible();
  },
);

Then(
  "the header's tab order follows the screen: brand, Options, access state, model badge",
  async ({ page }) => {
    // The tab order is the DOM order. The screen order is read from the boxes: rows from top to bottom, then left to
    // right within a row. The two must match, or Tab would jump across the header.
    const parts = await page.evaluate(() =>
      Array.from(
        document.querySelectorAll(
          ".chat-header .brand-identity, .chat-header [data-role='chat-options-toggle'], .chat-header [data-role='repository-access'], .chat-header .model-badge",
        ),
      ).map((element) => {
        const box = element.getBoundingClientRect();
        return {
          name:
            (element instanceof HTMLElement && element.dataset["role"]) ||
            element.className,
          top: box.top,
          left: box.left,
        };
      }),
    );
    const tabOrder = parts.map((part) => part.name);
    expect(tabOrder, "the header focus order").toEqual([
      "brand-identity",
      "chat-options-toggle",
      "repository-access",
      "model-badge",
    ]);
    expect(
      inScreenOrder(parts),
      "the header's screen order differs from its tab order",
    ).toEqual(tabOrder);
  },
);

Then(
  "the options button is at least 44 pixels across and tall",
  async ({ page }) => {
    const box = await boxOf(page.locator(OPTIONS_TOGGLE), "the options button");
    expect(box.width).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
    expect(box.height).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
  },
);

When("the visitor opens the Codex options panel", async ({ page }) => {
  await openOptionsIfCollapsed(page);
});

Then(
  "the model selector is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator("#model-selector")).toBeVisible();
  },
);

Then(
  "the reasoning effort selector is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator("#effort-selector")).toBeVisible();
  },
);

Then(
  "the Clear chat control is on screen in the options panel",
  async ({ page }) => {
    await expect(page.locator(CLEAR)).toBeVisible();
  },
);

Then("the options panel is no wider than the screen", async ({ page }) => {
  const box = await boxOf(page.locator(".chat-actions"), "the options panel");
  expect(box.width).toBeLessThanOrEqual(viewportOf(page).width);
});

Then(
  "every options panel control is at least 44 pixels tall",
  async ({ page }) => {
    const selectors = ["#model-selector", "#effort-selector", CLEAR];
    const boxes = await Promise.all(
      selectors.map((selector) => boxOf(page.locator(selector), selector)),
    );
    for (const [index, box] of boxes.entries()) {
      expect(box.height, `${selectors[index]} height`).toBeGreaterThanOrEqual(
        TOUCH_TARGET_PX,
      );
    }
  },
);
