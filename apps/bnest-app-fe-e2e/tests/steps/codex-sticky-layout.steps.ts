import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { saveChatWithMessages } from "../support/codex-chat-transcript";
import { instanceIdentities } from "../support/instance-identities";
import {
  boxOf,
  EDGE_TOLERANCE_PX,
  saveScrolledRoom,
  screenOf,
} from "../support/sticky-room";

// chat.feature, Rule "Codex header and composer stay in place while the messages scroll". Every box is read from the
// rendered page in Chromium at the served origin. The page itself never scrolls; only the conversation does.

const { Given, Then, When } = createBdd();

const CONVERSATION = "#chat-conversation";
const HEADER = ".chat-header";
const COMPOSER = "#chat-composer-form";
const SEND = "#chat-composer-form .send-button";
const TEXTAREA = "#chat-composer-form textarea";
const NEWEST = [
  '#chat-conversation [data-role="assistant-message"]',
  '#chat-conversation [data-role="user-message"]',
].join(", ");

Given(
  "a Codex conversation holds {int} messages",
  async ({ page: _page }, count) => {
    await saveChatWithMessages(instanceIdentities().admin.username, count);
  },
);

When(
  "the visitor scrolls the Codex conversation to the middle",
  async ({ page, $testInfo }) => {
    const conversation = page.locator(CONVERSATION);
    const overflows = await conversation.evaluate(
      (element) => element.scrollHeight > element.clientHeight,
    );
    if (!overflows)
      throw new Error("the conversation does not overflow its box");
    await conversation.evaluate((element) => {
      element.scrollTop = Math.floor(
        (element.scrollHeight - element.clientHeight) / 2,
      );
    });
    await expect
      .poll(() => conversation.evaluate((element) => element.scrollTop))
      .toBeGreaterThan(0);
    await saveScrolledRoom(page, $testInfo, "codex", {
      scroller: CONVERSATION,
      header: HEADER,
      composer: COMPOSER,
    });
  },
);

Then("the Codex header is at the top of the screen", async ({ page }) => {
  const header = await boxOf(page, HEADER);
  expect(header.y, "header top").toBeLessThanOrEqual(EDGE_TOLERANCE_PX);
  expect(header.y, "header top on screen").toBeGreaterThanOrEqual(0);
});

Then("the Codex composer is at the bottom of the screen", async ({ page }) => {
  const composer = await boxOf(page, COMPOSER);
  const header = await boxOf(page, HEADER);
  const conversation = await boxOf(page, CONVERSATION);
  const { height } = screenOf(page);
  const bottom = composer.y + composer.height;
  // The sizes go into the message, so a failure says which box takes the room (header, conversation or composer).
  expect(
    bottom,
    `composer bottom on screen (header ${header.height} px, conversation ${conversation.height} px, composer ${composer.height} px, screen ${height} px)`,
  ).toBeLessThanOrEqual(height);
  expect(height - bottom, "gap below the composer").toBeLessThanOrEqual(
    EDGE_TOLERANCE_PX,
  );
});

Then("the newest Codex message ends above the composer", async ({ page }) => {
  const newest = await boxOf(page, NEWEST);
  const composer = await boxOf(page, COMPOSER);
  expect(newest.y + newest.height, "newest message bottom").toBeLessThanOrEqual(
    composer.y,
  );
});

Then("the page does not scroll", async ({ page }) => {
  const scroll = await page.evaluate(() => {
    const root = document.scrollingElement ?? document.documentElement;
    return {
      vertical: root.scrollHeight - root.clientHeight,
      horizontal: root.scrollWidth - root.clientWidth,
      offset: window.scrollY,
    };
  });
  expect(scroll.vertical, "vertical page overflow").toBeLessThanOrEqual(1);
  expect(scroll.horizontal, "horizontal page overflow").toBeLessThanOrEqual(1);
  expect(scroll.offset, "page scroll offset").toBe(0);
  // A scroll attempt over the room's header: a wheel over the header scrolls the page only if the page can move.
  const headerSelector =
    (await page.locator(".family-chat-header").count()) > 0
      ? ".family-chat-header"
      : HEADER;
  const header = await boxOf(page, headerSelector);
  await page.mouse.move(
    header.x + header.width / 2,
    header.y + header.height / 2,
  );
  await page.mouse.wheel(0, 300);
  // Two frames let a scroll the wheel started land before the offset is read.
  const offsetAfterWheel = await page.evaluate(
    () =>
      new Promise<number>((resolve) => {
        requestAnimationFrame(() =>
          requestAnimationFrame(() => resolve(window.scrollY)),
        );
      }),
  );
  expect(offsetAfterWheel, "the page offset after a scroll attempt").toBe(0);
});

When(
  "the soft keyboard shrinks the screen to {string}",
  async ({ page }, spec: string) => {
    const match = /^(\d+)x(\d+)$/u.exec(spec);
    if (!match) throw new Error(`unknown screen size ${spec}`);
    await page.setViewportSize({
      width: Number(match[1]),
      height: Number(match[2]),
    });
    await page.evaluate(
      () =>
        new Promise<void>((resolve) => {
          requestAnimationFrame(() => resolve());
        }),
    );
  },
);

interface VvhState {
  synced: boolean;
  written: string;
  visible: number;
  shell: number;
  marginPx: number;
}

// The written --vvh, the visual viewport it should equal, and the room shell's rendered height, all read in one call.
function vvhState(page: Page): Promise<VvhState> {
  return page.evaluate(() => {
    const visible = window.visualViewport?.height ?? window.innerHeight;
    const written = document.documentElement.style
      .getPropertyValue("--vvh")
      .trim();
    const shell = document.querySelector(".chat-shell, .family-chat-shell");
    const rem = Number(
      getComputedStyle(document.documentElement).fontSize.replace("px", ""),
    );
    return {
      synced: written === `${visible}px`,
      written,
      visible,
      shell: shell ? shell.getBoundingClientRect().height : -1,
      marginPx: 2.5 * rem,
    };
  });
}

// The page writes --vvh from the visual viewport, and the room shell fills that height. The Family shell may give up its
// 2.5rem margin; the Codex shell takes the whole visible area. The declared rule is checked by the Vitest layer.
Then(
  "the Codex room fills the visible area above the keyboard",
  async ({ page }) => {
    await expect.poll(() => vvhState(page)).toMatchObject({ synced: true });
    const state = await vvhState(page);
    expect(state.shell, "the room shell is on the page").toBeGreaterThanOrEqual(
      0,
    );
    expect(
      state.shell,
      `room shell height, visible area ${state.visible} px, --vvh ${state.written}`,
    ).toBeGreaterThanOrEqual(state.visible - state.marginPx);
    expect(
      state.shell,
      "the room shell does not exceed the visible area",
    ).toBeLessThanOrEqual(state.visible + 1);
  },
);

Then("the Send button and the Codex header are on screen", async ({ page }) => {
  const { height } = screenOf(page);
  const send = await boxOf(page, SEND);
  const header = await boxOf(page, HEADER);
  expect(send.y + send.height, "Send bottom").toBeLessThanOrEqual(height);
  expect(header.y, "header top").toBeGreaterThanOrEqual(0);
});

Then(
  "the Codex message box is no taller than {int} lines",
  async ({ page }, lines: number) => {
    const limit = await page.locator(TEXTAREA).evaluate((element) => {
      // Computed lengths are pixel values here, so the unit is dropped before each number is read.
      const style = getComputedStyle(element);
      const lineHeight = Number(style.lineHeight.replace("px", ""));
      const chrome =
        Number(style.paddingTop.replace("px", "")) +
        Number(style.paddingBottom.replace("px", "")) +
        Number(style.borderTopWidth.replace("px", "")) +
        Number(style.borderBottomWidth.replace("px", ""));
      return { lineHeight, chrome };
    });
    const box = await boxOf(page, TEXTAREA);
    const cap = lines * limit.lineHeight + limit.chrome;
    expect(box.height, `message box height, cap ${cap} px`).toBeLessThanOrEqual(
      cap + 1,
    );
  },
);

// The message box is at least two lines tall: its own height, measured, against two lines of text plus its chrome.
Then("the Codex message box is at least two lines tall", async ({ page }) => {
  const metrics = await page.locator(TEXTAREA).evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      lineHeight: Number(style.lineHeight.replace("px", "")),
      chrome:
        Number(style.paddingTop.replace("px", "")) +
        Number(style.paddingBottom.replace("px", "")) +
        Number(style.borderTopWidth.replace("px", "")) +
        Number(style.borderBottomWidth.replace("px", "")),
    };
  });
  const box = await boxOf(page, TEXTAREA);
  expect(box.height, "the message box height").toBeGreaterThanOrEqual(
    2 * metrics.lineHeight + metrics.chrome - 1,
  );
});

// The header keeps its full height when a short landscape window gives the conversation the room: its controls sit
// inside its box, and the conversation starts below it. The two-row phone header is not reopened by this step.
Then(
  "the Codex header keeps its full height and its controls stay inside it",
  async ({ page }) => {
    const header = await boxOf(page, HEADER);
    expect(header.height, "the header height").toBeGreaterThanOrEqual(40);
    const conversation = await boxOf(page, CONVERSATION);
    expect(
      conversation.y,
      "the conversation starts below the header",
    ).toBeGreaterThanOrEqual(header.y + header.height - 0.5);
    const controls = await page
      .locator(
        `${HEADER} button, ${HEADER} select, ${HEADER} a, ${HEADER} input`,
      )
      .evaluateAll((nodes) =>
        nodes
          .filter((node) => node.getClientRects().length > 0)
          .map((node) => {
            const rect = node.getBoundingClientRect();
            return {
              top: rect.top,
              bottom: rect.bottom,
              left: rect.left,
              right: rect.right,
            };
          }),
      );
    expect(controls.length, "the header has visible controls").toBeGreaterThan(
      0,
    );
    for (const control of controls) {
      expect(control.top, "a control's top edge").toBeGreaterThanOrEqual(
        header.y - 0.5,
      );
      expect(control.bottom, "a control's bottom edge").toBeLessThanOrEqual(
        header.y + header.height + 0.5,
      );
      expect(control.left, "a control's left edge").toBeGreaterThanOrEqual(
        header.x - 0.5,
      );
      expect(control.right, "a control's right edge").toBeLessThanOrEqual(
        header.x + header.width + 0.5,
      );
    }
  },
);

Then(
  "the Codex message list keeps its overscroll inside itself",
  async ({ page }) => {
    const overscroll = await page
      .locator(CONVERSATION)
      .evaluate((element) => getComputedStyle(element).overscrollBehaviorY);
    expect(overscroll, "the Codex message list's overscroll").toBe("contain");
  },
);
