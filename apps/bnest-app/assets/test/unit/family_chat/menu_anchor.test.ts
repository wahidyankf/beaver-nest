// @vitest-environment happy-dom
//
// Where the action menu sits, as arithmetic rather than as layout.
//
// Tech-doc 003's Responsive Behaviour table asks for a popover anchored to
// the message at and above 600px, and a sheet from the bottom edge below it.
// The sheet is the stylesheet's; the popover needs a position, and a position
// is a decision this layer can make and check without a layout engine.
// Whether the browser then paints it where the arithmetic says is FE_E2E's.

import { describe, expect, it } from "vitest";
import {
  anchorMenu,
  GAP,
  menuPlacement,
} from "../../../js/family_chat/menu_anchor.js";

const menu = { height: 100, width: 160 };
const viewport = { height: 900, width: 1440 };

function message(overrides: Record<string, number> = {}) {
  return { bottom: 350, left: 700, right: 1070, top: 270, ...overrides };
}

describe("menuPlacement", () => {
  it("sits just below the message it acts on", () => {
    expect(
      menuPlacement({ menu, message: message(), ownMessage: true, viewport })
        .top,
    ).toBe(350 + GAP);
  });

  it("aligns to the sending edge of an own message", () => {
    // Own messages hang off the right, and so does the control that opens
    // this menu; aligning the far edge keeps the two together.
    expect(
      menuPlacement({ menu, message: message(), ownMessage: true, viewport })
        .left,
    ).toBe(1070 - 160);
  });

  it("aligns to the left edge of another member's message", () => {
    expect(
      menuPlacement({ menu, message: message(), ownMessage: false, viewport })
        .left,
    ).toBe(700);
  });

  it("flips above the message when there is no room below", () => {
    const low = message({ bottom: 860, top: 780 });

    expect(
      menuPlacement({ menu, message: low, ownMessage: true, viewport }).top,
    ).toBe(780 - GAP - 100);
  });

  it("gives up the gap before it gives up a visible item", () => {
    // Neither side fits a menu this tall, so it settles at the lowest top
    // that still shows the last item -- nearer the message than the top of
    // the viewport would be, and with nothing cut off either way.
    const tall = { height: 800, width: 160 };
    const low = message({ bottom: 860, top: 780 });

    expect(
      menuPlacement({ menu: tall, message: low, ownMessage: true, viewport })
        .top,
    ).toBe(900 - 800 - GAP);
  });

  it("never runs off the left edge", () => {
    const nearLeft = message({ left: 4, right: 40 });

    expect(
      menuPlacement({ menu, message: nearLeft, ownMessage: true, viewport })
        .left,
    ).toBe(GAP);
  });

  it("never runs off the right edge", () => {
    const nearRight = message({ left: 1400, right: 1436 });

    expect(
      menuPlacement({ menu, message: nearRight, ownMessage: false, viewport })
        .left,
    ).toBe(1440 - 160 - GAP);
  });

  it("clamps rather than overflowing a viewport narrower than the menu", () => {
    const narrow = { height: 900, width: 100 };

    expect(
      menuPlacement({
        menu,
        message: message(),
        ownMessage: true,
        viewport: narrow,
      }).left,
    ).toBe(GAP);
  });
});

describe("anchorMenu", () => {
  // The placement has to survive a viewport that crosses 600px while the
  // menu is open -- a tablet rotating to portrait, which is exactly the
  // household surface. An inline `top`/`left` would beat the stylesheet's
  // sheet rule and strand the menu at stale desktop coordinates, so the
  // placement is published as custom properties and the cascade decides
  // which one applies.
  function room() {
    document.body.innerHTML = `
      <ol>
        <li data-role="family-chat-message" data-message-id="7"
            class="family-chat-message family-chat-message--own"></li>
      </ol>
      <div data-role="family-chat-message-actions"></div>`;
    const list = document.querySelector("ol") as HTMLElement;
    const host = document.querySelector(
      '[data-role="family-chat-message-actions"]',
    ) as HTMLElement;
    return { host, list };
  }

  it("publishes the placement as custom properties, not as top and left", () => {
    const { host, list } = room();

    anchorMenu(host, list, "7");

    expect(host.style.getPropertyValue("--fc-menu-top")).toMatch(/px$/u);
    expect(host.style.getPropertyValue("--fc-menu-left")).toMatch(/px$/u);
    expect(host.style.top).toBe("");
    expect(host.style.left).toBe("");
  });

  it("leaves the placement alone when the message is not rendered", () => {
    const { host, list } = room();

    anchorMenu(host, list, "does-not-exist");

    expect(host.style.getPropertyValue("--fc-menu-top")).toBe("");
  });
});
