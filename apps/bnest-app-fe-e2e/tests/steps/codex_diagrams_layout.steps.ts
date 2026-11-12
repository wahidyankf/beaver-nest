import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { expectDecodedPicture, pictureLayout } from "../support/codex-diagrams";

// The 320 px picture-layout steps of chat.feature's Codex diagram rules (tag @codex-diagram), in Chromium. Split out of
// codex_diagrams.steps.ts to keep that file within the line limit; the steps and their proof are unchanged.
const { Then } = createBdd();

Then(
  "the picture scrolls inside its own box at 320 pixels",
  async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 640 });
    await expectDecodedPicture(page);

    const layout = await pictureLayout(page);

    expect(layout.overflowX).toBe("auto");
    expect(layout.canvasScrolls).toBe(true);
    expect(layout.canvasWidth).toBeLessThanOrEqual(320);
    expect(layout.pageScrollWidth).toBeLessThanOrEqual(layout.pageClientWidth);
  },
);

Then("the picture fits its own box at 320 pixels", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 });
  await expectDecodedPicture(page);

  const layout = await pictureLayout(page);

  expect(layout.canvasScrolls, "a narrow picture is wider than its box").toBe(
    false,
  );
  expect(layout.imageWidth).toBeLessThanOrEqual(layout.canvasWidth + 0.5);
  expect(layout.pageScrollWidth).toBeLessThanOrEqual(layout.pageClientWidth);
});

// ADR 004, Decision 5: the picture is at least 0.75 of its natural width (a 16 px label stays at 12 px or more) and at
// least 30 rem, unless the drawing is smaller than that.
const READABLE_REM_PX = 480;

Then("the picture keeps a readable size at 320 pixels", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 });
  await expectDecodedPicture(page);

  const layout = await pictureLayout(page);
  const readable = Math.min(
    layout.naturalWidth,
    Math.max(READABLE_REM_PX, layout.naturalWidth * 0.75),
  );

  expect(layout.naturalWidth, "the picture's natural width").toBeGreaterThan(0);
  expect(
    layout.imageWidth,
    "the rendered picture width against its readable width",
  ).toBeGreaterThanOrEqual(readable - 0.5);
});
