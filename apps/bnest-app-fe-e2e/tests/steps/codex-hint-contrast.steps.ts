import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then } = createBdd();

// WCAG AA for text (4.5 to 1). The colours are read from the painted page, not from the stylesheet. The unit proof is
// the Vitest binding in apps/bnest-app/assets/test/behaviour/codex_composer.steps.ts, which reads the shipped tokens.
const TEXT_MIN_RATIO = 4.5;

function channelLuminance(value: number): number {
  const channel = value / 255;
  return channel <= 0.03928
    ? channel / 12.92
    : ((channel + 0.055) / 1.055) ** 2.4;
}

/** The WCAG relative luminance of a computed `rgb(...)` or `rgba(...)` colour. */
function luminanceOf(computed: string): number {
  const match = /rgba?\((\d+),\s*(\d+),\s*(\d+)/u.exec(computed);
  if (!match) throw new Error(`not a computed rgb colour: ${computed}`);
  const [red, green, blue] = [match[1], match[2], match[3]].map((channel) =>
    channelLuminance(Number(channel)),
  ) as [number, number, number];
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

Then(
  "the send shortcut hint has at least 4.5 to 1 contrast with the composer",
  async ({ page }) => {
    const hintColor = await page
      .locator(".composer-hint")
      .evaluate((element) => getComputedStyle(element).color);
    const composerColor = await page
      .locator(".composer")
      .evaluate((element) => getComputedStyle(element).backgroundColor);
    const [light, dark] = [
      luminanceOf(hintColor),
      luminanceOf(composerColor),
    ].toSorted((a, b) => b - a) as [number, number];
    const ratio = (light + 0.05) / (dark + 0.05);
    expect(
      ratio,
      `the hint ${hintColor} on ${composerColor}`,
    ).toBeGreaterThanOrEqual(TEXT_MIN_RATIO);
  },
);
