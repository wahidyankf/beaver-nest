// Step bindings for the Rules `Keyboard reach of message content` (FC-02) and `Keyboard reach of the message history`
// of specs/apps/bnest/app-fe/behaviours/family_chat.feature (ADR 003, Decision 6).
//
// Same room as `family_chat.steps.ts` (`support/browser_room.ts`): the production room booted from the shipped
// template, driven by simulated Tab, arrow, Enter, Space and Escape presses. happy-dom has no layout and no
// scrolling, so a scroll region is declared wide or fitting with `declareScrollRegion` before the room renders.
// Moving focus with an arrow, Home or End is checked as the history's scroll position after the key: the focused
// message must sit inside the history's window (`revealInHistory`), or the menu must sit beside it. Keys that
// scroll the page itself are checked as what the page did with the key (it did not cancel it, so the browser
// scrolls). `family_chat_keyboard` is run by the Playwright adapter too, which measures real overflow and real scroll.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  activePage,
  declareScrollRegion,
  declareTallRow,
  HISTORY_HEIGHT_PX,
  heightOfText,
  isRendered,
  messageRows,
  otherMember,
  post,
  pressKey,
  type Page,
} from "./support/browser_room";
import { recall, remember } from "./support/scenario_memory";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import { GAP } from "../../js/family_chat/menu_anchor.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const CSS_DIR = path.resolve(here, "../../css");

// What the scenarios name as content. The Playwright adapter (`tests/support/family-chat-keyboard.ts`) names the same
// things, so a change here is a change there.
const NAMED_KINDS: Readonly<Record<string, string>> = {
  table: "table",
  "code block": "pre",
  diagram: ".bnest-diagram-canvas",
  "quote card": ".family-chat-message-quote",
};

// The selector each named kind is declared wide or fitting by.
const SCROLL_SELECTORS: Readonly<Record<string, string>> = {
  table: "table",
  "code block": "pre",
  diagram: ".bnest-diagram-canvas",
};

// The focus rule each scroll region keeps in the shipped stylesheet (the own-bubble override is a separate rule).
const FOCUS_RING_SUFFIXES: Readonly<Record<string, string>> = {
  table: "table:focus-visible",
  "code block": "pre:focus-visible",
  diagram: ".bnest-diagram-canvas:focus-visible",
};

// A markdown table whose cells are single words far wider than a phone bubble, so it overflows at 390 px.
const WIDE_TABLE = [
  "| Menu | Drink | Dessert | Notes | Seats |",
  "| ---- | ----- | ------- | ----- | ----- |",
  "| Nasigorengkampungspesialbuatkeluargakitasemua | Tehmanisdengansusuhangatbersamakeluarga | Kuehmangkokdaripasarpagihariinisegarsekali | Pedasnyasedanglebihenakdimakanbersama | Tigaorangdewasadanduaanakkecil |",
].join("\n");

const WIDE_CODE = `${"pickup-the-children-from-the-school-gate-".repeat(8)}`;

const WIDE_BODIES: Readonly<Record<string, string>> = {
  table: `Dinner plan:\n\n${WIDE_TABLE}`,
  "code block": `\`\`\`text\n${WIDE_CODE}\n\`\`\``,
};

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

export function familyChatKeyboardSteps(): readonly StepDefinition[] {
  return registry;
}

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

interface LastPress {
  readonly key: string;
  readonly shiftKey: boolean;
  readonly target: Element | null;
  readonly defaultPrevented: boolean;
}

function focusedElement(page: Page): Element {
  const active = page.document.activeElement;
  if (active === null || active === page.document.body) {
    throw new Error("no element holds keyboard focus");
  }
  return active;
}

/** Whether `element` is the named content: a named kind, or a link or summary whose text is the name. */
function isNamed(element: Element, name: string): boolean {
  const selector = NAMED_KINDS[name];
  if (selector !== undefined) return element.matches(selector);
  return (
    element.matches("a[href], summary") &&
    (element.textContent ?? "").trim() === name
  );
}

function describeFocus(element: Element | null): string {
  if (element === null) return "nothing";
  return (
    element.getAttribute("data-role") ??
    element.tagName.toLowerCase() +
      " " +
      (element.textContent ?? "").trim().slice(0, 40)
  );
}

/** The rendered row whose typed body contains `text`. */
function rowWithBody(page: Page, text: string): HTMLElement {
  const row = messageRows(page).find((candidate) =>
    (
      candidate.querySelector('[data-role="family-chat-message-body"]')
        ?.textContent ?? ""
    ).includes(text),
  );
  if (!row)
    throw new Error(`no message shows the text ${JSON.stringify(text)}`);
  return row;
}

function linkNamed(page: Page, text: string): HTMLAnchorElement {
  const link = [
    ...page.elements.list.querySelectorAll<HTMLAnchorElement>("a[href]"),
  ].find((candidate) => (candidate.textContent ?? "").trim() === text);
  if (!link) throw new Error(`no link reads ${JSON.stringify(text)}`);
  return link;
}

function stopsIn(page: Page): HTMLElement[] {
  return [
    ...page.elements.list.querySelectorAll<HTMLElement>(
      '[data-role="family-chat-message"][tabindex="0"]',
    ),
  ];
}

/** The `KeyboardEvent.key` a feature's key name stands for, where the two differ. */
const KEY_VALUES: Readonly<Record<string, string>> = { Space: " " };

/** Presses `key` (with Shift when named) and remembers what the page did with it. */
async function pressAndRemember(combo: string): Promise<void> {
  const shiftKey = combo.startsWith("Shift+");
  const name = shiftKey ? combo.slice("Shift+".length) : combo;
  const key = KEY_VALUES[name] ?? name;
  const target = activePage().document.activeElement;
  const result = await pressKey(key, { shiftKey });
  remember("lastPress", {
    key,
    shiftKey,
    target,
    defaultPrevented: result.defaultPrevented,
  } satisfies LastPress);
}

// --- Given: what the history holds ------------------------------------------------

step("the history holds {int} messages, each with a link", (count) => {
  for (let index = 0; index < Number(count); index += 1) {
    post({
      body: `Note ${index} [link ${index}](https://example.test/${index})`,
      sender: otherMember("Ayah"),
    });
  }
});

// The tall message's text carries this marker; the layout model draws it TALL_ROW_PX tall, taller than the 400 px window.
const TALL_MARKER = "tall-note-marker";
const TALL_ROW_PX = 600;

step(
  "the history holds {int} messages and a message taller than the window follows them",
  (count) => {
    for (let index = 0; index < Number(count); index += 1) {
      post({ body: `Note ${index}`, sender: otherMember("Ayah") });
    }
    declareTallRow(TALL_MARKER, TALL_ROW_PX);
    const tall = post({
      body: `Tall note ${TALL_MARKER}`,
      sender: otherMember("Ayah"),
    });
    // The layout's own lookup must give this message's stored text a height taller than the window. If the marker
    // is missing from the text, the lookup falls back to the ordinary row and this fails.
    const height = heightOfText(tall.body);
    expect(
      height > HISTORY_HEIGHT_PX,
      `the tall message is ${height} px, not taller than the ${HISTORY_HEIGHT_PX} px window`,
    );
  },
);

step("{word} has sent a wide {string} message", (sender, kind) => {
  const body = WIDE_BODIES[kind];
  if (body === undefined) throw new Error(`no wide message is named ${kind}`);
  const selector = SCROLL_SELECTORS[kind];
  if (selector === undefined) throw new Error(`${kind} is not a scroll region`);
  declareScrollRegion(selector, "wide");
  post({ body, sender: otherMember(sender) });
});

step("the {string} in the message is wider than its box", (kind) => {
  const selector = SCROLL_SELECTORS[kind];
  if (selector === undefined) throw new Error(`${kind} is not a scroll region`);
  declareScrollRegion(selector, "wide");
});

step("the {string} in the message fits its box", (kind) => {
  const selector = SCROLL_SELECTORS[kind];
  if (selector === undefined) throw new Error(`${kind} is not a scroll region`);
  declareScrollRegion(selector, "fits");
});

// --- When: the keys ----------------------------------------------------------------

step("the visitor presses {string}", async (combo) => {
  await pressAndRemember(combo);
});

step(
  "the visitor presses {string} until keyboard focus is on {string}",
  async (key, name) => {
    const page = activePage();
    for (let press = 0; press < 8; press += 1) {
      const active = page.document.activeElement;
      if (active !== null && isNamed(active, name)) return;
      await pressAndRemember(key);
    }
    const active = page.document.activeElement;
    expect(
      active !== null && isNamed(active, name),
      `${key} never moved keyboard focus to ${JSON.stringify(name)}; focus is on ${describeFocus(active)}`,
    );
  },
);

// --- Then: where focus is, and what the page did with the key -----------------------

step("keyboard focus is on {string}", (name) => {
  const active = focusedElement(activePage());
  expect(
    isNamed(active, name),
    `keyboard focus is on ${describeFocus(active)}, not ${JSON.stringify(name)}`,
  );
});

step("keyboard focus is on the message {string}", (text) => {
  const page = activePage();
  const active = focusedElement(page);
  expect(
    active === rowWithBody(page, text),
    `keyboard focus is on ${describeFocus(active)}, not the message ${JSON.stringify(text)}`,
  );
});

step("keyboard focus is outside the history", () => {
  const page = activePage();
  const active = page.document.activeElement;
  expect(
    active === null || !page.elements.list.contains(active),
    `keyboard focus is still in the history, on ${describeFocus(active)}`,
  );
});

step("the message {string} is the keyboard stop", (text) => {
  const page = activePage();
  const row = rowWithBody(page, text);
  const stops = stopsIn(page);
  expect(
    stops.length === 1 && stops[0] === row,
    `the keyboard stop is on ${stops.map(describeFocus).join(", ") || "no message"}, not ${JSON.stringify(text)}`,
  );
});

step("exactly one link in the history is a tab stop", () => {
  const page = activePage();
  const reachable = [
    ...page.elements.list.querySelectorAll<HTMLAnchorElement>("a[href]"),
  ].filter((link) => link.tabIndex >= 0);
  expect(
    reachable.length === 1,
    `${reachable.length} links in the history are tab stops`,
  );
});

step("the link {string} opens its address in a new tab", (text) => {
  const press = recall<LastPress>("lastPress");
  const link = linkNamed(activePage(), text);
  expect(
    press.key === "Enter" && press.target === link,
    `the last key was ${press.key} on ${describeFocus(press.target)}, not Enter on the link`,
  );
  expect(
    !press.defaultPrevented,
    "the page cancelled Enter, so the link would not open",
  );
  expect(
    link.getAttribute("target") === "_blank" &&
      (link.getAttribute("rel") ?? "").includes("noopener"),
    `the link ${link.outerHTML} does not open in a new tab`,
  );
});

step("the diagram source is shown", () => {
  const page = activePage();
  const details = page.elements.list.querySelector<HTMLElement>(
    ".bnest-diagram-source",
  );
  const code = details?.querySelector<HTMLElement>("pre");
  expect(
    details?.hasAttribute("open") === true,
    "the diagram source is closed",
  );
  expect(
    code !== null && code !== undefined && isRendered(code),
    "the diagram source is open but not shown",
  );
});

step("the {string} is scrolled to the right", (name) => {
  const press = recall<LastPress>("lastPress");
  expect(
    press.key === "ArrowRight" &&
      press.target !== null &&
      isNamed(press.target, name),
    `the last key was ${press.key} on ${describeFocus(press.target)}, not ArrowRight on the ${name}`,
  );
  // happy-dom does not scroll. What the page can do is decline to cancel the key, which leaves the browser to
  // scroll the focused region; the Playwright adapter measures the scroll itself.
  expect(
    !press.defaultPrevented,
    `the page cancelled ArrowRight on the ${name}`,
  );
  const element = press.target as HTMLElement;
  expect(
    element.scrollWidth > element.clientWidth,
    `the ${name} is not wider than its box, so it has nothing to scroll`,
  );
});

step("the {string} shows a visible focus ring", (name) => {
  const active = focusedElement(activePage());
  expect(
    isNamed(active, name),
    `focus is on ${describeFocus(active)}, not the ${name}`,
  );
  expect(
    focusRingDeclared(FOCUS_RING_SUFFIXES[name] ?? ""),
    `the stylesheet declares no visible focus ring for the ${name}`,
  );
});

// --- The stylesheet's declared focus rings ---------------------------------------------

const CSS_TEXT = ["chat_shared.css", "diagrams.css", "app.css"]
  .map((file) => readFileSync(path.resolve(CSS_DIR, file), "utf8"))
  .join("\n")
  .replace(/\/\*[\s\S]*?\*\//gu, "");

/**
 * Whether a rule that ends in `suffix` (a `:focus-visible` selector) declares an outline other than `none`. A nested
 * `@media` block is read through its innermost rules, which is where the declarations are.
 */
function focusRingDeclared(suffix: string): boolean {
  if (suffix === "") return false;
  for (const match of CSS_TEXT.matchAll(/([^{}]+)\{([^{}]*)\}/gu)) {
    const selectors = (match[1] ?? "").split(",").map((part) => part.trim());
    const declarations = match[2] ?? "";
    const outline = /(?:^|;|\s)outline\s*:\s*([^;]+)/u.exec(declarations)?.[1];
    if (
      selectors.some((selector) => selector.endsWith(suffix)) &&
      outline !== undefined &&
      !/^none\b/u.test(outline.trim())
    ) {
      return true;
    }
  }
  return false;
}

// --- Keyboard moves bring the focused message into view (family_chat.feature, "Keyboard reach of the message history")

step("the history is laid out on the screen", () => {
  // The room opens at its newest message, with the history scrolled to the bottom of its modelled layout. The menu's
  // placement reads the screen size from globalThis, which in this harness is not the room's own window, so the
  // room's screen size is mirrored there, as a browser has the two as one.
  const page = activePage();
  for (const key of ["innerWidth", "innerHeight"] as const) {
    Object.defineProperty(globalThis, key, {
      configurable: true,
      value: page.window[key],
      writable: true,
    });
  }
  const { history } = page.elements;
  expect(
    history.scrollHeight > history.clientHeight,
    "the history does not overflow its window",
  );
  expect(
    history.scrollTop + history.clientHeight >= history.scrollHeight - 1,
    "the room did not open at its newest message",
  );
});

step("the visitor presses {string} {int} times", async (combo, count) => {
  for (let press = 0; press < Number(count); press += 1) {
    // eslint-disable-next-line no-await-in-loop -- each press moves focus before the next one is judged.
    await pressAndRemember(combo);
  }
});

step("the top of the focused message is inside the visible history", () => {
  // A message taller than the window cannot fit in it, so its top edge is what the reader must see first.
  const page = activePage();
  const focused = focusedElement(page);
  const frame = page.elements.history.getBoundingClientRect();
  const row = focused.getBoundingClientRect();
  expect(
    row.top >= frame.top && row.top < frame.bottom,
    `the focused message's top is ${row.top}, outside a history from ${frame.top} to ${frame.bottom}`,
  );
});

/** The number a seeded message's body ends with ("Message 19" is 19), or null when the body does not end in one. */
function bodyNumberOf(element: Element): number | null {
  const body =
    element.querySelector('[data-role="family-chat-message-body"]')
      ?.textContent ?? "";
  const match = /(\d+)\s*$/u.exec(body.trim());
  return match?.[1] === undefined ? null : Number(match[1]);
}

step("the focused message is the message with the number {int}", (number) => {
  const actual = bodyNumberOf(focusedElement(activePage()));
  expect(
    actual === Number(number),
    `the focused message is number ${actual ?? "none"}, not ${number}`,
  );
});

step("the focused message is the newest message", () => {
  const page = activePage();
  const rows = messageRows(page);
  const newest = rows[rows.length - 1];
  expect(
    newest !== undefined && focusedElement(page) === newest,
    `keyboard focus is not on the newest of ${rows.length} messages`,
  );
});

step("the focused message is not the newest message", () => {
  // Proves the arrow presses moved focus away from the newest message, so a later End press is what brings it back.
  const page = activePage();
  const rows = messageRows(page);
  const newest = rows[rows.length - 1];
  const focused = focusedElement(page);
  expect(
    newest !== undefined &&
      rows.length > 1 &&
      focused !== newest &&
      rows.includes(focused as HTMLElement),
    `keyboard focus is on the newest of ${rows.length} messages, or on no message`,
  );
});

step("the focused message is the tall message", () => {
  const body =
    focusedElement(activePage()).querySelector(
      '[data-role="family-chat-message-body"]',
    )?.textContent ?? "";
  expect(
    body.includes("Tall note"),
    `keyboard focus is not on the tall message, its body is ${JSON.stringify(body)}`,
  );
});

step("the history's position is noted", () => {
  remember("noted history position", activePage().elements.history.scrollTop);
});

step("the history has not moved since its position was noted", () => {
  const noted = recall<number>("noted history position");
  const now = activePage().elements.history.scrollTop;
  expect(now === noted, `the history moved from ${noted} to ${now}`);
});

step("the focused message is inside the visible history", () => {
  const page = activePage();
  const focused = focusedElement(page);
  const frame = page.elements.history.getBoundingClientRect();
  const row = focused.getBoundingClientRect();
  expect(
    row.top >= frame.top && row.bottom <= frame.bottom,
    `the focused message spans ${row.top} to ${row.bottom} in a history from ${frame.top} to ${frame.bottom}`,
  );
});

step(
  "the message action menu is beside the focused message inside the screen",
  () => {
    // Enter moves focus into the menu, so the message is read as the history's tab stop.
    const page = activePage();
    const [message] = stopsIn(page);
    const host = page.document.querySelector<HTMLElement>(
      '[data-role="family-chat-message-actions"]',
    );
    if (!message) throw new Error("the history has no tab stop");
    if (!host) throw new Error("no action menu is open");
    const top = Number.parseFloat(host.style.getPropertyValue("--fc-menu-top"));
    const box = message.getBoundingClientRect();
    expect(
      top >= box.top - GAP && top <= box.bottom + GAP,
      `the menu's top is ${top}, beside a message that spans ${box.top} to ${box.bottom}`,
    );
    // The menu's top edge is on the screen. Its bottom edge depends on its laid-out height, which only Chromium
    // measures; the Playwright row checks both edges.
    const screen = globalThis.innerHeight;
    expect(
      top >= 0 && top <= screen,
      `the menu's top is ${top} on a ${screen} px screen`,
    );
  },
);
