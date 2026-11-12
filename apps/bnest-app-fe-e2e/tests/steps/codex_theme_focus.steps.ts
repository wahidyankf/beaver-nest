import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Codex theme buttons' keyboard focus ring (chat.feature, the Rule "Codex chat on touch and short screens"). The
// buttons take the same 3 px coral ring as the other Codex header controls; the Vitest binding proves the declared
// outline in codex_layout.steps.ts.

const { Then, When } = createBdd();

const CORAL_RGB = "rgb(229, 99, 61)";

When("the visitor tabs to a Codex theme button", async ({ page }) => {
  for (let press = 0; press < 40; press += 1) {
    // eslint-disable-next-line no-await-in-loop -- each Tab is judged before the next one.
    const inside = await page.evaluate(
      () =>
        (document.activeElement?.closest(".chat-theme-control") ?? null) !==
        null,
    );
    if (inside) return;
    // eslint-disable-next-line no-await-in-loop -- the same press loop.
    await page.keyboard.press("Tab");
  }
  throw new Error("Tab never reached a Codex theme button");
});

Then(
  "the focused Codex theme button shows the coral focus ring",
  async ({ page }) => {
    const ring = await page
      .locator(".chat-theme-control button:focus-visible")
      .first()
      .evaluate((node) => {
        const style = getComputedStyle(node);
        return {
          color: style.outlineColor,
          style: style.outlineStyle,
          width: style.outlineWidth,
        };
      });
    expect(ring).toEqual({ color: CORAL_RGB, style: "solid", width: "3px" });
  },
);
