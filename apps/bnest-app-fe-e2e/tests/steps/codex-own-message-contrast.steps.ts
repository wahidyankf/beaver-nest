import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The Show raw label and its focus ring on a visitor's dark bubble, measured on the computed colours of the real page
// (chat.feature, Rule "Own messages in the Codex chat"; ADR 005, decision 4).

const { Then } = createBdd();

type Channels = [number, number, number];

/** `#rrggbb` or `rgb(r, g, b)` as its three channels, for the contrast check. */
function channelsOf(colour: string): Channels {
  const hex = /^#([0-9a-f]{6})$/iu.exec(colour.trim());
  if (hex?.[1]) {
    const value = Number.parseInt(hex[1], 16);
    return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
  }
  const rgb = /^rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/u.exec(colour.trim());
  if (!rgb) throw new Error(`not a colour: ${colour}`);
  return [Number(rgb[1]), Number(rgb[2]), Number(rgb[3])];
}

/** The WCAG relative luminance of a colour given as channels. */
function luminanceOf([red, green, blue]: Channels): number {
  const [r, g, b] = [red, green, blue].map((channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  }) as Channels;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** The WCAG contrast ratio of two colours, from 1 to 21. */
function ratioOf(first: Channels, second: Channels): number {
  const [light, dark] = [luminanceOf(first), luminanceOf(second)].toSorted(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

Then(
  "the Show raw label is at least 4.5 to 1 against the visitor's bubble",
  async ({ page }) => {
    const colours = await page.evaluate(() => {
      const toggle = document.querySelector(".own-raw-toggle");
      const bubble = toggle?.closest(".message-visitor");
      if (!toggle || !bubble) return null;
      return {
        label: getComputedStyle(toggle).color,
        fill: getComputedStyle(bubble).backgroundColor,
      };
    });
    expect(colours, "no Show raw control on a visitor bubble").not.toBeNull();
    const ratio = ratioOf(
      channelsOf(colours?.label ?? ""),
      channelsOf(colours?.fill ?? ""),
    );
    expect(
      ratio,
      `the Show raw label is ${ratio.toFixed(2)} to 1`,
    ).toBeGreaterThanOrEqual(4.5);
  },
);

Then(
  "the Show raw focus ring is at least 3 to 1 against the visitor's bubble",
  async ({ page }) => {
    // Keyboard focus reaches the toggle by Tab, so the painted focus ring is the one a keyboard user sees.
    const toggle = page.locator(".own-raw-toggle").first();
    for (let press = 0; press < 60; press += 1) {
      // eslint-disable-next-line no-await-in-loop -- each Tab press must land before the focus is read.
      const focused = await toggle.evaluate(
        (element) => element === document.activeElement,
      );
      if (focused) break;
      // eslint-disable-next-line no-await-in-loop -- the same reason.
      await page.keyboard.press("Tab");
    }
    const ring = await toggle.evaluate((element) => ({
      visible: element.matches(":focus-visible"),
      style: getComputedStyle(element).outlineStyle,
      colour: getComputedStyle(element).outlineColor,
    }));
    expect(ring.visible, "the Show raw toggle has no keyboard focus").toBe(
      true,
    );
    expect(ring.style, "the Show raw focus ring is not painted").not.toBe(
      "none",
    );
    const fill = await page.evaluate(() => {
      const bubble = document.querySelector(".message-visitor");
      return bubble ? getComputedStyle(bubble).backgroundColor : null;
    });
    expect(fill, "no visitor bubble on the page").not.toBeNull();
    const ratio = ratioOf(channelsOf(ring.colour), channelsOf(fill ?? ""));
    expect(
      ratio,
      `the Show raw focus ring is ${ratio.toFixed(2)} to 1`,
    ).toBeGreaterThanOrEqual(3);
  },
);
