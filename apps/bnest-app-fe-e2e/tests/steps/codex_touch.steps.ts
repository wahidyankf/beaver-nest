import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  openChatAsAdmin,
  sendAndWaitForReply,
} from "../support/codex-diagrams";
import {
  openOptionsIfCollapsed,
  parseViewport,
} from "../support/chat-ui-steps";
import { emulateTouchPointer } from "../support/touch-pointer";

// The touch and short-screen layout scenarios of chat.feature (the Rule "Codex chat on touch and short screens").
// Each Then reads a rendered box or a computed style in real Chromium. A touch pointer is emulated through the DevTools
// protocol, so `(pointer: coarse)` holds in both the desktop and the mobile project. Their unit proof is the Vitest
// binding in apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts. The coral focus-ring scenarios live in
// codex-touch-focus.steps.ts.

const { Given, Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex composer and most of the conversation fit a small phone
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex header controls are at least 44 pixels tall on a touch screen
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex composer text is 16 pixels on a touch screen
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Codex tables and code blocks show that they scroll
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A long Codex code block scrolls inside a height limit
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A Codex picture fits a short screen
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The Codex diagram source is at least 44 pixels tall on a touch screen
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The message composer leaves most of a short screen to the conversation

const TOUCH_TARGET_PX = 44;
const CODE_BLOCK_MAX_PX = 384;
const SCREEN_IMAGE_SHARE = 0.7;

function latestReply(page: Page): Locator {
  return page.locator("[data-role=assistant-message]").last();
}

async function heightOf(locator: Locator, label: string): Promise<number> {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box.height;
}

function computedOf(locator: Locator, property: string): Promise<string> {
  return locator.evaluate(
    (element, name) => getComputedStyle(element).getPropertyValue(name),
    property,
  );
}

Given(
  "the Codex chat page is open at {string}",
  async ({ page }, spec: string) => {
    await page.setViewportSize(parseViewport(spec));
    await openChatAsAdmin(page);
  },
);

Given("the visitor's pointer is a touch pointer", async ({ page }) => {
  await emulateTouchPointer(page);
});

Given("a Codex reply answers {string}", async ({ page }, prompt: string) => {
  await sendAndWaitForReply(page, prompt);
});

When("the page is laid out", async ({ page }) => {
  // Fonts and the first layout settle before any box is read.
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(
    () =>
      new Promise((resolve) => {
        requestAnimationFrame(() => resolve(null));
      }),
  );
});

Then("the header controls are at least 44 pixels tall", async ({ page }) => {
  // On a phone the model, effort and Clear chat sit in the options panel, so the panel is opened first.
  const toggle = page.locator("[data-role=chat-options-toggle]");
  await openOptionsIfCollapsed(page);
  const controls = [
    toggle,
    page.locator("[data-role=repository-write-toggle]"),
    page.locator("[data-role=model-selector]"),
    page.locator("[data-role=effort-selector]"),
    page.locator("[data-role=clear-chat]"),
  ];
  const heights = await Promise.all(
    controls.map(async (control) => {
      await expect(control).toBeVisible();
      return heightOf(control, "a header control");
    }),
  );
  for (const height of heights) {
    expect(height, "a header control's height").toBeGreaterThanOrEqual(
      TOUCH_TARGET_PX,
    );
  }
});

Then("the message composer text is 16 pixels", async ({ page }) => {
  expect(
    await computedOf(page.locator("[data-role=chat-composer]"), "font-size"),
  ).toBe("16px");
});

Then(
  "the wide table and the code block show a scroll cue",
  async ({ page }) => {
    const reply = latestReply(page);
    const measures = await Promise.all(
      ["table", "pre"].map(async (selector) => {
        const element = reply.locator(selector).first();
        await expect(element).toBeVisible();
        const measure = await element.evaluate((node) => ({
          scrolls: node.scrollWidth > node.clientWidth,
          overflowX: getComputedStyle(node).overflowX,
          background: getComputedStyle(node).backgroundImage,
        }));
        return { selector, measure };
      }),
    );
    for (const { selector, measure } of measures) {
      expect(measure.overflowX, `${selector} overflow`).toBe("auto");
      expect(measure.scrolls, `${selector} does not overflow its box`).toBe(
        true,
      );
      expect(measure.background, `${selector} scroll cue`).toContain(
        "linear-gradient",
      );
    }
  },
);

Then(
  "the code block is no taller than 384 pixels and scrolls",
  async ({ page }) => {
    const code = latestReply(page).locator("pre").first();
    const height = await heightOf(code, "the code block");
    expect(height, "the code block height").toBeLessThanOrEqual(
      CODE_BLOCK_MAX_PX + 1,
    );
    const measure = await code.evaluate((node) => ({
      scrollsDown: node.scrollHeight > node.clientHeight,
      overflowY: getComputedStyle(node).overflowY,
    }));
    expect(measure.overflowY, "the code block vertical overflow").toBe("auto");
    expect(
      measure.scrollsDown,
      "the code block does not scroll vertically",
    ).toBe(true);
  },
);

Then(
  "the logo is no taller than 70 percent of the screen height",
  async ({ page }) => {
    const image = latestReply(page).locator("img").first();
    await expect
      .poll(() =>
        image.evaluate((node) => (node as HTMLImageElement).naturalWidth),
      )
      .toBeGreaterThan(0);
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const height = await heightOf(image, "the reply image");
    expect(height, "the image height").toBeLessThanOrEqual(
      SCREEN_IMAGE_SHARE * viewport.height + 1,
    );
  },
);

Then(
  "the message composer is on screen without scrolling the page",
  async ({ page }) => {
    await expect(page.locator(".composer")).toBeVisible();
    const measured = await page.evaluate(() => ({
      composerBottom:
        document.querySelector(".composer")?.getBoundingClientRect().bottom ??
        Number.POSITIVE_INFINITY,
      pageHeight: document.documentElement.scrollHeight,
      screenHeight: window.innerHeight,
    }));
    expect(
      measured.composerBottom,
      "the composer's bottom edge is below the screen",
    ).toBeLessThanOrEqual(measured.screenHeight);
    expect(
      measured.pageHeight,
      "the whole page is taller than the screen",
    ).toBeLessThanOrEqual(measured.screenHeight);
  },
);

Then(
  "the diagram source summary is at least 44 pixels tall",
  async ({ page }) => {
    const summary = page.locator(".bnest-diagram-source > summary").first();
    await expect(summary).toBeVisible();
    const height = await heightOf(summary, "the diagram source summary");
    expect(height, "the diagram source summary height").toBeGreaterThanOrEqual(
      TOUCH_TARGET_PX,
    );
  },
);

// The header's numeric budget on the composer scenario's phone: at most 30 percent of the window and at most 110 pixels.
// The Vitest binding proves the header wraps its controls onto rows; these numbers are measured here.
Then(
  "the Codex header keeps its controls on wrapping rows",
  async ({ page }) => {
    const header = page.locator(".chat-header");
    await expect(header).toHaveCount(1);
    const height = await heightOf(header, "the Codex header");
    const screenHeight = await page.evaluate(() => window.innerHeight);
    expect(height, "the Codex header's height").toBeLessThanOrEqual(
      0.3 * screenHeight,
    );
    expect(height, "the Codex header row's height").toBeLessThanOrEqual(110);
  },
);
