// Step bindings for the Codex chat rules of specs/apps/bnest/app-fe/behaviours/chat.feature (tag `@fe-vitest-unit`):
// the message box keys (ADR 005, decision 1), the Clear chat confirmation (decision 2), the raw or rendered view of a
// visitor's message (decision 4), the single light appearance (decision 3), and the phone layout budget (owner
// request, 2026-11-13).
//
// The keys and the controls run the shipped modules (`js/chat_keys.js`, `js/chat_controls.js`) on a happy-dom page
// whose markup mirrors `chat_live.ex`. The server's part (LiveView `clear`, `phx-submit`) is proven by the e2e
// adapter, which runs the real page. The layout Thens check the declared values of the shipped stylesheet.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Window } from "happy-dom";
import {
  installComposerKeys,
  keepFocusOnSendPress,
} from "../../js/chat_keys.js";
import { ChatComposer } from "../../js/codex_composer_hook.js";
import { installChatControls } from "../../js/chat_controls.js";
import {
  declarationsFor,
  lengthPx,
  resolveVars,
  type Environment,
} from "../support/shipped_css";
import {
  forgetScenario,
  recall,
  recallOr,
  remember,
} from "./support/scenario_memory";
import {
  assertHintTakesNoRow,
  CODEX_TEMPLATE,
  hintAsSeen,
  hintEnvironment,
} from "./support/send_hint";
import {
  assertNoDarkPreferenceRule,
  assertNoThemeControl,
  assertPageBackgroundIsLight,
  assertSingleLightAppearance,
  contrastRatio,
  templateFor,
} from "./support/appearance";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

const here = path.dirname(fileURLToPath(import.meta.url));
const APP_ROOT = path.resolve(here, "../../..");
const CHAT_TEMPLATE = path.resolve(
  APP_ROOT,
  "lib/bnest_app_web/live/chat_live.ex",
);

const TOUCH_TARGET_PX = 44;
/** The widest screen the phone header rules cover (the `max-width: 767px` media query). */
const PHONE_WIDTH_PX = 767;
/** Fails the step when the condition does not hold. Vitest's `expect` without a matcher asserts nothing. */
function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const registry: StepDefinition[] = [];

function step(
  expression: string,
  handler: (...args: string[]) => void | Promise<void>,
): void {
  const wrapped: StepHandler = async (context, ...args) => {
    await handler(...args);
    return context;
  };
  registry.push({ expression, handler: wrapped });
}

export function codexComposerSteps(): readonly StepDefinition[] {
  return registry;
}

/** Forgets the page a scenario built; `verify.ts` calls this after every scenario. */
export function resetCodexComposer(): void {
  page?.window.close();
  page = null;
  forgetScenario();
}

// --- The page ----------------------------------------------------------------------------

interface Page {
  readonly window: Window;
  readonly document: Document;
  readonly textarea: HTMLTextAreaElement;
  readonly form: HTMLFormElement;
  submits: number;
  clears: number;
  hook?: { mounted(): void; beforeUpdate(): void; updated(): void };
}

let page: Page | null = null;

// The window the keys read: its width comes from the layout binding's viewport and its pointer from the pointer step.
// The keys read the pointer only; the width is there so a rule that read it would change the outcome, and the cross
// rows would catch it.
const view = {
  get innerWidth(): number {
    return recallOr("codexViewport", { width: 1280, height: 800 }).width;
  },
  matchMedia(query: string) {
    // Only the pointer queries are evaluated. Any other query is a width or a preference the double cannot answer, so it
    // throws rather than answering false and letting a width rule pass unseen.
    if (query === "(display-mode: standalone)")
      return {
        matches: false,
        media: query,
        addEventListener() {},
        removeEventListener() {},
      } as unknown as MediaQueryList;
    if (!/^\(pointer: (coarse|fine)\)$/u.test(query)) {
      throw new Error(`the matchMedia double does not evaluate ${query}`);
    }
    return {
      matches: query === "(pointer: coarse)" && recallOr("codexCoarse", false),
      media: query,
      addEventListener() {},
      removeEventListener() {},
    };
  },
};

/** Builds the Codex message box and the Clear chat controls, markup as `chat_live.ex` renders them. */
function openPage(): Page {
  const window = new Window({ url: "http://localhost/chat" });
  const document = window.document;
  document.body.innerHTML = `
    <main class="chat-shell">
      <div class="chat-header">
        <button type="button" class="chat-options-toggle" data-role="chat-options-toggle" aria-expanded="false" aria-controls="chat-options">Options</button>
        <div id="chat-options" class="chat-actions" data-role="chat-options">
          <div class="clear-chat" data-role="clear-chat-group">
            <button type="button" class="clear-chat-button" data-role="clear-chat" aria-expanded="false" aria-controls="clear-chat-confirm">Clear chat</button>
            <div id="clear-chat-confirm" class="clear-chat-confirm" role="alertdialog" aria-label="Confirm clearing the chat" aria-describedby="clear-chat-question" data-role="clear-chat-confirm" hidden>
              <p id="clear-chat-question" class="clear-chat-question">Delete all messages?</p>
              <button type="button" class="clear-chat-cancel" data-role="clear-chat-cancel">Cancel</button>
              <button type="button" class="clear-chat-yes" data-role="clear-chat-yes">Yes, delete</button>
            </div>
          </div>
        </div>
      </div>
      <div id="chat-conversation" class="conversation"></div>
      <form id="chat-composer-form" class="composer">
        <textarea id="chat-composer" data-role="chat-composer" aria-describedby="chat-composer-hint" rows="1"></textarea>
        <button type="submit" class="send-button">Send</button>
        <p id="chat-composer-hint" class="composer-hint" data-role="composer-hint"><span class="hint-keyboard">Enter to send, Shift+Enter for a new line</span><span class="hint-touch">Shift+Enter to send</span></p>
      </form>
    </main>`;
  const textarea = document.querySelector(
    "textarea",
  ) as unknown as HTMLTextAreaElement;
  const form = document.querySelector("form") as unknown as HTMLFormElement;
  const built: Page = {
    window,
    document: document as unknown as Document,
    textarea,
    form,
    submits: 0,
    clears: 0,
  };
  // The same hook app.js registers on the message box. It mounts before the submit model, so it records the sent text
  // first, as LiveView's own submit handling runs after the form's listeners.
  const hook = Object.assign(Object.create(ChatComposer), { el: textarea });
  hook.mounted();
  built.hook = hook;
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    built.submits += 1;
    // The box is empty straight after a send in this model. The server's own clear, in the reply patch, is modelled by
    // "Codex finishes the reply".
    built.textarea.value = "";
  });
  document
    .querySelector("[data-role='clear-chat-yes']")
    ?.addEventListener("click", () => {
      built.clears += 1;
    });
  installComposerKeys(
    window as unknown as Parameters<typeof installComposerKeys>[0],
    view as unknown as Parameters<typeof installComposerKeys>[1],
  );
  // The same wiring as app.js: a pointer press on Send does not move keyboard focus off the box.
  keepFocusOnSendPress(
    window as unknown as Parameters<typeof keepFocusOnSendPress>[0],
  );
  installChatControls(document as unknown as Document);
  return built;
}

function currentPage(): Page {
  if (page === null) page = openPage();
  return page;
}

/** Dispatches a key press as the browser does; a key the page does not prevent types its newline. */
function press(
  key: string,
  options: { shiftKey?: boolean; isComposing?: boolean } = {},
): void {
  const built = currentPage();
  // The keydown is dispatched even to a disabled box: the production guard in chat_keys.js must be what stops a send.
  const target = built.document.activeElement ?? built.document.body;
  const down = new built.window.KeyboardEvent("keydown", {
    key,
    shiftKey: options.shiftKey ?? false,
    isComposing: options.isComposing ?? false,
    bubbles: true,
    cancelable: true,
  });
  target.dispatchEvent(down as unknown as Event);
  if (
    !down.defaultPrevented &&
    key === "Enter" &&
    !options.isComposing &&
    target === built.textarea
  ) {
    built.textarea.value += "\n";
  }
}

function click(selector: string): void {
  const element = currentPage().document.querySelector(
    selector,
  ) as HTMLElement | null;
  if (!element) throw new Error(`no element matches ${selector}`);
  element.click();
}

function focusedRole(): string | null {
  const active = currentPage().document.activeElement;
  return active?.getAttribute("data-role") ?? null;
}

function requireMessage(): void {
  currentPage().textarea.focus();
}

// --- Keys ----------------------------------------------------------------------------------

/** "Shift+Enter" -> key "Enter" with Shift; any other name is the key itself. */
function keyOf(name: string): { key: string; shiftKey: boolean } {
  const shiftKey = name.startsWith("Shift+");
  return { key: shiftKey ? name.slice("Shift+".length) : name, shiftKey };
}

step("the visitor connects a touch pointer", () => {
  remember("codexCoarse", true);
});

step("the Codex message box has keyboard focus", () => {
  requireMessage();
});

// A browser moves focus to the button a pointer presses, unless the press's default is cancelled. The page's own
// listeners run first, so the model reads whether the press was cancelled before it moves focus.
step("the visitor presses Send with a pointer", () => {
  const built = currentPage();
  const send = built.document.querySelector(".send-button") as HTMLElement;
  for (const type of ["pointerdown", "mousedown"]) {
    const press = new built.window.Event(type, {
      bubbles: true,
      cancelable: true,
    });
    send.dispatchEvent(press as unknown as Event);
    if (!press.defaultPrevented) send.focus();
  }
  send.click();
});

step("the Codex message box holds {string}", (text) => {
  // The visitor types into the box, so it holds keyboard focus; a key press then reaches it.
  remember("codexDraft", text);
  const built = currentPage();
  built.textarea.value = text;
  built.textarea.focus();
});

// The box is read-only while Codex replies, not disabled: a disabled box loses keyboard focus (ADR 005, decision 1).
function assertBusyBoxIsReadOnly(): void {
  const source = readFileSync(CHAT_TEMPLATE, "utf8");
  // Only the message box's own tag: the Send button beside it is disabled while busy, and that is allowed.
  const start = source.indexOf('data-role="chat-composer"');
  const box = source.slice(start, source.indexOf("/>", start));
  check(
    /readonly=\{@chat\.busy\}/u.test(box),
    "the Codex message box is not read-only while busy in chat_live.ex",
  );
  check(
    !/disabled=\{@chat\.busy/u.test(box),
    "the Codex message box is still disabled while busy in chat_live.ex",
  );
}

step("Codex is {string}", (state) => {
  assertBusyBoxIsReadOnly();
  currentPage().textarea.readOnly = state === "replying";
});

step("Codex finishes the reply", () => {
  assertBusyBoxIsReadOnly();
  const built = currentPage();
  // The reply patch: the server clears the box it sent from. The hook puts back only the text typed after the send.
  built.hook?.beforeUpdate();
  built.textarea.value = "";
  built.hook?.updated();
  built.textarea.readOnly = false;
});

// Text typed after the send, before the reply's patch clears the box. The box takes keys only while it is not read-only.
step(
  "the visitor types {string} in the Codex message box before the reply lands",
  (text) => {
    const built = currentPage();
    check(
      !built.textarea.readOnly,
      "the Codex message box is read-only, so it takes no text",
    );
    built.textarea.value += text;
  },
);

step("the Codex message box keeps {string}", (text) => {
  check(
    currentPage().textarea.value === text,
    `the Codex message box holds ${JSON.stringify(currentPage().textarea.value)}, not ${JSON.stringify(text)}`,
  );
});

step("keyboard focus is in the Codex message box", () => {
  const built = currentPage();
  check(
    built.document.activeElement === built.textarea,
    "keyboard focus is not in the Codex message box",
  );
});

step("the visitor presses {string} in the Codex message box", (name) => {
  press(keyOf(name).key, { shiftKey: keyOf(name).shiftKey });
});

step(
  "the visitor confirms a composition with {string} in the Codex message box",
  (name) => {
    press(keyOf(name).key, {
      shiftKey: keyOf(name).shiftKey,
      isComposing: true,
    });
  },
);

step("the message box shows {string}", (shown) => {
  const value = currentPage().textarea.value;
  if (shown === "an empty box") {
    check(value === "", `the box holds ${JSON.stringify(value)}`);
    return;
  }
  if (shown === "a new line after its draft") {
    // The expected text is the draft the visitor typed in this scenario, not a fixed word.
    const draft = recall<string>("codexDraft");
    check(value === `${draft}\n`, `the box holds ${JSON.stringify(value)}`);
    return;
  }
  throw new Error(`unknown box state ${shown}`);
});

step("nothing is sent to Codex", () => {
  check(
    currentPage().submits === 0,
    `${currentPage().submits} sends reached the form`,
  );
});

step("Codex receives {int} message sends", (count) => {
  check(
    String(currentPage().submits) === String(count),
    `Codex received ${currentPage().submits} sends, not ${count}`,
  );
});

step("the send shortcut hint reads {string}", (text) => {
  // The wording the visitor sees: the production template's spans, shown or hidden by the shipped stylesheet for the
  // visitor's pointer. The pointer comes from the scenario's last pointer step.
  const shown = hintAsSeen(
    CODEX_TEMPLATE,
    hintEnvironment(
      recallOr<{ viewport: { width: number; height: number } } | null>(
        "codexLaidOut",
        null,
      ),
      recallOr("codexCoarse", false),
    ),
  );
  check(
    shown.length === 1 && shown[0] === text,
    `the hint a visitor sees is ${JSON.stringify(shown)}, not ${JSON.stringify([text])}`,
  );
});

step("the send shortcut hint takes no row", () => {
  const env = hintEnvironment(
    recallOr<{ viewport: { width: number; height: number } } | null>(
      "codexLaidOut",
      null,
    ),
    recallOr("codexCoarse", false),
  );
  assertHintTakesNoRow(".composer-hint", env);
});

// --- Clear chat ----------------------------------------------------------------------------

step("the Codex conversation holds {string}", (text) => {
  const conversation =
    currentPage().document.getElementById("chat-conversation");
  if (!conversation) throw new Error("no conversation");
  conversation.innerHTML = `<p data-role="user-message">${text}</p>`;
});

step("the visitor chooses Clear chat", () => {
  click("[data-role='clear-chat']");
});

step("the visitor has chosen Clear chat", () => {
  click("[data-role='clear-chat']");
});

step("the visitor chooses Cancel", () => {
  click("[data-role='clear-chat-cancel']");
});

step("the visitor presses Escape", () => {
  const built = currentPage();
  const target = built.document.activeElement ?? built.document.body;
  target.dispatchEvent(
    new built.window.KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    }) as unknown as Event,
  );
});

// A Tab that leaves the confirmation moves focus to a control outside it. The browser sends a focusout that names
// that control, as the chat_controls.js rule reads it; this model moves focus to the message box, which is outside
// the confirmation. The real Tab order is walked in Chromium (bnest-app-fe-e2e, Clear chat steps).
step("the visitor tabs out of the confirmation", () => {
  const built = currentPage();
  const from = built.document.activeElement ?? built.document.body;
  const outside = built.textarea;
  outside.focus();
  const leaving = new built.window.FocusEvent("focusout", { bubbles: true });
  // The focus target is set on the event itself, as the browser sends it; the event class's init type does not take it.
  Object.defineProperty(leaving, "relatedTarget", { value: outside });
  from.dispatchEvent(leaving as unknown as Event);
});

step("the visitor chooses Yes, delete", () => {
  click("[data-role='clear-chat-yes']");
});

step("the confirmation asks {string}", (text) => {
  check(
    currentPage().document.querySelector(
      "[data-role='clear-chat-confirm'] .clear-chat-question",
    )?.textContent === text,
    "the confirmation asks a different question",
  );
});

step("the confirmation offers {string} and {string}", (yes, cancel) => {
  const buttons = [
    ...currentPage().document.querySelectorAll(
      "[data-role='clear-chat-confirm'] button",
    ),
  ].map((button) => button.textContent?.trim());
  check(
    buttons.join("|") === `${cancel}|${yes}`,
    `the confirmation offers ${buttons.join(", ")}`,
  );
});

step("the conversation still shows {string}", (text) => {
  const shown = currentPage().document.querySelector(
    "[data-role='user-message']",
  )?.textContent;
  check(shown === text, `the conversation shows ${JSON.stringify(shown)}`);
});

// The Clear chat markup in this file is hand-written, so the server's template is checked too: exactly one
// `phx-click="clear"` in chat_live.ex, on the Yes button. A Clear chat trigger that sent it would leave the browser
// counter at 0 here and still pass the counter alone.
function checkClearOnlyOnYes(): void {
  const source = readFileSync(CHAT_TEMPLATE, "utf8");
  const clearEvents = source.match(/phx-click="clear"/gu) ?? [];
  check(
    clearEvents.length === 1,
    `chat_live.ex has ${clearEvents.length} phx-click="clear" attributes, not 1`,
  );
  check(
    /<button[^>]*data-role="clear-chat-yes"[^>]*phx-click="clear"/u.test(
      source,
    ),
    "the Yes, delete button no longer sends the clear event in chat_live.ex",
  );
}

step("nothing is cleared yet", () => {
  check(
    currentPage().clears === 0,
    "the clear request was sent before the confirmation",
  );
  checkClearOnlyOnYes();
});

step("the confirmation is closed", () => {
  const confirmation = currentPage().document.querySelector(
    "[data-role='clear-chat-confirm']",
  ) as HTMLElement | null;
  check(confirmation?.hidden === true, "the confirmation is still open");
});

step("keyboard focus is on the confirmation's Cancel button", () => {
  check(focusedRole() === "clear-chat-cancel", `focus is on ${focusedRole()}`);
});

step("the visitor moves focus to the message box", () => {
  currentPage().textarea.focus();
});

step("keyboard focus is on the message box", () => {
  const built = currentPage();
  check(
    built.document.activeElement === built.textarea,
    `focus is on ${built.document.activeElement?.tagName ?? "nothing"}`,
  );
});

step("keyboard focus is on the Clear chat button", () => {
  check(focusedRole() === "clear-chat", `focus is on ${focusedRole()}`);
});

step("the clear request is sent to Codex", () => {
  // The browser counter proves the click; the template proves that only "Yes, delete" carries the LiveView clear event.
  checkClearOnlyOnYes();
  const source = readFileSync(CHAT_TEMPLATE, "utf8");
  const cancel =
    /<button[^>]*data-role="clear-chat-cancel"[^>]*>/u.exec(source)?.[0] ?? "";
  check(
    cancel !== "" && !cancel.includes("phx-click"),
    "the Cancel button sends a clear event in chat_live.ex",
  );
  check(
    currentPage().clears === 1,
    `the clear request was sent ${currentPage().clears} times`,
  );
});

// The unit layer proves only that the confirmation is an overlay. Its place on the screen, and that it covers the
// composer without a page scroll, are measured in Chromium (bnest-app-fe-e2e, Clear chat steps).
step("the confirmation is on screen without scrolling the page", () => {
  const env = laidOut();
  check(
    declarationsFor(".clear-chat-confirm", env)["position"] === "absolute",
    "the confirmation is not an overlay",
  );
});

step("each confirmation button is at least 44 pixels tall and across", () => {
  const env = laidOut();
  const height = lengthPx(
    resolveVars(
      declarationsFor(".clear-chat-actions button", env)["min-height"] ?? "",
    ),
    env,
  );
  const width = lengthPx(
    resolveVars(
      declarationsFor(".clear-chat-actions button", env)["min-width"] ?? "",
    ),
    env,
  );
  check(
    height >= TOUCH_TARGET_PX && width >= TOUCH_TARGET_PX,
    `the buttons are ${width} by ${height} px`,
  );
});

step("the confirmation is no wider than the screen", () => {
  const env = laidOut();
  const width = lengthPx(
    resolveVars(declarationsFor(".clear-chat-confirm", env)["width"] ?? ""),
    env,
  );
  check(
    width <= env.width,
    `the confirmation is ${width} px on a ${env.width} px screen`,
  );
});

// --- Own messages --------------------------------------------------------------------------

// The markup the production component writes for a visitor's message (`ChatComponents.own_message`), and the text the
// visitor typed. `own_message_markup_fixture_test.exs` proves the committed file equals the shipped markup, so these rows read
// the server's output and never a copy written here.
const OWN_MESSAGE_FIXTURE = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../test/support/own_message_markup.json",
);
const OWN_MESSAGES = JSON.parse(
  readFileSync(OWN_MESSAGE_FIXTURE, "utf8"),
) as Record<string, { input: string; markup: string }>;

function ownMessageFixture(name: string): { input: string; markup: string } {
  const fixture = OWN_MESSAGES[name];
  if (!fixture) throw new Error(`no own-message fixture named ${name}`);
  return fixture;
}

// Puts one fixture message into the conversation, as the server rendered it. The typed text is the fixture's input.
function ownMessage(name: string): void {
  const fixture = ownMessageFixture(name);
  const built = currentPage();
  const conversation = built.document.getElementById("chat-conversation");
  if (!conversation) throw new Error("no conversation");
  conversation.innerHTML = `<article data-role="message">${fixture.markup}</article>`;
  // The Then compares the raw view with this recorded input, which comes from the server fixture.
  remember("typedText", fixture.input);
}

step("a visitor's message with Markdown is in the Codex conversation", () => {
  ownMessage("plain");
});

step(
  "a visitor's message with script and javascript link text is in the Codex conversation",
  () => {
    ownMessage("hostile");
  },
);

step(
  "a visitor's message with line breaks and indentation is in the Codex conversation",
  () => {
    ownMessage("whitespace");
  },
);

step("the visitor's message shows its Markdown rendered", () => {
  const view = currentPage()
    .document.querySelector("[data-role='own-message']")
    ?.getAttribute("data-view");
  check(view === "rendered", `the message shows its ${view} view`);
});

step(
  "the visitor's message has a {string} control of at least 44 pixels",
  (label) => {
    const toggle = currentPage().document.querySelector(
      "[data-role='raw-toggle']",
    );
    check(
      toggle?.textContent?.includes(label) === true,
      `the control does not read ${label}`,
    );
    const env = laidOut();
    const height = lengthPx(
      resolveVars(declarationsFor(".own-raw-toggle", env)["min-height"] ?? ""),
      env,
    );
    check(height >= TOUCH_TARGET_PX, `the control is ${height} px tall`);
  },
);

// The label names the view the visitor asks for. The toggle is clicked only when that view is not already showing, so
// "Show raw" and "Show rendered" are different actions.
step("the visitor chooses {string} on the visitor's message", (label) => {
  const wanted =
    label === "Show raw"
      ? "raw"
      : label === "Show rendered"
        ? "rendered"
        : null;
  check(
    wanted !== null,
    `no own-message view is named ${JSON.stringify(label)}`,
  );
  const shown = () =>
    currentPage()
      .document.querySelector("[data-role='own-message']")
      ?.getAttribute("data-view");
  if (shown() !== wanted) click("[data-role='raw-toggle']");
  check(shown() === wanted, `the view is ${shown()} after choosing ${label}`);
});

step("the visitor's message shows the exact typed text", () => {
  const built = currentPage();
  const message = built.document.querySelector("[data-role='own-message']");
  const raw =
    built.document.querySelector("[data-role='user-message-raw']")
      ?.textContent ?? "";
  check(
    message?.getAttribute("data-view") === "raw",
    "the raw view is not showing",
  );
  check(
    raw === recall<string>("typedText"),
    `the raw view shows ${JSON.stringify(raw)}`,
  );
});

step("the control reads {string}", (label) => {
  // The label is the span the shipped stylesheet leaves displayed for the message's current view, not a recomputed name.
  const env = laidOut();
  const view = currentPage()
    .document.querySelector("[data-role='own-message']")
    ?.getAttribute("data-view");
  const shownSpan = ["show", "hide"].find((name) => {
    const inView = declarationsFor(
      `.own-message[data-view="${view}"] .own-raw-${name}`,
      env,
    )["display"];
    const base = declarationsFor(`.own-raw-${name}`, env)["display"];
    return (inView ?? base) !== "none";
  });
  const shown = shownSpan === "show" ? "Show raw" : "Show rendered";
  check(shown === label, `the control reads ${shown} in the ${view} view`);
});

step("the visitor's message contains no script element", () => {
  const raw = currentPage().document.querySelector(
    "[data-role='user-message-raw']",
  );
  check(
    raw?.querySelector("script") === null,
    "the raw view holds a script element",
  );
  const rendered = currentPage().document.querySelector(
    "[data-role='user-message']",
  );
  check(
    rendered?.querySelector("script") === null,
    "the rendered view holds a script element",
  );
});

step("the visitor's message contains no javascript link", () => {
  const rendered = currentPage().document.querySelector(
    "[data-role='user-message']",
  );
  // The mailto link must render, so a message with no anchor cannot pass the javascript check.
  check(
    rendered?.querySelectorAll(
      "a[href='mailto:test-user-visitor@example.invalid']",
    ).length === 1,
    "the mailto link is not rendered once",
  );
  check(
    rendered?.querySelector("a[href^='javascript:']") === null,
    "a javascript link is rendered",
  );
});

step("the visitor's message keeps the typed line breaks and spaces", () => {
  const raw = currentPage().document.querySelector(
    "[data-role='user-message-raw']",
  )?.textContent;
  const typed = ownMessageFixture("whitespace").input;
  check(raw === typed, `the raw view is ${JSON.stringify(raw)}`);
  const env = laidOut();
  check(
    declarationsFor(".own-raw", env)["white-space"] === "pre-wrap",
    "the raw view does not keep whitespace",
  );
});

// --- Light appearance ------------------------------------------------------------------------

// The dark preference has no effect because no rule answers it (ADR 005, decision 3).
step("the visitor's system prefers a dark color scheme", () => {
  assertNoDarkPreferenceRule();
});

step("the page has no color theme control", () => {
  assertNoThemeControl();
});

step("the page background is light", () => {
  assertSingleLightAppearance();
  assertPageBackgroundIsLight();
});

// --- Phone layout budget ---------------------------------------------------------------------

function laidOut(): Environment {
  const laid = recall<{
    viewport: { width: number; height: number };
    coarse: boolean;
  }>("codexLaidOut");
  return {
    width: laid.viewport.width,
    height: laid.viewport.height,
    coarse: laid.coarse,
  };
}

// The rows a wrapping header takes are measured by the Playwright adapter. Here the declared rules must make the header a
// flex row, which may wrap once onto a second line on a phone.
step("the Codex header has at most two rows", () => {
  const env = laidOut();
  check(
    declarationsFor(".chat-header", env)["display"] === "flex",
    "the header is not a flex row",
  );
});

step(
  "the header's tab order follows the screen: brand, Options, access state, model badge",
  () => {
    // Keyboard focus follows source order, so the source must match the phone layout. A CSS `order` would move a
    // control on screen without moving it in the source, so no header child may carry one.
    const env = laidOut();
    for (const selector of [
      ".brand-identity",
      ".chat-controls",
      ".chat-access",
      ".model-badge",
      ".chat-options-toggle",
    ]) {
      check(
        (declarationsFor(selector, env)["order"] ?? "0") === "0",
        `${selector} has a CSS order, which moves it on screen`,
      );
    }
    const source = readFileSync(CHAT_TEMPLATE, "utf8");
    const at = [
      "brand-identity",
      "chat-options-toggle",
      "repository-access",
      "model-badge",
    ].map((role) => source.indexOf(role));
    check(
      at.every((index, i) => index >= 0 && (i === 0 || index > at[i - 1]!)),
      `the header source order is ${at.join(", ")}`,
    );
  },
);

step("the brand link is not covered by any header control", () => {
  // The Playwright adapter hit-tests the brand link. Here the source order keeps every other control after the brand
  // on a phone (the layout has no CSS order overrides), and on a wide short window the row does not wrap, so no control
  // can start over the brand.
  const env = laidOut();
  if (env.width > PHONE_WIDTH_PX) {
    check(
      declarationsFor(".chat-header", env)["flex-wrap"] === "nowrap",
      "the header wraps on a wide short window",
    );
    return;
  }
  const source = readFileSync(CHAT_TEMPLATE, "utf8");
  const brand = source.indexOf("brand-identity");
  for (const role of [
    "chat-options-toggle",
    "repository-access",
    "model-badge",
  ]) {
    check(source.indexOf(role) > brand, `${role} is not after the brand`);
  }
  check(
    Number(declarationsFor(".brand-identity", env)["order"] ?? "0") === 0,
    "the brand link is moved in the row",
  );
});

step(
  "the repository access state and the model badge are visible without opening Options",
  () => {
    // Both sit in the header before the Options panel, so the panel's closed state never hides them. On a phone no
    // rule hides them either.
    const env = laidOut();
    if (env.width <= PHONE_WIDTH_PX) {
      for (const selector of [".chat-access", ".model-badge"]) {
        check(
          declarationsFor(selector, env)["display"] !== "none",
          `${selector} is hidden on a phone`,
        );
      }
    }
    const source = readFileSync(CHAT_TEMPLATE, "utf8");
    const badge = source.indexOf('class="model-badge"');
    const panel = source.indexOf('id="chat-options"');
    check(
      source.includes('data-role="repository-access"'),
      "no repository access state in the header",
    );
    check(
      badge !== -1 && panel !== -1 && badge < panel,
      "the model badge sits inside the Options panel",
    );
  },
);

step("the options panel has no fade over its controls", () => {
  // The scrolling row fades its right edge. The panel is not a scrolling row, so the fade must not reach it.
  const env = laidOut();
  check(
    declarationsFor(".chat-actions", env)["mask-image"] === "none",
    `the options panel keeps a fade: ${declarationsFor(".chat-actions", env)["mask-image"]}`,
  );
});

step("the options panel does not cover the repository access state", () => {
  // The panel hangs below the header, so it starts at the header's bottom edge and not over its controls.
  const env = laidOut();
  const top = declarationsFor(".chat-actions", env)["inset-block-start"] ?? "";
  check(
    top.includes("100%"),
    `the options panel starts at ${top}, not below the header`,
  );
  // On a phone the panel is hidden until the visitor opens it, so the panel's controls never cover the header.
  if (env.width <= PHONE_WIDTH_PX) {
    check(
      declarationsFor(".chat-actions", env)["display"] === "none",
      "the options panel is shown while closed",
    );
    check(
      declarationsFor(".chat-actions.is-open", env)["display"] === "flex",
      "an open options panel is not shown",
    );
  }
});

step(
  "the header holds the brand, the repository access state and the options button",
  () => {
    const source = readFileSync(CHAT_TEMPLATE, "utf8");
    for (const role of [
      "brand-identity",
      "chat-access",
      "chat-options-toggle",
    ]) {
      check(source.includes(role), `the header has no ${role}`);
    }
  },
);

step("the options button is at least 44 pixels across and tall", () => {
  const env = laidOut();
  const declared = declarationsFor(".chat-options-toggle", env);
  const height = lengthPx(resolveVars(declared["min-height"] ?? ""), env);
  const width = lengthPx(resolveVars(declared["min-width"] ?? ""), env);
  check(
    height >= TOUCH_TARGET_PX && width >= TOUCH_TARGET_PX,
    `the options button is ${width} by ${height} px`,
  );
});

step("the model selector is on screen in the options panel", () => {
  check(
    readFileSync(CHAT_TEMPLATE, "utf8").includes('id="model-picker"'),
    "no model picker in the panel",
  );
});

step("the reasoning effort selector is on screen in the options panel", () => {
  check(
    readFileSync(CHAT_TEMPLATE, "utf8").includes('id="effort-picker"'),
    "no effort picker in the panel",
  );
});

step("the Clear chat control is on screen in the options panel", () => {
  check(
    /data-role="chat-options"[\s\S]*?data-role="clear-chat"/u.test(
      readFileSync(CHAT_TEMPLATE, "utf8"),
    ),
    "no Clear chat button after the options panel opens in chat_live.ex",
  );
});

step("the options panel is no wider than the screen", () => {
  const env = laidOut();
  const width = lengthPx(
    resolveVars(declarationsFor(".chat-actions", env)["width"] ?? ""),
    env,
  );
  check(
    width <= env.width,
    `the options panel is ${width} px on a ${env.width} px screen`,
  );
});

step(
  "the options panel keeps 12 pixels from the right edge of the screen",
  () => {
    // The header pads its edges by 0.75rem; the panel sits from the header's padding edge, so 0.75rem is the 12 pixel gap.
    const env = laidOut();
    const inset = lengthPx(
      resolveVars(
        declarationsFor(".chat-actions", env)["inset-inline-end"] ?? "",
      ),
      env,
    );
    check(inset === 12, `the options panel is ${inset} px from the right edge`);
  },
);

// A tap leaves :hover on the button, so the fill must come from the `(hover: hover)` rule and not the bare selector.
// Each step's expectation comes from the scenario's pointer, which the Given sets before this Then.
// The hint's text must read on the composer behind it (WCAG AA, 4.5 to 1), using the shipped colour tokens.
step(
  "the send shortcut hint has at least 4.5 to 1 contrast with the composer",
  () => {
    const env = laidOut();
    const ink = resolveVars(
      declarationsFor(".composer-hint", env)["color"] ?? "",
    );
    const background = resolveVars(
      declarationsFor(".composer", env)["background"] ?? "",
    );
    const ratio = contrastRatio(ink, background);
    check(
      ratio >= 4.5,
      `the hint reads ${ratio.toFixed(2)} to 1 on the composer`,
    );
  },
);

step("the Clear chat button does not fill on hover", () => {
  const env = laidOut();
  check(env.coarse, "the scenario's pointer is not a touch pointer");
  const fill = declarationsFor(".clear-chat-button:hover", env)["background"];
  check(
    fill === undefined,
    `the Clear chat hover fill is ${fill} for a touch pointer`,
  );
});

step("the Clear chat button fills on hover", () => {
  const env = laidOut();
  check(!env.coarse, "the scenario's pointer is not a fine pointer");
  const fill = declarationsFor(".clear-chat-button:hover", env)["background"];
  check(
    fill !== undefined,
    "the Clear chat hover fill is absent for a fine pointer",
  );
});

step("every options panel control is at least 44 pixels tall", () => {
  const env = laidOut();
  const height = lengthPx(
    resolveVars(
      declarationsFor(".chat-actions select", env)["min-height"] ?? "",
    ),
    env,
  );
  check(
    height >= TOUCH_TARGET_PX,
    `the options controls are ${height} px tall`,
  );
});

step("the Codex options panel is closed", () => {
  check(
    currentPage()
      .document.querySelector("[data-role='chat-options']")
      ?.classList.contains("is-open") !== true,
    "the options panel is still open",
  );
});

step("the Options button reports it is closed", () => {
  check(
    currentPage()
      .document.querySelector("[data-role='chat-options-toggle']")
      ?.getAttribute("aria-expanded") === "false",
    "the Options button still says it is open",
  );
});

step("the visitor taps the message box", () => {
  click("[data-role='chat-composer']");
});

/** WCAG relative luminance of a `#rrggbb` colour. */
function luminanceOf(hex: string): number {
  const channels = [1, 3, 5].map((offset) => {
    const value = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  const [red = 0, green = 0, blue = 0] = channels;
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

/** The contrast ratio of two `#rrggbb` colours, from 1 to 21. */
function contrastOf(first: string, second: string): number {
  const [light, dark] = [luminanceOf(first), luminanceOf(second)].toSorted(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

/**
 * A declared colour as a `#rrggbb` value. A `var()` is looked up first in the bubble's own declarations (its tokens), then
 * in the shared token layer that `resolveVars` reads.
 */
function colourOf(
  value: string | undefined,
  scope: Record<string, string>,
): string {
  const named = /^var\((--[\w-]+)\)$/u.exec((value ?? "").trim());
  const next = named?.[1] ? (scope[named[1]] ?? value ?? "") : (value ?? "");
  return resolveVars(next);
}

step(
  "the Show raw label is at least 4.5 to 1 against the visitor's bubble",
  () => {
    const env = laidOut();
    const bubble = declarationsFor(".message-visitor", env);
    const ratio = contrastOf(
      colourOf(declarationsFor(".own-raw-toggle", env)["color"], bubble),
      colourOf(bubble["background"], bubble),
    );
    check(ratio >= 4.5, `the Show raw label is ${ratio.toFixed(2)} to 1`);
  },
);

step(
  "the Show raw focus ring is at least 3 to 1 against the visitor's bubble",
  () => {
    const env = laidOut();
    const bubble = declarationsFor(".message-visitor", env);
    const ratio = contrastOf(
      colourOf(bubble["--chat-focus-ring"], bubble),
      colourOf(bubble["background"], bubble),
    );
    check(ratio >= 3, `the Show raw focus ring is ${ratio.toFixed(2)} to 1`);
  },
);

step("an approved admin opens {string}", (pathname) => {
  // The page is served by this template; a scenario on a route with no template is an error, not a pass.
  check(
    readFileSync(templateFor(pathname), "utf8").length > 0,
    `no template serves ${pathname}`,
  );
  remember("openedPath", pathname);
});

step("the visitor's pointer is a fine pointer", () => {
  remember("codexCoarse", false);
});

step("the visitor opens the Codex options panel", () => {
  click("[data-role='chat-options-toggle']");
  check(
    currentPage()
      .document.querySelector("[data-role='chat-options']")
      ?.classList.contains("is-open") === true,
    "the options panel did not open",
  );
});
