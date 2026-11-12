// Step bindings for the `Formatted messages` rule of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature.
//
// The room is the one `family_chat.steps.ts` opens (`support/browser_room.ts`). A message another member sends
// reaches it as the server committed it, carrying the `bodyHtml` the production renderer produced for its body
// (`support/family_chat_rendered_bodies.json`). "The message" a Then reads is the one the scenario's last Given,
// When, or send named; a Then reads only what the room rendered (the body element, its computed style, the roving
// stop), never a value a binding stored.
//
// Two layers stay with the Playwright adapter: an image's load (`naturalWidth`) and a table's real fit in a phone
// width. Here the image element and its address are read, and the shipped stylesheet's declared width rules are
// read through the page's computed style.

import {
  activePage,
  committedFor,
  computedStyleOf,
  device,
  otherMember,
  post,
  rowFor,
  server,
  visitor,
  waitFor,
} from "./support/browser_room";
import { recallOr, remember } from "./support/scenario_memory";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import { replyThroughMenu } from "./family_chat_reply.steps";
import { ownInlineContrast } from "../support/own_bubble";

// The bodies the formatted-message scenarios send. Each has a recorded production rendering in
// `support/family_chat_rendered_bodies.json`; a change to one of them needs that file regenerated.
const TWO_LINES = "First line\nSecond line";
const WIDE_MESSAGE =
  "![Wide banner](https://images.example.test/banner.png)\n\n" +
  "| Day | Dinner | Chores | Notes | Shopping | Reminders |\n" +
  "| --- | --- | --- | --- | --- | --- |\n" +
  "| Monday | Soup and bread | Laundry | Call grandma | Milk, eggs, rice | Dentist at ten |";

const PHONE_WIDTH_PX = 390;

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

export function familyChatMarkdownSteps(): readonly StepDefinition[] {
  return registry;
}

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

/**
 * The row the scenario is about: the message another member sent (remembered by its server id), or the visitor's
 * own send (remembered by its client id, shown pending until it commits). Null while it is not rendered yet.
 */
function targetRow(): HTMLElement | null {
  const key = recallOr<string | null>(
    "markdownTarget",
    recallOr<string | null>("clientMessageId", null),
  );
  if (key === null) throw new Error("no earlier step named a message");
  const committed = committedFor(key);
  return rowFor(committed?.id ?? key);
}

/** The rendered body of the target message; `committed` waits until the server's copy replaces a pending one. */
async function renderedBody(committed = true): Promise<HTMLElement> {
  await waitFor(() => {
    const row = targetRow();
    return (
      row !== null &&
      (!committed || row.dataset["deliveryState"] === "committed")
    );
  }, "the message to render");
  const body = targetRow()?.querySelector<HTMLElement>(
    '[data-role="family-chat-message-body"]',
  );
  if (!body) throw new Error("the message renders no body element");
  return body;
}

function linksIn(body: HTMLElement): HTMLAnchorElement[] {
  return [...body.querySelectorAll<HTMLAnchorElement>("a[href]")];
}

function quoteOf(row: HTMLElement): HTMLElement {
  const quote = row.querySelector<HTMLElement>(
    '[data-role="family-chat-message-quote"]',
  );
  if (!quote) throw new Error("the reply carries no quote");
  return quote;
}

// --- Given and When: who sent what -----------------------------------------------

step("{word} has sent the family chat message {string}", (sender, body) => {
  remember("markdownTarget", post({ body, sender: otherMember(sender) }).id);
});

step("{word} has sent a message typed on two lines", (sender) => {
  remember(
    "markdownTarget",
    post({ body: TWO_LINES, sender: otherMember(sender) }).id,
  );
});

step("{word} has sent a wide image and a wide table", (sender) => {
  remember(
    "markdownTarget",
    post({ body: WIDE_MESSAGE, sender: otherMember(sender) }).id,
  );
});

step(
  "{word} sends the family chat message {string} while the visitor watches",
  async (sender, body) => {
    const message = post({ body, sender: otherMember(sender) });
    remember("markdownTarget", message.id);
    await waitFor(
      () => rowFor(message.id) !== null,
      "the live message to reach the room",
    );
  },
);

step("the server holds the visitor's next message unanswered", () => {
  server().setSendOutcome(visitor().id, "hold");
});

step("the visitor replies to the message with {string}", async (body) => {
  await waitFor(() => targetRow() !== null, "the message to reply to");
  const id = await replyThroughMenu(targetRow() as HTMLElement, body);
  if (id === null) throw new Error("the room refused the reply");
  remember("markdownTarget", id);
});

// --- Then: what the room rendered --------------------------------------------------

// The own bubble's inline elements, each checked for body contrast (the same colours the unit proof reads from the
// shipped stylesheet). The Playwright adapter measures the rendered colours of the same elements.
const OWN_INLINE_ELEMENTS: readonly { label: string; selector: string }[] = [
  { label: "the struck text", selector: ".markdown-body del" },
  { label: "the link", selector: ".markdown-body a" },
  { label: "the inline code", selector: ".markdown-body code" },
  { label: "the quote", selector: ".markdown-body blockquote" },
  { label: "the table cell", selector: ".markdown-body td" },
];

step(
  "the struck text, the link, the inline code, the quote and the table cell each have a contrast ratio of at least 4.5 to 1 on my own bubble",
  async () => {
    // The rendered own body must hold each element, or the contrast of a missing element would pass unseen. The
    // message renders once the server confirms it, so the page is waited on first.
    const { document } = activePage().window;
    await waitFor(
      () =>
        document.querySelector(
          ".family-chat-message--own .markdown-body del",
        ) !== null,
      "the own message's struck text is rendered",
    );
    for (const { label, selector } of OWN_INLINE_ELEMENTS) {
      expect(
        document.querySelector(`.family-chat-message--own ${selector}`) !==
          null,
        `${label} is not in the rendered own message`,
      );
    }
    for (const { label, selector } of OWN_INLINE_ELEMENTS) {
      const ratio = ownInlineContrast(selector);
      expect(
        ratio >= 4.5,
        `${label} is ${ratio.toFixed(2)}:1 on the own bubble`,
      );
    }
  },
);

step("the message shows {string} in bold", async (text) => {
  const body = await renderedBody();
  expect(
    [...body.querySelectorAll("strong")].some(
      (strong) => strong.textContent === text,
    ),
    `no bold ${JSON.stringify(text)} in ${body.innerHTML}`,
  );
});

step("the message links {string} to {string}", async (text, address) => {
  const body = await renderedBody();
  expect(
    linksIn(body).some(
      (link) =>
        link.textContent === text && link.getAttribute("href") === address,
    ),
    `no link ${JSON.stringify(text)} to ${address} in ${body.innerHTML}`,
  );
});

step("the message shows the text {string}", async (text) => {
  const body = await renderedBody();
  expect(
    (body.textContent ?? "").includes(text),
    `the message reads ${JSON.stringify(body.textContent)}`,
  );
});

step("the message contains no script or image element", async () => {
  const body = await renderedBody();
  expect(
    body.querySelector("script, img") === null,
    `the message holds ${body.innerHTML}`,
  );
});

step(
  "the message shows {string} as typed text with no formatting",
  async (text) => {
    const body = await renderedBody(false);
    expect(
      body.dataset["bodyFormat"] === "text",
      `the body is ${String(body.dataset["bodyFormat"])}, not text`,
    );
    expect(
      body.textContent === text && body.children.length === 0,
      `the body reads ${JSON.stringify(body.textContent)}`,
    );
  },
);

step("the message keeps its two lines on separate lines", async () => {
  const body = await renderedBody();
  const text = (body.textContent ?? "").replace(/\s+/gu, " ").trim();
  expect(body.querySelector("br") !== null, "no line break in the message");
  expect(
    text.includes("First line") && text.includes("Second line"),
    `the message reads ${JSON.stringify(text)}`,
  );
});

step("the message shows the image {string} from {string}", async (alt, src) => {
  const body = await renderedBody();
  const image = body.querySelector("img");
  expect(
    image?.getAttribute("alt") === alt && image.getAttribute("src") === src,
    `the message shows ${body.innerHTML}`,
  );
});

step("the message shows no image", async () => {
  const body = await renderedBody();
  expect(
    body.querySelector("img") === null,
    `the message shows an image: ${body.innerHTML}`,
  );
});

step("the links in the message open in a new tab", async () => {
  const body = await renderedBody();
  const links = linksIn(body);
  expect(links.length > 0, "the message has no link");
  for (const link of links) {
    expect(
      link.getAttribute("target") === "_blank" &&
        (link.getAttribute("rel") ?? "").includes("noopener"),
      `the link ${link.outerHTML} does not open in a new tab`,
    );
  }
});

step("the message fits the phone width", async () => {
  const body = await renderedBody();
  const bubble = targetRow()?.querySelector<HTMLElement>(
    ".family-chat-message-bubble",
  );
  if (!bubble) throw new Error("the message has no bubble");
  expect(device().viewport.width === PHONE_WIDTH_PX, "the viewport is not 390");
  // The wide table and image stay inside their bubble, which may shrink below its content.
  const table = body.querySelector<HTMLElement>("table");
  if (!table) throw new Error("the message has no table");
  expect(bubble.contains(table), "the table is outside its bubble");
  expect(
    computedStyleOf(bubble).getPropertyValue("min-width") === "0",
    "the bubble does not allow shrinking",
  );
  expect(
    computedStyleOf(table).getPropertyValue("overflow-x") === "auto",
    "the table does not scroll inside the bubble",
  );
  const image = body.querySelector<HTMLElement>("img");
  if (!image) throw new Error("the message has no image");
  expect(bubble.contains(image), "the image is outside");
  expect(
    computedStyleOf(image).getPropertyValue("max-width") === "100%",
    "the image is not limited to the bubble width",
  );
});

step("the image in the message loads", async () => {
  // This layer reads that the image element carries its address; the request and the decoded size
  // (`naturalWidth`) are the Playwright adapter's.
  const body = await renderedBody();
  const image = body.querySelector("img");
  expect(
    image !== null && (image.getAttribute("src") ?? "") !== "",
    "the message shows no image to load",
  );
});

step("the reply quotes {string} as plain text", async (text) => {
  await renderedBody();
  const quote = quoteOf(targetRow() as HTMLElement);
  const preview = quote.querySelector<HTMLElement>(
    '[data-role="family-chat-message-quote-preview"]',
  );
  expect(preview !== null, "the quote has no preview");
  expect(
    preview?.textContent === text && preview.children.length === 0,
    `the quote reads ${JSON.stringify(preview?.textContent)}`,
  );
});

step("the quote contains no link", async () => {
  await renderedBody();
  const quote = quoteOf(targetRow() as HTMLElement);
  expect(
    quote.querySelector("a, strong, em, code, img, del") === null,
    `the quote holds ${quote.innerHTML}`,
  );
});
