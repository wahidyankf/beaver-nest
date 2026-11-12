// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/message_content_stops.js`: which content of a Family Chat message
// is a tab stop, and only for the one message the history's stop is on (ADR 003, Decision 6, rules 2, 3, 5 and 7).
// Each test states one row of that rule and asserts on the attributes a browser would act on.
//
// happy-dom has no layout, so a scroll region's overflow is declared on the element (`scrollWidth` and `clientWidth`)
// the way a browser would measure it. The Playwright adapter measures real overflow.

import { describe, expect, it } from "vitest";
import {
  CONTENT_SELECTORS,
  syncContentStops,
} from "../../../js/family_chat/message_content_stops.js";
import { messageNode } from "../../../js/family_chat/message_render.js";
import { drawnFigure } from "../../../js/diagrams/diagram_figure.js";

const BODY_OPEN =
  '<div phx-r class="message-content markdown-body family-chat-message-body" data-role="family-chat-message-body">';

const LINK_TABLE_CODE_HTML = `${BODY_OPEN}<p><a href="https://example.test/home">home</a></p><table><tr><td>Rice</td></tr></table><pre><code>rice for four</code></pre><ul><li><input type="checkbox" disabled> task</li></ul></div>`;

function messageWith(
  id: string,
  bodyHtml: string,
  replyTo?: { id: string; senderDisplayName: string; bodyPreview: string },
) {
  return messageNode(
    {
      id,
      body: `message ${id}`,
      bodyHtml,
      senderId: "u-ayah",
      senderDisplayName: "Ayah",
      replyTo: replyTo ?? null,
    },
    { pending: false, currentUserId: "u-me" },
  );
}

/** A list of committed messages, the last one the newest. */
function listOf(...items: HTMLElement[]): HTMLElement {
  const list = document.createElement("ol");
  list.append(...items);
  document.body.replaceChildren(list);
  return list;
}

function itemsOf(list: HTMLElement): HTMLElement[] {
  return [
    ...list.querySelectorAll<HTMLElement>('[data-role="family-chat-message"]'),
  ];
}

function within(item: HTMLElement, selector: string): HTMLElement {
  const element = item.querySelector<HTMLElement>(selector);
  if (!element) throw new Error(`no ${selector} in the message`);
  return element;
}

/** Declares an element as overflowing its box, the way a browser measures a wide table, code block or picture. */
function overflow(element: HTMLElement): void {
  Object.defineProperty(element, "scrollWidth", {
    configurable: true,
    value: 1000,
  });
  Object.defineProperty(element, "clientWidth", {
    configurable: true,
    value: 300,
  });
}

/** Declares an element as exactly its box: no overflow, so a browser would not stop on it. */
function fits(element: HTMLElement): void {
  Object.defineProperty(element, "scrollWidth", {
    configurable: true,
    value: 300,
  });
  Object.defineProperty(element, "clientWidth", {
    configurable: true,
    value: 300,
  });
}

describe("CONTENT_SELECTORS", () => {
  it("names the quote card, the body's links, the diagram source, and the scroll regions, and nothing else", () => {
    expect(CONTENT_SELECTORS).toContain(".family-chat-message-quote");
    expect(CONTENT_SELECTORS).toContain(
      '[data-role="family-chat-message-body"] a[href]',
    );
    expect(CONTENT_SELECTORS).toContain(".bnest-diagram-source > summary");
    expect(CONTENT_SELECTORS).toContain(
      '[data-role="family-chat-message-body"] table',
    );
    expect(CONTENT_SELECTORS).toContain(
      '[data-role="family-chat-message-body"] pre',
    );
    expect(CONTENT_SELECTORS).toContain(
      '[data-role="family-chat-message-body"] .bnest-diagram-canvas',
    );
    expect(CONTENT_SELECTORS).not.toMatch(/input|checkbox|button:not/u);
  });
});

describe("syncContentStops: a message that is not the stop", () => {
  it("keeps its links, quote card, diagram source, and scroll regions out of the tab order", () => {
    const quoted = messageWith("2", LINK_TABLE_CODE_HTML, {
      id: "1",
      senderDisplayName: "Bunda",
      bodyPreview: "earlier",
    });
    const stop = messageWith("3", `${BODY_OPEN}<p>plain</p></div>`);
    const list = listOf(quoted, stop);
    // Raised by an earlier stop: the sync must lower them again.
    within(quoted, "a[href]").tabIndex = 0;
    within(quoted, "table").tabIndex = 0;

    syncContentStops(itemsOf(list), stop);

    expect(within(quoted, "a[href]").tabIndex).toBe(-1);
    expect(within(quoted, "table").tabIndex).toBe(-1);
    expect(within(quoted, ".family-chat-message-quote").tabIndex).toBe(-1);
  });

  it("sets a scroll region to -1 explicitly, even when it does not overflow", () => {
    const other = messageWith("2", LINK_TABLE_CODE_HTML);
    const stop = messageWith("3", `${BODY_OPEN}<p>plain</p></div>`);
    const list = listOf(other, stop);
    fits(within(other, "table"));

    syncContentStops(itemsOf(list), stop);

    expect(within(other, "table").getAttribute("tabindex")).toBe("-1");
    expect(within(other, "pre").getAttribute("tabindex")).toBe("-1");
  });
});

describe("syncContentStops: the stop message", () => {
  it("raises its quote card, links, and diagram source", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML, {
      id: "1",
      senderDisplayName: "Bunda",
      bodyPreview: "earlier",
    });
    const list = listOf(stop);

    syncContentStops(itemsOf(list), stop);

    expect(within(stop, ".family-chat-message-quote").tabIndex).toBe(0);
    expect(within(stop, "a[href]").tabIndex).toBe(0);
  });

  it("raises a table or code block only while it overflows", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    overflow(within(stop, "table"));
    fits(within(stop, "pre"));

    syncContentStops(itemsOf(list), stop);

    expect(within(stop, "table").tabIndex).toBe(0);
    expect(within(stop, "pre").tabIndex).toBe(-1);
  });

  it("gives a wide code block a group role and a name, so a screen reader announces what it is", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    overflow(within(stop, "pre"));

    syncContentStops(itemsOf(list), stop);

    const code = within(stop, "pre");
    expect(code.tabIndex).toBe(0);
    expect(code.getAttribute("role")).toBe("group");
    expect(code.getAttribute("aria-label")).toBe("Code, scrollable");
  });

  it("names a wide table that has no name, and keeps the name it has", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    const table = within(stop, "table");
    overflow(table);

    syncContentStops(itemsOf(list), stop);
    expect(table.getAttribute("aria-label")).toBe("Table, scrollable");

    table.setAttribute("aria-label", "Dinner menu");
    syncContentStops(itemsOf(list), stop);
    expect(table.getAttribute("aria-label")).toBe("Dinner menu");
  });

  it("does not make a task checkbox, the actions button, or a retry control reachable", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    const checkbox = within(stop, 'input[type="checkbox"]');
    checkbox.tabIndex = -1;

    syncContentStops(itemsOf(list), stop);

    expect(checkbox.tabIndex).toBe(-1);
    expect(
      within(stop, '[data-role="family-chat-message-more"]').tabIndex,
    ).toBe(-1);
  });
});

describe("syncContentStops: moving the stop and changing what is measured", () => {
  it("lowers the old stop's content when the stop moves to another message", () => {
    const first = messageWith("2", LINK_TABLE_CODE_HTML);
    const second = messageWith(
      "3",
      `${BODY_OPEN}<p><a href="https://example.test/x">x</a></p></div>`,
    );
    const list = listOf(first, second);
    overflow(within(first, "table"));

    syncContentStops(itemsOf(list), first);
    expect(within(first, "table").tabIndex).toBe(0);

    syncContentStops(itemsOf(list), second);
    expect(within(first, "table").tabIndex).toBe(-1);
    expect(within(second, "a[href]").tabIndex).toBe(0);
    expect(within(first, "a[href]").tabIndex).toBe(-1);
  });

  it("removes a name it added when the region stops being the stop's", () => {
    const first = messageWith("2", LINK_TABLE_CODE_HTML);
    const second = messageWith("3", `${BODY_OPEN}<p>plain</p></div>`);
    const list = listOf(first, second);
    overflow(within(first, "pre"));

    syncContentStops(itemsOf(list), first);
    expect(within(first, "pre").getAttribute("aria-label")).toBe(
      "Code, scrollable",
    );

    syncContentStops(itemsOf(list), second);
    expect(within(first, "pre").hasAttribute("aria-label")).toBe(false);
    expect(within(first, "pre").hasAttribute("role")).toBe(false);
  });

  it("is idempotent: a second sync over the same DOM changes nothing", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    overflow(within(stop, "table"));
    syncContentStops(itemsOf(list), stop);
    const before = list.innerHTML;

    syncContentStops(itemsOf(list), stop);

    expect(list.innerHTML).toBe(before);
  });

  it("adds and removes no node, so its own attribute changes cannot re-trigger the observer", () => {
    const stop = messageWith("3", LINK_TABLE_CODE_HTML);
    const list = listOf(stop);
    const nodesBefore = list.querySelectorAll("*").length;

    syncContentStops(itemsOf(list), stop);

    expect(list.querySelectorAll("*").length).toBe(nodesBefore);
  });

  it("raises a diagram canvas and its source once the picture overflows", () => {
    const stop = messageWith("3", `${BODY_OPEN}<p>plain</p></div>`);
    const list = listOf(stop);
    const figure = drawnFigure({
      image: {
        src: "data:image/svg+xml;charset=utf-8,%3Csvg%3E%3C%2Fsvg%3E",
        width: 500,
        height: 200,
      },
      kind: "Flowchart",
      source: "flowchart TD",
      focusable: false,
    });
    within(stop, '[data-role="family-chat-message-body"]').append(figure);
    syncContentStops(itemsOf(list), stop);
    expect(
      figure.querySelector<HTMLElement>(".bnest-diagram-canvas")!.tabIndex,
    ).toBe(-1);

    overflow(figure.querySelector<HTMLElement>(".bnest-diagram-canvas")!);
    syncContentStops(itemsOf(list), stop);

    expect(
      figure.querySelector<HTMLElement>(".bnest-diagram-canvas")!.tabIndex,
    ).toBe(0);
    expect(
      figure.querySelector<HTMLElement>(".bnest-diagram-source > summary")!
        .tabIndex,
    ).toBe(0);
  });
});
