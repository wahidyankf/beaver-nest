import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The layout a phone reader sees (ADR 002, Decision 2 and the Markdown rules in app.css). Each check reads a
// computed style or a box, so a CSS rule that regresses fails here. Unit and integration prove only the structure
// these checks depend on; the scenario is `@integration-exempt` for that reason.
const { Then } = createBdd();

const PHONE_VIEWPORT = { width: 390, height: 844 };

function latestReply(page: Page): Locator {
  return page.locator("[data-role=assistant-message]").last();
}

async function requireBox(locator: Locator, label: string) {
  const box = await locator.boundingBox();

  if (box === null) throw new Error(`${label} has no box.`);

  return box;
}

// A wide table scrolls sideways inside the bubble, and the page itself does not widen.
async function expectWideTableScrollsInside(
  page: Page,
  reply: Locator,
  bubbleWidth: number,
): Promise<void> {
  const table = reply.locator("table").first();

  await expect(table).toHaveCSS("overflow-x", "auto");

  const measure = await table.evaluate((element) => ({
    scrolls: element.scrollWidth > element.clientWidth,
    width: element.getBoundingClientRect().width,
  }));

  expect(measure.scrolls).toBe(true);
  expect(measure.width).toBeLessThanOrEqual(bubbleWidth);

  const pageWidth = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));

  expect(pageWidth.scroll).toBeLessThanOrEqual(pageWidth.client);
}

// A task checkbox and its text share one line: the text is inline and their centres line up.
async function expectTaskBesideItsText(reply: Locator): Promise<void> {
  const task = reply.locator("li:has(> input[type=checkbox]):has(> p)").first();

  await expect(task.locator("> p")).toHaveCSS("display", "inline");

  const [box, text] = await Promise.all([
    requireBox(task.locator("input[type=checkbox]"), "The task checkbox"),
    requireBox(task.locator("> p"), "The task text"),
  ]);

  const boxCentre = box.y + box.height / 2;
  const textCentre = text.y + text.height / 2;

  expect(Math.abs(boxCentre - textCentre)).toBeLessThan(text.height / 2);
}

// Only the first paragraph of a task item sits beside its checkbox; a later paragraph of the same item stays a block.
async function expectLaterTaskParagraphIsBlock(reply: Locator): Promise<void> {
  const later = reply.locator(
    "li:has(> input[type=checkbox]) > p:nth-of-type(2)",
  );

  await expect(later).toHaveCount(1);
  await expect(later).toHaveCSS("display", "block");
}

// A link is underlined, so it is not told apart by its colour alone.
async function expectUnderlinedLink(reply: Locator): Promise<void> {
  await expect(reply.locator("a", { hasText: "Beaver Nest docs" })).toHaveCSS(
    "text-decoration-line",
    "underline",
  );
}

// An image keeps to the bubble width and to the height cap, once the browser has decoded it.
async function expectImageInsideBubble(
  reply: Locator,
  bubbleWidth: number,
): Promise<void> {
  const image = reply.locator("img").first();

  await expect
    .poll(() =>
      image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
    )
    .toBeGreaterThan(0);
  await expect(image).toHaveCSS("max-height", "448px");

  const box = await requireBox(image, "The Codex reply image");

  expect(box.width).toBeLessThanOrEqual(bubbleWidth);
}

// The viewport is set here, before the layout is read, so the checks run at a phone width.
Then(
  "the latest Codex reply lays out its table, task list, link and image inside the bubble",
  async ({ page }) => {
    await page.setViewportSize(PHONE_VIEWPORT);

    const reply = latestReply(page);
    const bubble = await requireBox(
      reply.locator("xpath=ancestor::article[1]"),
      "The Codex reply bubble",
    );

    await expectWideTableScrollsInside(page, reply, bubble.width);
    await expectTaskBesideItsText(reply);
    await expectLaterTaskParagraphIsBlock(reply);
    await expectUnderlinedLink(reply);
    await expectImageInsideBubble(reply, bubble.width);
  },
);

Then(
  "the latest Codex reply holds a wide table and an image",
  async ({ page }) => {
    await expect
      .poll(() => latestReply(page).locator("table th").count(), {
        timeout: 15_000,
      })
      .toBeGreaterThanOrEqual(8);
    await expect(latestReply(page).locator("img").first()).toBeAttached();
  },
);

// At a phone width neither the page nor the reply bubble scrolls sideways: a wide table scrolls inside its own
// element, and an image shrinks to the bubble (ADR 003, threat table: "Wide image or table breaks the phone layout").
Then(
  "the page does not overflow horizontally at 390 pixels",
  async ({ page }) => {
    await page.setViewportSize(PHONE_VIEWPORT);
    // A picture has no width to overflow with until it has decoded, so each one must have loaded before the measure.
    await expect
      .poll(
        () =>
          latestReply(page)
            .locator("img")
            .evaluateAll(
              (images) =>
                images.length > 0 &&
                images.every(
                  (image) => (image as HTMLImageElement).naturalWidth > 0,
                ),
            ),
        { timeout: 15_000 },
      )
      .toBe(true);

    const pageWidth = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    const bubble = latestReply(page).locator("xpath=ancestor::article[1]");
    const bubbleWidth = await bubble.evaluate((element) => ({
      scroll: element.scrollWidth,
      client: element.clientWidth,
    }));

    expect(pageWidth.scroll).toBeLessThanOrEqual(pageWidth.client);
    expect(bubbleWidth.scroll).toBeLessThanOrEqual(bubbleWidth.client);
  },
);
