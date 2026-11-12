// Every inline element a Markdown body renders inside an own (dark) message bubble must be legible on the bubble's
// fill (WCAG 1.4.3, 4.5:1 for body text). A rule that colours an element with a light-bubble literal instead of a
// token turns the text into the fill itself: `.markdown-body del` did so, and its strike-through text was invisible.
// The colours are read from the shipped stylesheets through the shared helper, not copied here.

import { describe, expect, it } from "vitest";
import {
  ownBubbleFill,
  ownInlineContrast,
  ownTextColour,
} from "../../support/own_bubble";

const MIN_BODY_CONTRAST = 4.5;

// The inline elements a rendered Markdown body can contain (chat_markdown.ex): links, inline code, strike-through,
// emphasis, quoted text, and table cells. Each is measured where it sits in the own bubble.
const INLINE_ELEMENTS = [
  ".markdown-body a",
  ".markdown-body code",
  ".markdown-body del",
  ".markdown-body em",
  ".markdown-body strong",
  ".markdown-body blockquote",
  ".markdown-body td",
  ".markdown-body th",
];

describe("the inline elements of a Markdown body inside an own bubble", () => {
  it("resolves the own fill from the bubble's surface token", () => {
    expect(ownBubbleFill()).toMatch(/^#[0-9a-f]{6}$/iu);
  });

  it.each(INLINE_ELEMENTS)(
    "keeps %s at body contrast on the own fill",
    (element) => {
      expect(ownTextColour(element)).toMatch(/^#[0-9a-f]{6}$/iu);
      const ratio = ownInlineContrast(element);

      expect(
        ratio,
        `${element} is ${ratio.toFixed(2)}:1 on the own fill`,
      ).toBeGreaterThanOrEqual(MIN_BODY_CONTRAST);
    },
  );
});
