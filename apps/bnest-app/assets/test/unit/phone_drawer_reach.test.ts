// @vitest-environment happy-dom
//
// The unit layer of the chat.feature scenario "A phone visitor reaches the newest message and the composer from the
// drawer". The scenario is tagged @integration-exempt, because the drawer, its scrim and the scrolled transcript are
// browser results. The drawer's open state is client-side, so its open step runs on the real drawer module and the
// real `installChatControls` listeners, as chat_controls.test.ts does. The layout Then steps check the declared values
// the shipped stylesheet gives a phone (390 by 844 CSS pixels, a touch pointer) through support/shipped_css. The
// rendered sizes, positions and scroll results are measured in Chromium by bnest-app-fe-e2e.

import { readFileSync } from "node:fs";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { installChatControls } from "../../js/chat_controls.js";
import { drawerIsOpen } from "../../js/conversation_drawer.js";
import { CODEX_TEMPLATE } from "../behaviour/support/send_hint";
import {
  declarationsFor,
  lengthPx,
  resolveVars,
  type Environment,
} from "../support/shipped_css";

const PHONE: Environment = { width: 390, height: 844, coarse: true };

// The Chats toggle, its scrim and the conversation drawer, as chat_live.ex renders them.
const PHONE_PAGE = `
  <button type="button" data-role="conversations-toggle" aria-expanded="false" aria-controls="conversation-drawer">Chats</button>
  <div data-role="conversation-scrim" class="conversation-scrim"></div>
  <aside data-role="conversation-rail" class="conversation-rail" id="conversation-drawer" aria-label="Chats">
    <button type="button" data-role="conversation-close">Close</button>
    <button type="button" data-role="new-conversation">New chat</button>
  </aside>`;

function el<T extends HTMLElement = HTMLElement>(selector: string): T {
  const found = document.querySelector<T>(selector);
  if (!found) throw new Error(`missing ${selector}`);
  return found;
}

function click(selector: string) {
  el(selector).dispatchEvent(
    new MouseEvent("click", { bubbles: true, cancelable: true }),
  );
}

/** The place of a fragment in chat_live.ex, failing when the fragment is missing. */
function templateIndex(template: string, fragment: string): number {
  const index = template.indexOf(fragment);
  expect(index, `chat_live.ex has no ${fragment}`).toBeGreaterThanOrEqual(0);
  return index;
}

describe("A phone visitor reaches the newest message and the composer from the drawer", () => {
  beforeAll(() => {
    installChatControls(document);
  });

  afterAll(() => {
    document.body.innerHTML = "";
  });

  beforeEach(() => {
    document.body.innerHTML = PHONE_PAGE;
  });

  // @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A phone visitor reaches the newest message and the composer from the drawer
  it("opens the drawer from the Chats toggle, keeps the composer at the bottom, and lets the conversation scroll", () => {
    // When the visitor opens the conversation drawer; Then the conversation drawer is open.
    click("[data-role='conversations-toggle']");
    expect(drawerIsOpen(document), "the drawer did not open").toBe(true);
    expect(
      el("[data-role='conversations-toggle']").getAttribute("aria-expanded"),
    ).toBe("true");
    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(true);

    // Then the Chats toggle is at least 44 pixels across and tall. The unit layer checks the declared size of the
    // phone rule, 2.75rem (44 pixels); the rendered size is measured in Chromium by bnest-app-fe-e2e.
    const toggle = declarationsFor(".conversations-toggle", PHONE);
    expect(toggle["display"], "the Chats toggle is hidden on a phone").toBe(
      "inline-flex",
    );
    expect(
      lengthPx(resolveVars(toggle["min-width"] ?? ""), PHONE),
      ".conversations-toggle is narrower than 2.75rem on a phone",
    ).toBeGreaterThanOrEqual(lengthPx("2.75rem", PHONE));
    expect(
      lengthPx(resolveVars(toggle["min-height"] ?? ""), PHONE),
      ".conversations-toggle is shorter than 2.75rem on a phone",
    ).toBeGreaterThanOrEqual(lengthPx("2.75rem", PHONE));

    // Then the newest message is fully above the composer, and the Codex composer is at the bottom of the screen.
    // Whether the newest message sits fully above the composer on screen is measured in Chromium by bnest-app-fe-e2e.
    // Here the composer stays in the flow, and the header, conversation and composer come in that order in chat_live.ex.
    const template = readFileSync(CODEX_TEMPLATE, "utf8");
    const header = templateIndex(template, 'class="chat-header"');
    const conversation = templateIndex(template, 'id="chat-conversation"');
    const composer = templateIndex(template, 'class="composer"');
    expect(
      header < conversation && conversation < composer,
      "the header, the conversation and the composer are not in that order",
    ).toBe(true);
    const composerPosition = declarationsFor(".composer", PHONE)["position"];
    expect(
      ["absolute", "fixed"],
      "the composer is taken out of the flow, so it can cover the newest message",
    ).not.toContain(composerPosition ?? "");
    expect(
      declarationsFor(".chat-panel", PHONE)["flex-direction"],
      "the panel does not stack the conversation above the composer",
    ).toBe("column");
    expect(
      declarationsFor(".composer", PHONE)["flex-shrink"],
      "the composer can shrink below its height",
    ).toBe("0");

    // Then the page does not scroll. The panel's height is the window's height on a phone, and the panel clips.
    // The rendered page is measured in Chromium by bnest-app-fe-e2e.
    const panel = declarationsFor(".chat-panel", PHONE);
    expect(
      lengthPx(resolveVars(panel["height"] ?? ""), PHONE),
      ".chat-panel is not the window's height",
    ).toBe(PHONE.height);
    expect(panel["overflow"], ".chat-panel lets the page scroll").toBe(
      "hidden",
    );
    expect(
      panel["min-height"],
      ".chat-panel can be taller than the window",
    ).toBe("0");

    // When the visitor scrolls the conversation to the newest message. The unit layer checks that the conversation
    // declares a scrolling overflow-y; the scroll position reached is measured in Chromium by bnest-app-fe-e2e.
    expect(
      ["auto", "scroll"],
      ".conversation does not allow scrolling its messages",
    ).toContain(declarationsFor(".conversation", PHONE)["overflow-y"] ?? "");
  });
});
