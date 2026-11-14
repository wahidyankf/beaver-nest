// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/chat_keys.js` (ADR 005, decision 1, revised 2026-11-13). The rule follows the
// visitor's input type only: a coarse primary pointer (touch) makes Enter a new line and Shift+Enter a send; a fine
// primary pointer (desktop or laptop) makes Enter a send and Shift+Enter a new line. The screen width never decides.
// Each test states the pointer and the width it reports through a window stub, so the rule is checked without a browser.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  vi,
  type Mock,
} from "vitest";
import {
  handleComposerKey,
  installComposerKeys,
  isTouchPointer,
  keepFocusOnSendPress,
  keyIntent,
  sendOnKey,
} from "../../js/chat_keys.js";

interface ViewState {
  coarse: boolean;
  width: number;
}

// The window the keys read: `matchMedia("(pointer: coarse)")` and `innerWidth`. The width is here so that a rule which
// read it would change the outcome; no test expects the width to matter.
function viewOf(state: ViewState): Window {
  return {
    get innerWidth() {
      return state.width;
    },
    matchMedia(query: string) {
      return {
        matches: query === "(pointer: coarse)" && state.coarse,
        media: query,
        addEventListener() {},
        removeEventListener() {},
      };
    },
  } as unknown as Window;
}

function fakeKey(
  init: Partial<{
    key: string;
    shiftKey: boolean;
    isComposing: boolean;
    repeat: boolean;
  }>,
) {
  return {
    key: "Enter",
    shiftKey: false,
    isComposing: false,
    ...init,
    preventDefault: vi.fn(),
  };
}

function fakeBox(value: string, disabled = false, readOnly = false) {
  const requestSubmit = vi.fn();
  return {
    value,
    disabled,
    readOnly,
    form: { requestSubmit },
    requestSubmit,
  };
}

const TOUCH = true;
const FINE = false;

describe("isTouchPointer", () => {
  it("reads the primary pointer only", () => {
    expect(isTouchPointer(viewOf({ coarse: TOUCH, width: 390 }))).toBe(true);
    expect(isTouchPointer(viewOf({ coarse: FINE, width: 390 }))).toBe(false);
  });

  it("gives the same answer at every width", () => {
    for (const width of [320, 768, 1024, 1440]) {
      expect(isTouchPointer(viewOf({ coarse: TOUCH, width }))).toBe(true);
      expect(isTouchPointer(viewOf({ coarse: FINE, width }))).toBe(false);
    }
  });
});

describe("keyIntent on a touch pointer", () => {
  it("starts a new line on Enter", () => {
    expect(keyIntent({ key: "Enter" }, TOUCH)).toBe("newline");
  });

  it("sends on Shift+Enter", () => {
    expect(keyIntent({ key: "Enter", shiftKey: true }, TOUCH)).toBe("send");
  });

  it("ignores Enter that confirms an IME composition, with or without Shift", () => {
    expect(keyIntent({ key: "Enter", isComposing: true }, TOUCH)).toBe(
      "ignore",
    );
    expect(
      keyIntent({ key: "Enter", shiftKey: true, isComposing: true }, TOUCH),
    ).toBe("ignore");
  });

  it("ignores every other key", () => {
    expect(keyIntent({ key: "a" }, TOUCH)).toBe("ignore");
    expect(keyIntent({ key: "Escape", shiftKey: true }, TOUCH)).toBe("ignore");
  });
});

describe("keyIntent on a fine pointer", () => {
  it("sends on Enter", () => {
    expect(keyIntent({ key: "Enter" }, FINE)).toBe("send");
  });

  it("starts a new line on Shift+Enter", () => {
    expect(keyIntent({ key: "Enter", shiftKey: true }, FINE)).toBe("newline");
  });

  it("ignores Enter that confirms an IME composition, with or without Shift", () => {
    expect(keyIntent({ key: "Enter", isComposing: true }, FINE)).toBe("ignore");
    expect(
      keyIntent({ key: "Enter", shiftKey: true, isComposing: true }, FINE),
    ).toBe("ignore");
  });

  it("ignores every other key", () => {
    expect(keyIntent({ key: "a" }, FINE)).toBe("ignore");
  });
});

describe("handleComposerKey", () => {
  it("sends a filled draft on Enter with a fine pointer, once, and stops the browser's newline", () => {
    const box = fakeBox("Hello");
    const press = fakeKey({ key: "Enter" });

    handleComposerKey(
      press as unknown as KeyboardEvent,
      box as unknown as HTMLTextAreaElement,
      FINE,
    );

    expect(press.preventDefault).toHaveBeenCalledOnce();
    expect(box.form.requestSubmit).toHaveBeenCalledOnce();
  });

  it("sends a filled draft on Shift+Enter with a touch pointer, once", () => {
    const box = fakeBox("Hello");
    const press = fakeKey({ key: "Enter", shiftKey: true });

    handleComposerKey(
      press as unknown as KeyboardEvent,
      box as unknown as HTMLTextAreaElement,
      TOUCH,
    );

    expect(press.preventDefault).toHaveBeenCalledOnce();
    expect(box.form.requestSubmit).toHaveBeenCalledOnce();
  });

  it("leaves Enter alone on a touch pointer, so the browser inserts the new line", () => {
    const box = fakeBox("Hello");
    const press = fakeKey({ key: "Enter" });

    handleComposerKey(
      press as unknown as KeyboardEvent,
      box as unknown as HTMLTextAreaElement,
      TOUCH,
    );

    expect(press.preventDefault).not.toHaveBeenCalled();
    expect(box.form.requestSubmit).not.toHaveBeenCalled();
  });

  it("leaves Shift+Enter alone on a fine pointer, so the browser inserts the new line", () => {
    const box = fakeBox("Hello");
    const press = fakeKey({ key: "Enter", shiftKey: true });

    handleComposerKey(
      press as unknown as KeyboardEvent,
      box as unknown as HTMLTextAreaElement,
      FINE,
    );

    expect(press.preventDefault).not.toHaveBeenCalled();
    expect(box.form.requestSubmit).not.toHaveBeenCalled();
  });

  it("does not send a blank draft, on either pointer", () => {
    for (const coarse of [TOUCH, FINE]) {
      const box = fakeBox("   ");
      const press = fakeKey({ key: "Enter", shiftKey: coarse });

      handleComposerKey(
        press as unknown as KeyboardEvent,
        box as unknown as HTMLTextAreaElement,
        coarse,
      );

      expect(box.form.requestSubmit).not.toHaveBeenCalled();
    }
  });

  it("does not send while the box is disabled (a reply is in progress), on either pointer", () => {
    for (const coarse of [TOUCH, FINE]) {
      const box = fakeBox("Hello", true);
      const press = fakeKey({ key: "Enter", shiftKey: coarse });

      handleComposerKey(
        press as unknown as KeyboardEvent,
        box as unknown as HTMLTextAreaElement,
        coarse,
      );

      expect(box.form.requestSubmit).not.toHaveBeenCalled();
    }
  });

  it("never sends on an IME composition, on either pointer, and keeps the draft", () => {
    for (const coarse of [TOUCH, FINE]) {
      const box = fakeBox("Compose");
      const press = fakeKey({
        key: "Enter",
        shiftKey: coarse,
        isComposing: true,
      });

      handleComposerKey(
        press as unknown as KeyboardEvent,
        box as unknown as HTMLTextAreaElement,
        coarse,
      );

      expect(press.preventDefault).not.toHaveBeenCalled();
      expect(box.form.requestSubmit).not.toHaveBeenCalled();
    }
  });
});

describe("installComposerKeys on a page", () => {
  let state: ViewState;
  let submitted: Mock<(event: Event) => void>;

  beforeAll(() => {
    state = { coarse: FINE, width: 1440 };
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  // The listener lives on the document, so it is installed once per test file; a second install would send twice.
  function page(value: string, view: Window) {
    document.body.innerHTML = `
      <form id="form"><textarea id="box" data-role="chat-composer"></textarea></form>
      <textarea id="other" data-role="other"></textarea>`;
    const box = document.querySelector<HTMLTextAreaElement>(
      "#box",
    ) as HTMLTextAreaElement;
    box.value = value;
    submitted = vi.fn((event: Event) => event.preventDefault());
    document
      .querySelector("#form")
      ?.addEventListener("submit", (event) => submitted(event));
    return { box, view };
  }

  function press(
    box: HTMLTextAreaElement,
    init: { key: string; shiftKey?: boolean; isComposing?: boolean },
  ) {
    box.dispatchEvent(
      new KeyboardEvent("keydown", {
        ...init,
        bubbles: true,
        cancelable: true,
      }),
    );
  }

  it("follows the pointer at each key press: a switch from fine to touch changes what Enter does", () => {
    installComposerKeys(document, viewOf(state));
    const { box } = page("First", viewOf(state));

    press(box, { key: "Enter" });
    expect(submitted).toHaveBeenCalledOnce();

    state.coarse = TOUCH;
    box.value = "Second";
    press(box, { key: "Enter" });
    expect(submitted).toHaveBeenCalledOnce();

    press(box, { key: "Enter", shiftKey: true });
    expect(submitted).toHaveBeenCalledTimes(2);

    state.coarse = FINE;
    press(box, { key: "Enter" });
    expect(submitted).toHaveBeenCalledTimes(3);
  });

  it("sends one message per send press, and a press while the box is disabled sends nothing", () => {
    state.coarse = FINE;
    const { box } = page("First", viewOf(state));

    press(box, { key: "Enter" });
    expect(submitted).toHaveBeenCalledOnce();

    box.disabled = true;
    press(box, { key: "Enter" });
    expect(submitted).toHaveBeenCalledOnce();
  });

  it("does not send an IME composition, on either pointer, and keeps the draft", () => {
    for (const coarse of [TOUCH, FINE]) {
      state.coarse = coarse;
      const { box } = page("Still composing", viewOf(state));

      press(box, { key: "Enter", shiftKey: coarse, isComposing: true });

      expect(submitted).not.toHaveBeenCalled();
      expect(box.value).toBe("Still composing");
    }
  });

  it("ignores a key press in a textarea that is not the Codex message box", () => {
    state.coarse = FINE;
    page("Hello", viewOf(state));
    const other = document.querySelector("#other") as HTMLTextAreaElement;

    other.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Enter",
        bubbles: true,
        cancelable: true,
      }),
    );

    expect(submitted).not.toHaveBeenCalled();
  });

  it.each([320, 768, 1024, 1440])(
    "keeps the same behaviour at a %i pixel window: fine Enter sends, touch Enter makes a new line",
    (width) => {
      state.width = width;
      state.coarse = FINE;
      const { box } = page("Width check", viewOf(state));
      press(box, { key: "Enter" });
      expect(submitted).toHaveBeenCalledOnce();

      state.coarse = TOUCH;
      box.value = "Width check";
      press(box, { key: "Enter" });
      expect(submitted).toHaveBeenCalledOnce();
    },
  );
});

// --- Input methods, held keys, and the width rule (round 3) -------------------------------------------------------

const here = path.dirname(fileURLToPath(import.meta.url));

describe("an input method's Enter (keyCode 229)", () => {
  it("is ignored on either pointer, with or without Shift, so Safari's composition Enter never sends", () => {
    for (const touch of [TOUCH, FINE]) {
      for (const shiftKey of [false, true]) {
        expect(keyIntent({ key: "Enter", shiftKey, keyCode: 229 }, touch)).toBe(
          "ignore",
        );
      }
    }
  });
});

describe("a held Enter", () => {
  it("does not send again on a repeat, and still stops the browser's newline", () => {
    const box = fakeBox("Hello");
    const press = fakeKey({ key: "Enter", repeat: true });

    handleComposerKey(
      press as unknown as KeyboardEvent,
      box as unknown as HTMLTextAreaElement,
      FINE,
    );

    expect(press.preventDefault).toHaveBeenCalledOnce();
    expect(box.form.requestSubmit).not.toHaveBeenCalled();
  });
});

describe("sendOnKey, the rule both message boxes share (Family Chat and Codex)", () => {
  it("runs the send once on a send press and stops the browser's newline", () => {
    for (const coarse of [TOUCH, FINE]) {
      const send = vi.fn();
      const press = fakeKey({ key: "Enter", shiftKey: coarse });

      const sent = sendOnKey(press, coarse, send);

      expect(sent).toBe(true);
      expect(press.preventDefault).toHaveBeenCalledOnce();
      expect(send).toHaveBeenCalledOnce();
    }
  });

  it("does not run the send again for a held send key, and still stops the newline", () => {
    for (const coarse of [TOUCH, FINE]) {
      const send = vi.fn();
      const press = fakeKey({ key: "Enter", shiftKey: coarse, repeat: true });

      sendOnKey(press, coarse, send);

      expect(press.preventDefault).toHaveBeenCalledOnce();
      expect(send).not.toHaveBeenCalled();
    }
  });

  it("leaves a newline press alone, so the browser inserts the line", () => {
    const send = vi.fn();
    const press = fakeKey({ key: "Enter" });

    expect(sendOnKey(press, TOUCH, send)).toBe(false);
    expect(press.preventDefault).not.toHaveBeenCalled();
    expect(send).not.toHaveBeenCalled();
  });
});

describe("a read-only Codex box while a reply is in progress (U1)", () => {
  it("never sends from a read-only box, on either pointer, and keeps the draft", () => {
    for (const coarse of [TOUCH, FINE]) {
      const box = fakeBox("Next question", false, true);
      const press = fakeKey({ key: "Enter", shiftKey: coarse });

      handleComposerKey(
        press as unknown as KeyboardEvent,
        box as unknown as HTMLTextAreaElement,
        coarse,
      );

      expect(box.form.requestSubmit).not.toHaveBeenCalled();
      expect(box.value).toBe("Next question");
    }
  });
});

describe("keepFocusOnSendPress on a page", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  function sendPage() {
    document.body.innerHTML = `
      <form id="chat-composer-form">
        <textarea data-role="chat-composer"></textarea>
        <button type="submit" class="send-button"><span>Send</span></button>
      </form>
      <button type="button" class="chat-options-toggle">Options</button>`;
    return {
      send: document.querySelector<HTMLElement>(
        ".send-button span",
      ) as HTMLElement,
      box: document.querySelector<HTMLElement>("textarea") as HTMLElement,
      options: document.querySelector<HTMLElement>(
        ".chat-options-toggle",
      ) as HTMLElement,
    };
  }

  // Dispatches one press and reports whether its default was cancelled, which is what keeps focus where it is.
  function pressDefaultCancelled(target: HTMLElement, type: string): boolean {
    const press = new Event(type, { bubbles: true, cancelable: true });
    target.dispatchEvent(press);
    return press.defaultPrevented;
  }

  it("cancels the default of a pointer press and a mouse press on the Send button, so focus stays in the box", () => {
    const { send } = sendPage();
    keepFocusOnSendPress(window);
    expect(pressDefaultCancelled(send, "pointerdown")).toBe(true);
    expect(pressDefaultCancelled(send, "mousedown")).toBe(true);
  });

  it("leaves presses on the message box and on other buttons alone", () => {
    const { box, options } = sendPage();
    keepFocusOnSendPress(window);
    expect(pressDefaultCancelled(box, "pointerdown")).toBe(false);
    expect(pressDefaultCancelled(box, "mousedown")).toBe(false);
    expect(pressDefaultCancelled(options, "mousedown")).toBe(false);
  });
});

describe("the key rule and the screen width", () => {
  it("chat_keys.js reads no window width and no width media query", () => {
    const source = readFileSync(
      path.resolve(here, "../../js/chat_keys.js"),
      "utf8",
    );
    expect(source).not.toMatch(
      /innerWidth|outerWidth|clientWidth|max-width|min-width/u,
    );
  });
});
