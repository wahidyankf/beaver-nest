// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/chat_controls.js` (ADR 005, decisions 2 to 4): the options panel, the Clear chat
// confirmation and its focus, Escape, and the raw or rendered view of a visitor message. The listeners are delegated on
// the document, so they are installed once and each test rebuilds only the page markup.

import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  installChatControls,
  keepOptionsState,
} from "../../js/chat_controls.js";

const CODEX_PAGE = `
  <button type="button" data-role="chat-options-toggle" aria-expanded="false">Options</button>
  <div data-role="chat-options" class="chat-options"><p>Options body</p></div>
  <div data-role="clear-chat-group" class="clear-chat">
    <button type="button" data-role="clear-chat" aria-expanded="false">Clear chat</button>
    <div data-role="clear-chat-confirm" role="alertdialog" hidden>
      <button type="button" data-role="clear-chat-cancel">Cancel</button>
      <button type="button" data-role="clear-chat-yes">Yes, delete</button>
    </div>
  </div>
  <div data-role="own-message" data-view="rendered">
    <div data-role="markdown-body">Rendered</div>
    <div data-role="user-message-raw">Raw text</div>
    <button type="button" data-role="raw-toggle">Show raw</button>
  </div>`;

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

function pressKey(selector: string, key: string) {
  el(selector).dispatchEvent(
    new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
  );
}

describe("installChatControls", () => {
  beforeAll(() => {
    installChatControls(document);
  });

  afterAll(() => {
    document.body.innerHTML = "";
  });

  beforeEach(() => {
    document.body.innerHTML = CODEX_PAGE;
  });

  describe("options panel", () => {
    it("opens and closes the panel and keeps aria-expanded in step", () => {
      click("[data-role='chat-options-toggle']");
      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(true);
      expect(
        el("[data-role='chat-options-toggle']").getAttribute("aria-expanded"),
      ).toBe("true");

      click("[data-role='chat-options-toggle']");
      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(false);
      expect(
        el("[data-role='chat-options-toggle']").getAttribute("aria-expanded"),
      ).toBe("false");
    });

    it("a tap outside the open panel closes it", () => {
      click("[data-role='chat-options-toggle']");
      document.body.insertAdjacentHTML(
        "beforeend",
        "<p data-role='conversation'>Conversation</p>",
      );
      click("[data-role='conversation']");

      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(false);
      expect(
        el("[data-role='chat-options-toggle']").getAttribute("aria-expanded"),
      ).toBe("false");
    });

    it("a tap inside the open panel leaves it open", () => {
      click("[data-role='chat-options-toggle']");
      click("[data-role='chat-options'] p");

      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(true);
    });

    it("Escape from the message box closes the panel and leaves focus in the message box", () => {
      click("[data-role='chat-options-toggle']");
      const box = document.createElement("textarea");
      box.setAttribute("data-role", "chat-composer");
      document.body.appendChild(box);
      box.focus();
      pressKey("[data-role='chat-composer']", "Escape");

      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(false);
      expect(document.activeElement).toBe(box);
    });

    it("Escape closes an open panel, returns focus to its toggle, and stops the default", () => {
      click("[data-role='chat-options-toggle']");
      const escape = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      el("[data-role='chat-options-toggle']").dispatchEvent(escape);

      expect(
        el("[data-role='chat-options']").classList.contains("is-open"),
      ).toBe(false);
      expect(escape.defaultPrevented).toBe(true);
      expect(document.activeElement).toBe(
        el("[data-role='chat-options-toggle']"),
      );
    });

    it("Escape does nothing when the panel is already closed", () => {
      const escape = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      el("[data-role='chat-options-toggle']").dispatchEvent(escape);

      expect(escape.defaultPrevented).toBe(false);
    });
  });

  describe("Clear chat confirmation", () => {
    it("opens the confirmation and moves focus to Cancel, the safe choice", () => {
      click("[data-role='clear-chat']");

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(false);
      expect(el("[data-role='clear-chat']").getAttribute("aria-expanded")).toBe(
        "true",
      );
      expect(document.activeElement).toBe(
        el("[data-role='clear-chat-cancel']"),
      );
    });

    it("Cancel closes the confirmation and returns focus to the Clear chat button", () => {
      click("[data-role='clear-chat']");
      click("[data-role='clear-chat-cancel']");

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
      expect(el("[data-role='clear-chat']").getAttribute("aria-expanded")).toBe(
        "false",
      );
      expect(document.activeElement).toBe(el("[data-role='clear-chat']"));
    });

    it("Yes, delete closes the confirmation so the LiveView clear event can run", () => {
      click("[data-role='clear-chat']");
      click("[data-role='clear-chat-yes']");

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
    });

    it("Escape closes an open confirmation, keeps the conversation, and stops the default", () => {
      click("[data-role='clear-chat']");
      el("[data-role='clear-chat-cancel']").focus();

      const escape = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      el("[data-role='clear-chat-cancel']").dispatchEvent(escape);

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
      expect(escape.defaultPrevented).toBe(true);
      expect(document.activeElement).toBe(el("[data-role='clear-chat']"));
    });

    it("Escape does nothing when the confirmation is already closed", () => {
      const escape = new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      });
      el("[data-role='clear-chat']").dispatchEvent(escape);

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
      expect(escape.defaultPrevented).toBe(false);
    });

    it("other keys leave an open confirmation open", () => {
      click("[data-role='clear-chat']");
      pressKey("[data-role='clear-chat-cancel']", "Enter");

      expect(el("[data-role='clear-chat-confirm']").hidden).toBe(false);
    });
  });

  describe("raw or rendered view of a visitor message", () => {
    it("switches a Markdown message to its raw text and back", () => {
      const message = el("[data-role='own-message']");

      click("[data-role='raw-toggle']");
      expect(message.dataset["view"]).toBe("raw");

      click("[data-role='raw-toggle']");
      expect(message.dataset["view"]).toBe("rendered");
    });

    it("toggles only the message that owns the pressed button", () => {
      document.body.insertAdjacentHTML(
        "beforeend",
        `<div data-role="own-message" data-view="rendered" id="second">
           <button type="button" data-role="raw-toggle">Show raw</button>
         </div>`,
      );

      click("#second [data-role='raw-toggle']");

      expect(el("#second").dataset["view"]).toBe("raw");
      expect(el("[data-role='own-message']").dataset["view"]).toBe("rendered");
    });
  });

  // LiveView rebuilds the server-rendered attributes on every patch, which would close an open panel. The DOM hook
  // carries the open state from the old element to the new one (app.js, LiveSocket `dom.onBeforeElUpdated`).
  describe("state kept across a LiveView patch", () => {
    function patched(open: boolean, expanded: string) {
      const panel = document.createElement("div");
      panel.setAttribute("data-role", "chat-options");
      panel.className = open ? "chat-actions is-open" : "chat-actions";
      const toggle = document.createElement("button");
      toggle.setAttribute("data-role", "chat-options-toggle");
      toggle.setAttribute("aria-expanded", expanded);
      return { panel, toggle };
    }

    it("keeps an open panel open after a patch that rendered it closed", () => {
      const from = patched(true, "true");
      const to = patched(false, "false");

      keepOptionsState(from.panel, to.panel);

      expect(to.panel.classList.contains("is-open")).toBe(true);
    });

    it("keeps the toggle's aria-expanded in step with the open panel", () => {
      const from = patched(true, "true");
      const to = patched(false, "false");

      keepOptionsState(from.toggle, to.toggle);

      expect(to.toggle.getAttribute("aria-expanded")).toBe("true");
    });

    it("leaves a closed panel closed", () => {
      const from = patched(false, "false");
      const to = patched(false, "false");

      keepOptionsState(from.panel, to.panel);
      keepOptionsState(from.toggle, to.toggle);

      expect(to.panel.classList.contains("is-open")).toBe(false);
      expect(to.toggle.getAttribute("aria-expanded")).toBe("false");
    });

    it("ignores elements that carry no options state", () => {
      const from = document.createElement("p");
      const to = document.createElement("p");
      to.textContent = "Patched";

      keepOptionsState(from, to);

      expect(to.classList.contains("is-open")).toBe(false);
      expect(to.hasAttribute("aria-expanded")).toBe(false);
    });
  });
});

// --- The Clear chat confirmation with the options panel (round 3, F1) ---------------------------------------------

function openConfirmation() {
  click("[data-role='chat-options-toggle']");
  click("[data-role='clear-chat']");
  expect(el("[data-role='clear-chat-confirm']").hidden).toBe(false);
}

function tapOutside() {
  document.body.insertAdjacentHTML(
    "beforeend",
    "<p data-role='conversation'>Conversation</p>",
  );
  click("[data-role='conversation']");
}

// The Clear chat group sits inside the options panel, as in chat_live.ex. A tap on it is therefore not a tap outside.
const PANEL_PAGE = `
  <button type="button" data-role="chat-options-toggle" aria-expanded="false">Options</button>
  <div data-role="chat-options" class="chat-options">
    <div data-role="clear-chat-group" class="clear-chat" phx-update="ignore">
      <button type="button" data-role="clear-chat" aria-expanded="false">Clear chat</button>
      <div data-role="clear-chat-confirm" role="alertdialog" hidden>
        <button type="button" data-role="clear-chat-cancel">Cancel</button>
        <button type="button" data-role="clear-chat-yes">Yes, delete</button>
      </div>
    </div>
  </div>
  <div data-role="own-message" data-view="rendered">
    <div data-role="markdown-body">Rendered</div>
  </div>`;

describe("the Clear chat confirmation follows the options panel", () => {
  beforeEach(() => {
    document.body.innerHTML = PANEL_PAGE;
  });

  it("a tap outside the panel closes the panel and the confirmation together", () => {
    openConfirmation();
    tapOutside();

    expect(el("[data-role='chat-options']").classList.contains("is-open")).toBe(
      false,
    );
    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
  });

  it("the toggle closing the panel also closes the confirmation", () => {
    openConfirmation();
    click("[data-role='chat-options-toggle']");

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
  });

  it("reopening the panel shows no stale confirmation", () => {
    openConfirmation();
    tapOutside();
    click("[data-role='chat-options-toggle']");

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
  });

  it("Escape closes an open confirmation even when focus is outside its group", () => {
    document.body.insertAdjacentHTML(
      "beforeend",
      "<button type='button' data-role='outside'>Outside</button>",
    );
    const outside = el("[data-role='outside']");
    outside.focus();
    // Focus leaving the group closes the confirmation first (see the focusout test below). This checks the keyboard
    // fallback for a confirmation that is still open while focus sits elsewhere.
    el("[data-role='clear-chat-confirm']").hidden = false;
    const escape = new KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    });
    outside.dispatchEvent(escape);

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
    expect(escape.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(outside);
  });

  it("focus leaving the confirmation group closes it without moving focus", () => {
    openConfirmation();
    document.body.insertAdjacentHTML(
      "beforeend",
      "<button type='button' data-role='outside'>Outside</button>",
    );
    const outside = el("[data-role='outside']");
    outside.focus();
    el("[data-role='clear-chat-cancel']").dispatchEvent(
      new FocusEvent("focusout", { bubbles: true, relatedTarget: outside }),
    );

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
    expect(document.activeElement).toBe(outside);
  });

  it("focus moving between the confirmation's own buttons keeps it open", () => {
    openConfirmation();
    el("[data-role='clear-chat-cancel']").dispatchEvent(
      new FocusEvent("focusout", {
        bubbles: true,
        relatedTarget: el("[data-role='clear-chat-yes']"),
      }),
    );

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(false);
  });

  it("a press that starts on Yes keeps the confirmation open when the browser releases focus", () => {
    openConfirmation();
    const yes = el("[data-role='clear-chat-yes']");
    // Safari does not focus a button on click, so the focusout of this press has no new target.
    yes.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    el("[data-role='clear-chat-cancel']").dispatchEvent(
      new FocusEvent("focusout", { bubbles: true, relatedTarget: null }),
    );

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(false);
    yes.dispatchEvent(new Event("pointerup", { bubbles: true }));
  });

  it("a press that starts outside the group still closes the confirmation when focus is released", () => {
    openConfirmation();
    document.body.insertAdjacentHTML(
      "beforeend",
      "<p data-role='conversation'>Conversation</p>",
    );
    el("[data-role='conversation']").dispatchEvent(
      new Event("pointerdown", { bubbles: true }),
    );
    el("[data-role='clear-chat-cancel']").dispatchEvent(
      new FocusEvent("focusout", { bubbles: true, relatedTarget: null }),
    );

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
    el("[data-role='conversation']").dispatchEvent(
      new Event("pointerup", { bubbles: true }),
    );
  });
});
