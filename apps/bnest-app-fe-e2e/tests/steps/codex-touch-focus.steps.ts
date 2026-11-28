import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The coral focus-ring scenarios of chat.feature. Split out of
// codex_touch.steps.ts to stay under the repository's 300-line step-file
// budget. The touch sizing and short-screen scenarios stay in
// codex_touch.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Codex links, tables, code blocks and diagram sources show the room's coral focus ring

const { Then } = createBdd();

const CORAL_RGB = "rgb(229, 99, 61)";

function latestReply(page: Page): Locator {
  return page.locator("[data-role=assistant-message]").last();
}

// Presses Tab from the page's start until the target has focus, as a keyboard reader would. A script focus does not
// match `:focus-visible` after a mouse click, so the ring a keyboard reader sees is only shown this way.
async function tabTo(page: Page, target: Locator, presses = 0): Promise<void> {
  if (presses === 0)
    await page.evaluate(() =>
      (document.activeElement as HTMLElement | null)?.blur(),
    );
  if (await target.evaluate((node) => node === document.activeElement)) return;
  if (presses >= 300) throw new Error("the keyboard cannot reach the link");
  // Each Tab moves focus from where the previous one left it, so the presses cannot run in parallel.
  await page.keyboard.press("Tab");
  return tabTo(page, target, presses + 1);
}

Then("a focused link shows the coral focus ring", async ({ page }) => {
  const link = latestReply(page).locator("a[href]").first();
  await tabTo(page, link);
  await expect(link).toBeFocused();
  const ring = await link.evaluate((node) => {
    const style = getComputedStyle(node);
    return {
      color: style.outlineColor,
      width: style.outlineWidth,
      style: style.outlineStyle,
    };
  });
  expect(ring).toEqual({ color: CORAL_RGB, width: "3px", style: "solid" });
});

/** The computed outline of a focused element, as the coral ring a keyboard reader sees. */
function ringOfFocused(target: Locator): Promise<{
  color: string;
  width: string;
  style: string;
}> {
  return target.evaluate((node) => {
    const style = getComputedStyle(node);
    return {
      color: style.outlineColor,
      width: style.outlineWidth,
      style: style.outlineStyle,
    };
  });
}

/** Tabs to the element and checks that it shows the coral ring while focused. */
async function expectFocusedCoralRing(
  page: Page,
  reply: Locator,
  selector: string,
): Promise<void> {
  const target = reply.locator(selector).first();
  await tabTo(page, target);
  await expect(target).toBeFocused();
  expect(await ringOfFocused(target), selector).toEqual({
    color: CORAL_RGB,
    width: "3px",
    style: "solid",
  });
}

Then(
  "a focused table and a focused code block show the coral focus ring",
  async ({ page }) => {
    // A table and a code block are reached by Tab like the link, and their computed outline is read while focused.
    const reply = latestReply(page);
    await expectFocusedCoralRing(page, reply, "table");
    await expectFocusedCoralRing(page, reply, "pre");
  },
);

Then(
  "a focused diagram source shows the coral focus ring",
  async ({ page }) => {
    const summary = page.locator(".bnest-diagram-source > summary").first();
    await tabTo(page, summary);
    await expect(summary).toBeFocused();
    expect(await ringOfFocused(summary)).toEqual({
      color: CORAL_RGB,
      width: "3px",
      style: "solid",
    });
  },
);
