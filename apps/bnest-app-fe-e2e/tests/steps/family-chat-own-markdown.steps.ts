import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The contrast of inline Markdown in the visitor's own bubble (family_chat.feature, Rule "Formatted messages"). Split from
// family-chat-markdown.steps.ts to stay under its line limit.

const { Then } = createBdd();

const OWN_INLINE_TAGS: readonly (readonly [label: string, tag: string])[] = [
  ["the struck text", "del"],
  ["the link", "a"],
  ["the inline code", "code"],
  ["the quote", "blockquote"],
  ["the table cell", "td"],
];

/** The WCAG relative luminance of an `[r, g, b]` colour with 0 to 255 channels. */
function luminanceOf([
  red = 0,
  green = 0,
  blue = 0,
]: readonly number[]): number {
  const [r, g, b] = [red, green, blue].map((channel) => {
    const scaled = channel / 255;
    return scaled <= 0.03928
      ? scaled / 12.92
      : ((scaled + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (r ?? 0) + 0.7152 * (g ?? 0) + 0.0722 * (b ?? 0);
}

Then(
  "the struck text, the link, the inline code, the quote and the table cell each have a contrast ratio of at least 4.5 to 1 on my own bubble",
  async ({ page }) => {
    // The colours are the rendered ones: each element's computed text colour, and its background over the own bubble's
    // fill (the inline code has a translucent background, so it is blended onto the fill first).
    const own = page.locator(".family-chat-message--own").last();
    await expect(
      own.locator(".markdown-body del"),
      "the struck text is rendered",
    ).toHaveCount(1);
    // The browser-side callback is serialised, so each colour is read from its computed value inline.
    const measured = await own.evaluate((message, tags) => {
      const bubble = message.querySelector(".family-chat-message-bubble");
      if (bubble === null) throw new Error("the own message has no bubble");
      const fill = (
        getComputedStyle(bubble).backgroundColor.match(/[\d.]+/gu) ?? []
      )
        .map(Number)
        .slice(0, 3);
      return tags.map(([label, tag]) => {
        const element = message.querySelector(`.markdown-body ${tag}`);
        if (element === null)
          return { label, text: [] as number[], background: [] as number[] };
        const style = getComputedStyle(element);
        const painted = (style.backgroundColor.match(/[\d.]+/gu) ?? []).map(
          Number,
        );
        const alpha = painted.length === 4 ? (painted[3] ?? 1) : 1;
        const background = [0, 1, 2].map(
          (index) =>
            alpha * (painted[index] ?? 0) + (1 - alpha) * (fill[index] ?? 0),
        );
        const text = (style.color.match(/[\d.]+/gu) ?? [])
          .map(Number)
          .slice(0, 3);
        return { label, text, background };
      });
    }, OWN_INLINE_TAGS);
    for (const { label, text, background } of measured) {
      expect(text.length, `${label} is not rendered`).toBe(3);
      const textLuminance = luminanceOf(text);
      const backgroundLuminance = luminanceOf(background);
      const ratio =
        (Math.max(textLuminance, backgroundLuminance) + 0.05) /
        (Math.min(textLuminance, backgroundLuminance) + 0.05);
      const shown = background.map((value) => Math.round(value));
      expect(
        ratio,
        `${label} is ${ratio.toFixed(2)}:1 on the own bubble (${text} on ${shown})`,
      ).toBeGreaterThanOrEqual(4.5);
    }
  },
);
