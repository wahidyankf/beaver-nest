// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/chat_controls.js` (ADR 005, decisions 2 to 4): the options panel, the Clear chat
// confirmation and its focus, Escape, and the raw or rendered view of a visitor message. The listeners are delegated on
// the document, so they are installed once and each test rebuilds only the page markup.

import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { installChatControls, keepOptionsState } from "../../js/chat_controls.js";
import {
  keepConversationDrawerState,
  setConversationDrawer,
} from "../../js/conversation_drawer.js";

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

// --- The conversation drawer on a phone --------------------------------------------------------------------------

// The drawer replaces the rail strip below the desktop width: the Chats toggle opens it, the scrim, the close button,
// a conversation entry or Escape closes it, and the desktop width closes it without moving focus.
const DRAWER_PAGE = `
  <button type="button" data-role="conversations-toggle" aria-expanded="false" aria-controls="conversation-drawer">Chats</button>
  <div data-role="conversation-scrim" class="conversation-scrim"></div>
  <aside data-role="conversation-rail" class="conversation-rail" aria-label="Chats">
    <button type="button" data-role="conversation-close">Close</button>
    <button type="button" data-role="new-conversation">New chat</button>
    <ul>
      <li data-role="conversation-item">
        <a href="/chat?conversation=abc" data-role="select-conversation">First</a>
        <button type="button" data-role="rename-toggle" aria-expanded="false">Rename</button>
      </li>
    </ul>
  </aside>
  <div data-role="clear-chat-group" class="clear-chat">
    <button type="button" data-role="clear-chat" aria-expanded="false">Clear chat</button>
    <div data-role="clear-chat-confirm" role="alertdialog" hidden>
      <button type="button" data-role="clear-chat-cancel">Cancel</button>
      <button type="button" data-role="clear-chat-yes">Yes, delete</button>
    </div>
  </div>
  <textarea data-role="chat-composer"></textarea>`;

describe("the conversation drawer", () => {
  beforeEach(() => {
    document.body.innerHTML = DRAWER_PAGE;
  });

  it("the Chats toggle opens the drawer, reports it open, and moves focus inside", () => {
    click("[data-role='conversations-toggle']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(true);
    expect(
      el("[data-role='conversations-toggle']").getAttribute("aria-expanded"),
    ).toBe("true");
    expect(
      el("[data-role='conversation-scrim']").classList.contains("is-open"),
    ).toBe(true);
    expect(document.activeElement).toBe(
      el("[data-role='conversation-close']"),
    );
  });

  it("the Chats toggle closes the drawer and returns focus to the toggle", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='conversations-toggle']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(
      el("[data-role='conversations-toggle']").getAttribute("aria-expanded"),
    ).toBe("false");
    expect(document.activeElement).toBe(
      el("[data-role='conversations-toggle']"),
    );
  });

  it("the close button closes the drawer and returns focus to the toggle", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='conversation-close']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(document.activeElement).toBe(
      el("[data-role='conversations-toggle']"),
    );
  });

  it("a tap on the scrim closes the drawer", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='conversation-scrim']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(document.activeElement).toBe(
      el("[data-role='conversations-toggle']"),
    );
  });

  it("opening a conversation closes the drawer and returns focus to the toggle", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='select-conversation']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(document.activeElement).toBe(
      el("[data-role='conversations-toggle']"),
    );
  });

  it("starting a new chat closes the drawer", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='new-conversation']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
  });

  it("the rename toggle leaves the drawer open", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='rename-toggle']");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(true);
  });

  it("Escape from inside the drawer closes it, returns focus to the toggle, and stops the default", () => {
    click("[data-role='conversations-toggle']");
    el("[data-role='conversation-close']").focus();
    const escape = new KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    });
    el("[data-role='conversation-close']").dispatchEvent(escape);

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(escape.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(
      el("[data-role='conversations-toggle']"),
    );
  });

  it("Escape from the message box closes the drawer but leaves focus in the message box", () => {
    click("[data-role='conversations-toggle']");
    const box = el("[data-role='chat-composer']");
    box.focus();
    pressKey("[data-role='chat-composer']", "Escape");

    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(false);
    expect(document.activeElement).toBe(box);
  });

  it("Escape does nothing when the drawer is already closed", () => {
    const escape = new KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    });
    el("[data-role='conversations-toggle']").dispatchEvent(escape);

    expect(escape.defaultPrevented).toBe(false);
  });

  it("Escape closes an open confirmation before the drawer", () => {
    click("[data-role='conversations-toggle']");
    click("[data-role='clear-chat']");
    pressKey("[data-role='clear-chat-cancel']", "Escape");

    expect(el("[data-role='clear-chat-confirm']").hidden).toBe(true);
    expect(
      el("[data-role='conversation-rail']").classList.contains("is-open"),
    ).toBe(true);
  });

  it("a LiveView patch keeps the open drawer and its toggle in step", () => {
    click("[data-role='conversations-toggle']");
    const drawer = el("[data-role='conversation-rail']");
    const replacement = drawer.cloneNode(false) as HTMLElement;
    keepConversationDrawerState(drawer, replacement);

    expect(replacement.classList.contains("is-open")).toBe(true);

    const toggle = el("[data-role='conversations-toggle']");
    const toggleReplacement = toggle.cloneNode(false) as HTMLElement;
    keepConversationDrawerState(toggle, toggleReplacement);

    expect(toggleReplacement.getAttribute("aria-expanded")).toBe("true");
  });

  it("a LiveView patch leaves a closed drawer closed", () => {
    const drawer = el("[data-role='conversation-rail']");
    const replacement = drawer.cloneNode(false) as HTMLElement;
    keepConversationDrawerState(drawer, replacement);

    expect(replacement.classList.contains("is-open")).toBe(false);
  });

  it("reaching the desktop width closes the drawer through its media query", () => {
    const toggle = document.createElement("button");
    toggle.setAttribute("data-role", "conversations-toggle");
    toggle.setAttribute("aria-expanded", "false");
    const scrim = document.createElement("div");
    scrim.setAttribute("data-role", "conversation-scrim");
    const close = document.createElement("button");
    close.setAttribute("data-role", "conversation-close");
    const drawer = document.createElement("aside");
    drawer.setAttribute("data-role", "conversation-rail");
    drawer.appendChild(close);
    const listenerHost: { current: (() => void) | null } = { current: null };
    const query = {
      matches: false,
      addEventListener: (...args: unknown[]) => {
        listenerHost.current = args[1] as () => void;
      },
    };
    let observedQuery = "";
    const fakeDocument = {
      defaultView: {
        matchMedia: (media: string) => {
          observedQuery = media;
          return query;
        },
      },
      querySelector: (selector: string) => {
        if (selector === "[data-role='conversation-rail']") return drawer;
        if (selector === "[data-role='conversations-toggle']") return toggle;
        if (selector === "[data-role='conversation-scrim']") return scrim;
        return null;
      },
      addEventListener: () => {},
    };
    installChatControls(fakeDocument as unknown as Document);

    expect(observedQuery).toBe("(min-width: 42rem)");

    setConversationDrawer(fakeDocument as unknown as Document, true, {
      keepFocus: true,
    });
    expect(drawer.classList.contains("is-open")).toBe(true);

    query.matches = false;
    listenerHost.current?.();
    expect(drawer.classList.contains("is-open")).toBe(true);

    query.matches = true;
    listenerHost.current?.();
    expect(drawer.classList.contains("is-open")).toBe(false);
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
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
