import { expect, type Locator } from "@playwright/test";
import { createBdd } from "playwright-bdd";

import { TEXTAREA } from "../support/chat-ui-steps";

const { Then } = createBdd();

// The look of the two message boxes (chat.feature, Rule "Codex message box and Send button look and line up as one
// composer"; family_chat.feature, Rule "Family Chat message box reads clearly"). Every value is read from the rendered
// page, so these steps prove what a visitor sees, not what the stylesheet says.

const SEND = "#chat-composer-form .send-button";
const FAMILY_BOX = "#family-chat-message-input";
const FAMILY_SEND = ".family-chat-send";

/** The channels of a computed `rgb()` or `rgba()` colour. */
function channelsOf(css: string): [number, number, number] {
  const match = /rgba?\(([^)]+)\)/u.exec(css);
  if (!match?.[1]) throw new Error(`not an rgb colour: ${css}`);
  const [red, green, blue] = match[1].split(/[\s,/]+/u).map(Number);
  return [red ?? 0, green ?? 0, blue ?? 0];
}

function luminanceOf(css: string): number {
  const [red, green, blue] = channelsOf(css).map((value) => {
    const channel = value / 255;
    return channel <= 0.03928
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (red ?? 0) + 0.7152 * (green ?? 0) + 0.0722 * (blue ?? 0);
}

/** The WCAG contrast ratio of two computed colours, from 1 to 21. */
function contrastOf(first: string, second: string): number {
  const [light, dark] = [luminanceOf(first), luminanceOf(second)].toSorted(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

Then(
  "the Send button's top and bottom edges are within 1 pixel of the message box's",
  async ({ page }) => {
    const box = await page.locator(TEXTAREA).boundingBox();
    const send = await page.locator(SEND).boundingBox();
    if (!box || !send)
      throw new Error("the message box or Send is not rendered");
    expect(Math.abs(send.y - box.y), "top edges").toBeLessThanOrEqual(1);
    expect(
      Math.abs(send.y + send.height - (box.y + box.height)),
      "bottom edges",
    ).toBeLessThanOrEqual(1);
  },
);

Then("the Codex message box has no resize handle", async ({ page }) => {
  const resize = await page
    .locator(TEXTAREA)
    .evaluate((element) => getComputedStyle(element).resize);
  expect(resize).toBe("none");
});

Then(
  "the Codex message box placeholder has at least 4.5 to 1 contrast with the box",
  async ({ page }) => {
    const colours = await page.locator(TEXTAREA).evaluate((element) => ({
      placeholder: getComputedStyle(element, "::placeholder").color,
      background: getComputedStyle(element).backgroundColor,
    }));
    expect(
      contrastOf(colours.placeholder, colours.background),
      `${colours.placeholder} on ${colours.background}`,
    ).toBeGreaterThanOrEqual(4.5);
  },
);

Then(
  "the Codex Send button has the same background as the Family Chat Send button",
  async ({ page }) => {
    const codex = await page
      .locator(SEND)
      .evaluate((element) => getComputedStyle(element).backgroundColor);
    // app.css serves both rooms, so the Family Chat Send rule is on this page. A probe button takes its style.
    const family = await page.evaluate(() => {
      const probe = document.createElement("button");
      probe.className = "family-chat-send";
      document.body.append(probe);
      const colour = getComputedStyle(probe).backgroundColor;
      probe.remove();
      return colour;
    });
    expect(codex).toBe(family);
  },
);

Then(
  "the Codex Send button text meets the contrast target",
  async ({ page }) => {
    const colours = await page.locator(SEND).evaluate((element) => {
      const style = getComputedStyle(element);
      return { text: style.color, background: style.backgroundColor };
    });
    expect(
      contrastOf(colours.text, colours.background),
      `${colours.text} on ${colours.background}`,
    ).toBeGreaterThanOrEqual(4.5);
  },
);

/** The four computed corner radii of an element, in top-left, top-right, bottom-right, bottom-left order. */
function cornerRadiiOf(locator: Locator): Promise<string[]> {
  return locator.evaluate((element) => {
    const style = getComputedStyle(element);
    return [
      style.borderTopLeftRadius,
      style.borderTopRightRadius,
      style.borderBottomRightRadius,
      style.borderBottomLeftRadius,
    ];
  });
}

Then(
  "the Family Chat Send button has four equal corner radii",
  async ({ page }) => {
    const corners = await cornerRadiiOf(page.locator(FAMILY_SEND));
    expect(new Set(corners).size, corners.join(" ")).toBe(1);
  },
);

Then("the Codex Send button has four equal corner radii", async ({ page }) => {
  const corners = await cornerRadiiOf(page.locator(SEND));
  expect(new Set(corners).size, corners.join(" ")).toBe(1);
});

Then(
  "the Codex Send button has the same corner radius as the Family Chat Send button",
  async ({ page }) => {
    const codex = await cornerRadiiOf(page.locator(SEND));
    // app.css serves both rooms, so the Family Chat Send rule is on this page. A probe button takes its style.
    const family = await page.evaluate(() => {
      const probe = document.createElement("button");
      probe.className = "family-chat-send";
      document.body.append(probe);
      const style = getComputedStyle(probe);
      const corners = [
        style.borderTopLeftRadius,
        style.borderTopRightRadius,
        style.borderBottomRightRadius,
        style.borderBottomLeftRadius,
      ];
      probe.remove();
      return corners;
    });
    expect(codex).toEqual(family);
  },
);

Then(
  "the Family Chat message box is named {string}",
  async ({ page }, name: string) => {
    await expect(
      page.getByRole("textbox", { name, exact: true }),
    ).toBeAttached();
  },
);

Then(
  "the message box placeholder has at least 4.5 to 1 contrast with the box",
  async ({ page }) => {
    const colours = await page.locator(FAMILY_BOX).evaluate((element) => ({
      placeholder: getComputedStyle(element, "::placeholder").color,
      background: getComputedStyle(element).backgroundColor,
    }));
    expect(
      contrastOf(colours.placeholder, colours.background),
      `${colours.placeholder} on ${colours.background}`,
    ).toBeGreaterThanOrEqual(4.5);
  },
);
