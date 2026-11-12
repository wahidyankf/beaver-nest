import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { targetBody } from "../support/family-chat-markdown";
import { DRAWN, settledTarget } from "../support/family-chat-diagram-settle";

const { Then } = createBdd();

// A wide diagram keeps its readable width: a 16 px label is at least 12 px (0.75 of the natural width), and the picture is
// never narrower than 30 rem unless the drawing itself is smaller (ADR 004, Decision 5).
const READABLE_REM_PX = 480;

Then("the diagram keeps a readable size", async ({ page }) => {
  await settledTarget(page);
  const figure = targetBody(page).locator(DRAWN).first();
  await expect(figure).toHaveCount(1);
  const sizes = await figure.evaluate((element) => {
    const picture = element.querySelector<HTMLImageElement>(
      ".bnest-diagram-canvas img",
    );
    return {
      natural: Number(picture?.getAttribute("width") ?? 0),
      rendered: picture?.getBoundingClientRect().width ?? 0,
    };
  });
  expect(sizes.natural, "the picture's natural width").toBeGreaterThan(0);
  const readable = Math.min(
    sizes.natural,
    Math.max(READABLE_REM_PX, sizes.natural * 0.75),
  );
  expect(
    sizes.rendered,
    "the rendered picture width against its readable width",
  ).toBeGreaterThanOrEqual(readable - 0.5);
});

Then("the diagram scrolls inside its own box", async ({ page }) => {
  await settledTarget(page);
  const figure = targetBody(page).locator(DRAWN).first();
  await expect(figure).toHaveCount(1);
  const box = await figure.evaluate((element) => {
    const canvas = element.querySelector<HTMLElement>(".bnest-diagram-canvas");
    const bubble = element.closest<HTMLElement>(".family-chat-message-bubble");
    return {
      overflowX: canvas ? getComputedStyle(canvas).overflowX : "missing",
      canvasScrolls: canvas ? canvas.scrollWidth > canvas.clientWidth : false,
      canvasWidth: canvas?.getBoundingClientRect().width ?? 0,
      bubbleWidth: bubble?.clientWidth ?? 0,
    };
  });
  expect(box.overflowX, "the canvas overflow").toBe("auto");
  expect(box.canvasScrolls, "the picture is wider than its box").toBe(true);
  expect(box.canvasWidth, "the canvas against the bubble").toBeLessThanOrEqual(
    box.bubbleWidth,
  );
});

Then(
  "the diagram bubble takes at least 80 percent of the message list width",
  async ({ page }) => {
    // The bubble of the newest message (the diagram just sent) against the message list it sits in.
    const bubble = page
      .locator('[data-role="family-chat-message"]')
      .last()
      .locator(".family-chat-message-bubble");
    const history = page.locator('[data-role="family-chat-history"]');
    const bubbleBox = await bubble.boundingBox();
    const historyBox = await history.boundingBox();
    if (bubbleBox === null || historyBox === null)
      throw new Error("the diagram bubble or the message list has no box");
    expect(
      bubbleBox.width / historyBox.width,
      "the diagram bubble share of the message list",
    ).toBeGreaterThanOrEqual(0.8);
  },
);
