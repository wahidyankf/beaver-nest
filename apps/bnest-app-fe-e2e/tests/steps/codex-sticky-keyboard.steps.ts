import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { boxOf, screenOf } from "../support/sticky-room";

// chat.feature's soft-keyboard scenarios: a smaller screen from the soft
// keyboard keeps the Codex composer on screen. Split out of
// codex-sticky-layout.steps.ts to stay under the repository's 300-line
// step-file budget. The scroll, header, composer, and message-box scenarios
// stay in codex-sticky-layout.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A smaller screen from the soft keyboard keeps the Codex composer on screen

const { Then, When } = createBdd();

const HEADER = ".chat-header";
const SEND = "#chat-composer-form .send-button";

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
