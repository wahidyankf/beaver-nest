import { expect, type Locator } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Codex header's repository access state, its end fade, the message box height cap and the hidden Message label
// (chat.feature, Rule "Codex chat on touch and short screens"). Each Then reads a rendered box in real Chromium; the
// Vitest binding (apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts) proves the declared CSS. Kept apart from
// codex_header.steps.ts so each step file stays within its line limit.

const { Given, Then } = createBdd();

type Box = { x: number; y: number; width: number; height: number };

async function boxOf(locator: Locator, label: string): Promise<Box> {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

const HEADER_ROW = ".chat-actions";
const TOUCH_TARGET_PX = 44;

// --- Repository access state, the row's end fade, the message box cap and the hidden label (round 3) -------------

const ACCESS_STATE = "[data-role=repository-access]";
const WRITE_TOGGLE = "[data-role=repository-write-toggle]";
const COMPOSER_BOX = "[data-role=chat-composer]";
const HEADER_MAX_PX = 160;

Given("repository writes are {string}", async ({ page }, state: string) => {
  // The header is read in the state the scenario names: writes off (the default) or switched on by the visitor.
  const access = page.locator(ACCESS_STATE);
  if (state === "enabled") {
    await page.locator(WRITE_TOGGLE).click();
    await expect(access).toContainText("Repo write enabled");
    return;
  }
  if (state !== "read-only") throw new Error(`unknown write state ${state}`);
  await expect(access).toContainText("Repo read-only");
});

/** True when some box around the element scrolls sideways, so the element can sit out of view. */
function insideSidewaysScroller(locator: Locator): Promise<boolean> {
  return locator.evaluate((node) => {
    for (let box = node.parentElement; box; box = box.parentElement) {
      const style = getComputedStyle(box);
      if (
        /(auto|scroll|hidden)/u.test(style.overflowX) &&
        box.scrollWidth > box.clientWidth
      ) {
        return true;
      }
    }
    return false;
  });
}

Then(
  "the repository access state is visible without scrolling the header",
  async ({ page }) => {
    // The state sits in the header outside every sideways scroller, and its box is inside the screen and the header.
    const access = page.locator(ACCESS_STATE);
    await expect(access).toBeVisible();
    expect(
      await insideSidewaysScroller(access),
      "the access state is inside a scrolling box",
    ).toBe(false);
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const box = await boxOf(access, "the repository access state");
    const header = await boxOf(
      page.locator(".chat-header"),
      "the Codex header",
    );
    expect(
      box.x,
      "the access state starts left of the screen",
    ).toBeGreaterThanOrEqual(-0.5);
    expect(
      box.x + box.width,
      "the access state ends right of the screen",
    ).toBeLessThanOrEqual(viewport.width + 0.5);
    expect(
      box.y,
      "the access state is above the header",
    ).toBeGreaterThanOrEqual(header.y - 0.5);
    expect(
      box.y + box.height,
      "the access state is below the header",
    ).toBeLessThanOrEqual(header.y + header.height + 0.5);
  },
);

Then(
  "the repository write toggle is at least 44 pixels tall",
  async ({ page }) => {
    const toggle = page.locator(WRITE_TOGGLE);
    await expect(toggle).toBeVisible();
    const box = await boxOf(toggle, "the repository write toggle");
    expect(
      box.height,
      "the repository write toggle height",
    ).toBeGreaterThanOrEqual(TOUCH_TARGET_PX);
  },
);

Then("the header's scrolling row ends inside the screen", async ({ page }) => {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  const row = await boxOf(
    page.locator(HEADER_ROW),
    "the header's scrolling row",
  );
  expect(
    row.x + row.width,
    "the scrolling row runs past the right edge of the screen",
  ).toBeLessThanOrEqual(viewport.width + 0.5);
});

Then(
  "the last header control clears the edge fade when the row is scrolled to its end",
  async ({ page }) => {
    // The fade is the stretch the row's mask covers at its end; the last control must sit clear of that stretch.
    const row = page.locator(HEADER_ROW);
    const fadePx = await row.evaluate((node) => {
      // Chromium reports the resolved stop, in pixels or in rem as written.
      const match = /calc\(100% - ([\d.]+)(px|rem)\)/u.exec(
        getComputedStyle(node).maskImage,
      );
      if (match === null) return Number.NaN;
      return match[2] === "rem" ? Number(match[1]) * 16 : Number(match[1]);
    });
    expect(fadePx, "the row's edge fade width").toBeGreaterThan(0);
    await row.evaluate((element) => {
      element.scrollLeft = element.scrollWidth;
    });
    const rowBox = await boxOf(row, "the header's scrolling row");
    const last = await boxOf(
      page.locator(`${HEADER_ROW} > *`).last(),
      "the last header control",
    );
    expect(
      last.x + last.width,
      `the last control ends under the ${fadePx} px fade`,
    ).toBeLessThanOrEqual(rowBox.x + rowBox.width - fadePx + 0.5);
  },
);

Then(
  "the message box stops at its height cap and scrolls the rest of the draft",
  async ({ page }) => {
    // The cap is 12 rem or 22 percent of the window's height, whichever is smaller. A six-line draft is taller than
    // that cap, so the box stops at the cap and scrolls. Without the cap the box would grow to the draft's height.
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const box = page.locator(COMPOSER_BOX);
    const measure = await box.evaluate((node) => ({
      height: node.getBoundingClientRect().height,
      overflowY: getComputedStyle(node).overflowY,
      scrolls: node.scrollHeight > node.clientHeight,
    }));
    const capPx = Math.min(12 * 16, 0.22 * viewport.height);
    expect(measure.height, "the message box height").toBeLessThanOrEqual(
      capPx + 1,
    );
    expect(
      measure.height,
      "the message box stops at its cap, not short of it",
    ).toBeGreaterThanOrEqual(capPx - 1);
    expect(measure.overflowY, "the message box overflow").toBe("auto");
    expect(measure.scrolls, "the draft overflows the message box").toBe(true);
  },
);

Then("the Codex header is at most 160 pixels tall", async ({ page }) => {
  const box = await boxOf(page.locator(".chat-header"), "the Codex header");
  expect(box.height, "the Codex header's height").toBeLessThanOrEqual(
    HEADER_MAX_PX,
  );
});

Then("the message box is named {string}", async ({ page }, name: string) => {
  // The accessible name is what a screen reader announces for the box, even though the label is out of sight.
  const box = page.getByRole("textbox", { name, exact: true });
  await expect(box).toHaveAttribute("data-role", "chat-composer");
  await expect(box).toBeVisible();
});

Then(
  "the visible Message label takes no space in the composer",
  async ({ page }) => {
    const label = await boxOf(
      page.locator(".composer .label"),
      "the visible Message label",
    );
    expect(label.width, "the label width").toBeLessThanOrEqual(1);
    expect(label.height, "the label height").toBeLessThanOrEqual(1);
  },
);
