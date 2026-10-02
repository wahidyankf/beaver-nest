// Step bindings for the reply scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature -- the `Message
// actions`, `Composing a reply`, `Reading a reply`, and `Keyboard reach of
// the message history` rules, plus the offline-queue, compatibility, and
// rollback scenarios that carry a reply.
//
// Same room as `family_chat.steps.ts` (`support/browser_room.ts`): the
// production room booted from the shipped template, driven by the member's
// own pointer and keys.

import { STATUS } from "../../js/family_chat/outbox.js";
import { rovingInvariantHolds } from "../../js/family_chat/roving_focus.js";
import type { StepDefinition, StepHandler } from "./family_chat.steps";

// What the room says, word for word as a member reads it. Compared as
// literals rather than through the production constants, so rewording
// one is a visible change a scenario catches.
const COPIED_ANNOUNCEMENT = "Message copied.";
const COPY_REFUSED_ANNOUNCEMENT = "Couldn't copy. Select the text manually.";
const REPLY_UNAVAILABLE_REASON = "Send this message before replying to it";
const JUMP_REFUSED_REMEDIATION = "That message is too far back to jump to.";
import {
  activePage,
  announcement,
  clickOn,
  closeWorld,
  committedFor,
  computedStyleOf,
  device,
  dropSockets,
  hasActivePage,
  hidden,
  isInView,
  isRendered,
  messageRows,
  namespaceOf,
  openRoomPage,
  otherMember,
  type Member,
  type Page,
  pointerDown,
  pointerMove,
  pointerUp,
  post,
  type PostOptions,
  pressKey,
  reconnectSockets,
  reloadPage,
  requireRow,
  routeRevision,
  rowFor,
  server,
  setDeviceOnline,
  settle,
  shownStatus,
  tabOrder,
  typeText,
  visibleRemediation,
  visitor,
  waitFor,
  watchPendingRows,
} from "./support/browser_room";
import { forgetScenario, recall, remember } from "./support/scenario_memory";

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

export function familyChatReplySteps(): readonly StepDefinition[] {
  return registry;
}

/** Tears the scenario's pages and memory down, whether it passed or not. */
export async function resetScenario(): Promise<void> {
  forgetScenario();
  await closeWorld();
}

// --- Shared helpers -------------------------------------------------------

const AYAH = (): Member => otherMember("Ayah");

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

type Seed = Omit<PostOptions, "sender"> & { from?: "visitor" | "ayah" };

/**
 * Seeds the conversation the server holds and opens the room on it,
 * remembering the newest seeded message as the one the scenario names.
 */
async function open(
  seed: Seed[] = [],
  options: { replies?: boolean } = {},
): Promise<Page> {
  routeRevision(options.replies ?? true);
  for (const { from, ...message } of seed) {
    post({
      ...message,
      ...(message.senderKind === "system"
        ? {}
        : { sender: from === "visitor" ? visitor() : AYAH() }),
    });
  }
  const page = await openRoomPage();
  const newest = server().newest();
  if (newest) {
    remember("targetId", newest.id);
    remember("targetBody", newest.body);
  }
  return page;
}

function targetId(): string {
  return recall<string>("targetId");
}

function messageElement(messageId: string): HTMLElement {
  return requireRow(messageId);
}

function requireTarget(): HTMLElement {
  return messageElement(targetId());
}

function menuHost(): HTMLElement {
  return activePage().elements.messageActions;
}

function menuButtons(host: HTMLElement = menuHost()): HTMLButtonElement[] {
  return [
    ...host.querySelectorAll<HTMLButtonElement>(
      '[data-role="family-chat-message-action"]',
    ),
  ];
}

async function openMenuOn(element: HTMLElement): Promise<void> {
  const more = element.querySelector<HTMLElement>(
    '[data-role="family-chat-message-more"]',
  );
  if (!more) throw new Error("the rendered message has no actions control");
  await clickOn(more);
}

async function chooseMenuItem(label: string): Promise<void> {
  const button = menuButtons().find((item) => item.textContent === label);
  if (!button) throw new Error(`the menu offers no ${JSON.stringify(label)}`);
  await clickOn(button);
}

function quoteIn(element: HTMLElement): HTMLElement {
  const quote = element.querySelector<HTMLElement>(
    '[data-role="family-chat-message-quote"]',
  );
  if (!quote) throw new Error("the rendered message carries no quote");
  return quote;
}

function graphemeCount(text: string): number {
  return [
    ...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text),
  ].length;
}

/** Replies to the named message the way a member does: menu, Reply, type, Send. */
async function replyThroughMenu(
  target: HTMLElement,
  body: string,
): Promise<string | null> {
  const page = activePage();
  await openMenuOn(target);
  await chooseMenuItem("Reply");
  const queued = watchPendingRows(page);
  typeText(body);
  await clickOn(page.elements.send);
  await waitFor(() => queued.length > 0, "the reply to be queued");
  return queued[0] ?? null;
}

function historyQueries(): number {
  return server().queries.filter(
    (query) =>
      query.operation === "FamilyChatMessages" &&
      query.memberId === visitor().id,
  ).length;
}

// --- Rule: Message actions ------------------------------------------------

step(
  "a visitor opens {string} with at least one committed message",
  async () => {
    await open([{ body: "Dinner is ready" }]);
  },
);

step(
  "the visitor presses and holds for {int} milliseconds on that message",
  async (duration) => {
    const page = activePage();
    const element = requireTarget();
    pointerDown(element);
    page.clock.advance(Number(duration));
    await settle();
  },
);

step("the visitor opens the browser context menu on that message", async () => {
  const page = activePage();
  requireTarget().dispatchEvent(
    new page.window.MouseEvent("contextmenu", {
      bubbles: true,
      cancelable: true,
    }) as unknown as Event,
  );
  await settle();
});

step(
  "the visitor activates the actions control revealed on hover on that message",
  async () => {
    await openMenuOn(requireTarget());
  },
);

step(
  "the visitor moves focus to the message and presses Enter on that message",
  async () => {
    requireTarget().focus();
    await pressKey("Enter");
  },
);

step("the message action menu opens for that message", () => {
  const host = menuHost();
  expect(!hidden(host), "the action menu did not open");
  expect(
    host.dataset["messageId"] === targetId(),
    `the menu opened for ${String(host.dataset["messageId"])}, not ${targetId()}`,
  );
});

step("keyboard focus is inside the menu", () => {
  const active = activePage().document.activeElement;
  expect(
    active !== null && menuHost().contains(active),
    "keyboard focus is not inside the menu",
  );
});

step("the message action menu is open for a committed message", async () => {
  await open([{ body: "Dinner is ready" }]);
  await openMenuOn(requireTarget());
});

step("the visitor presses Escape", async () => {
  await pressKey("Escape");
});

step("the menu closes", () => {
  expect(hidden(menuHost()), "the action menu is still open");
});

step("keyboard focus is on that same message", () => {
  expect(
    activePage().document.activeElement === requireTarget(),
    "keyboard focus did not return to the message the menu came from",
  );
});

step(
  "the visitor presses a message and moves more than {int} pixels before releasing",
  async (tolerance) => {
    const page = activePage();
    const [element] = messageRows(page);
    if (!element) throw new Error("the room shows no message to press");
    pointerDown(element, { clientX: 40, clientY: 80 });
    pointerMove(element, { clientX: 40, clientY: 80 + Number(tolerance) + 1 });
    page.clock.advance(1000);
    pointerUp(element);
    await settle();
  },
);

step("no action menu opens", () => {
  expect(hidden(menuHost()), "a menu opened for a press that became a scroll");
});

step("the message action menu is open for one committed message", async () => {
  await open([
    { body: "Dinner is ready" },
    { body: "On my way", from: "visitor" },
  ]);
  const [first, second] = server().messages;
  if (!first || !second)
    throw new Error("the room was seeded with too few messages");
  remember("targetId", first.id);
  remember("secondId", second.id);
  await openMenuOn(messageElement(first.id));
});

step("the visitor opens the menu on a different message", async () => {
  await openMenuOn(messageElement(recall<string>("secondId")));
});

step("only the second message has an open menu", () => {
  const hosts = activePage().document.querySelectorAll(
    '[data-role="family-chat-message-actions"]',
  );
  expect(hosts.length === 1, `the room rendered ${hosts.length} menu hosts`);
  expect(!hidden(menuHost()), "the second message has no open menu");
  expect(
    menuHost().dataset["messageId"] === recall<string>("secondId"),
    "the menu is still open for the first message",
  );
});

step("the visitor opens the action menu on that message", async () => {
  await openMenuOn(requireTarget());
});

step("the menu offers exactly {string} and {string}", (first, second) => {
  const labels = menuButtons().map((item) => item.textContent);
  expect(
    labels.length === 2 && labels[0] === first && labels[1] === second,
    `the menu offers ${JSON.stringify(labels)}`,
  );
});

step("both actions are available", () => {
  const disabled = menuButtons().filter(
    (item) => item.getAttribute("aria-disabled") === "true",
  );
  expect(
    disabled.length === 0,
    "an action is unavailable on a committed message",
  );
});

step("the visitor's own message is in the {string} state", async (state) => {
  await open([{ body: "Dinner is ready" }]);
  const page = activePage();
  // Each state is reached the way the room really reaches it.
  if (state === "Waiting for connection") setDeviceOnline(page.device, false);
  if (state === "Sending") server().setSendOutcome(visitor().id, "hold");
  if (state === "Retrying") server().setSendOutcome(visitor().id, "offline");
  if (state === "Couldn't send") {
    server().setSendOutcome(visitor().id, { code: "VALIDATION_FAILED" });
  }
  const queued = watchPendingRows(page);
  page.elements.input.focus();
  typeText("Oke");
  await clickOn(page.elements.send);
  await waitFor(() => queued.length > 0, "the message to be queued");
  const id = queued[0] ?? "";
  remember("targetId", id);
  const shown = state === "Retrying" ? STATUS.RETRYING : state;
  await waitFor(
    () => shownStatus(requireRow(id)) === shown,
    `the message to show ${JSON.stringify(shown)}`,
  );
});

step("the visitor opens the action menu on it", async () => {
  await openMenuOn(requireTarget());
});

step("{string} is present and unavailable", (label) => {
  const button = menuButtons().find((item) => item.textContent === label);
  expect(
    button !== undefined,
    `the menu does not offer ${JSON.stringify(label)}`,
  );
  expect(
    button?.getAttribute("aria-disabled") === "true",
    `${JSON.stringify(label)} is available on a message that is not committed`,
  );
});

step(
  "the menu states that the message must send before it can be replied to",
  () => {
    const button = menuButtons().find((item) => item.textContent === "Reply");
    expect(
      button?.getAttribute("aria-description") === REPLY_UNAVAILABLE_REASON,
      `the menu gives no reason: ${String(button?.getAttribute("aria-description"))}`,
    );
  },
);

function expectAvailable(label: string): void {
  const button = menuButtons().find((item) => item.textContent === label);
  expect(
    button !== undefined,
    `the menu does not offer ${JSON.stringify(label)}`,
  );
  expect(
    button?.getAttribute("aria-disabled") !== "true",
    `${JSON.stringify(label)} is unavailable`,
  );
}

step("{string} remains available", (label) => {
  expectAvailable(label);
});

step("the room holds a committed system message", async () => {
  await open([{ body: "Bunda joined the room", senderKind: "system" }]);
});

step("{string} is available", (label) => {
  expectAvailable(label);
});

step(
  "the visitor opens the action menu on a message whose body is {string}",
  async (body) => {
    await open([{ body }]);
    await openMenuOn(requireTarget());
  },
);

step("the visitor chooses {string}", async (label) => {
  await chooseMenuItem(label);
});

step("the clipboard holds exactly {string}", async (expected) => {
  const { clipboard } = device();
  await waitFor(() => clipboard.writes.length > 0, "a clipboard write");
  expect(
    clipboard.writes.length === 1 && clipboard.writes[0] === expected,
    `the clipboard holds ${JSON.stringify(clipboard.writes)}`,
  );
});

step("the room announces that the message was copied", async () => {
  await waitFor(
    () => announcement() === COPIED_ANNOUNCEMENT,
    "the copy announcement",
  );
});

step("the browser refuses clipboard write access", async () => {
  device().clipboard.refuse = true;
  await open([{ body: "Dinner is ready" }]);
});

step("the visitor chooses {string} on a committed message", async (label) => {
  await openMenuOn(requireTarget());
  await chooseMenuItem(label);
});

step("the room states that the text could not be copied", async () => {
  await waitFor(
    () => announcement() === COPY_REFUSED_ANNOUNCEMENT,
    "the refused-copy announcement",
  );
});

// --- Rule: Composing a reply ----------------------------------------------

step(
  "the visitor opens the action menu on a message from {string} reading {string}",
  async (sender, body) => {
    routeRevision(true);
    post({ body, sender: otherMember(sender) });
    await open();
    await openMenuOn(requireTarget());
  },
);

step("the composer shows a reply strip naming {string}", (sender) => {
  const { elements } = activePage();
  expect(!hidden(elements.replyStrip), "the reply strip is not showing");
  expect(
    elements.replyStripName.textContent === `Replying to ${sender}`,
    `the strip reads ${JSON.stringify(elements.replyStripName.textContent)}`,
  );
});

step("the strip shows the text of that message", () => {
  const { elements } = activePage();
  expect(
    elements.replyStripPreview.textContent === recall<string>("targetBody"),
    `the strip shows ${JSON.stringify(elements.replyStripPreview.textContent)}`,
  );
});

step("keyboard focus is in the message input", () => {
  const page = activePage();
  expect(
    page.document.activeElement === page.elements.input,
    "keyboard focus is not in the message input",
  );
});

step(
  "the room announces that the visitor is replying to {string}",
  (sender) => {
    expect(
      announcement() === `Replying to ${sender}.`,
      `the room announced ${JSON.stringify(announcement())}`,
    );
  },
);

step("the selected message body is {int} graphemes long", async (length) => {
  await open([{ body: "a".repeat(Number(length)) }]);
});

step("the reply strip renders it", async () => {
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
});

step("at most {int} graphemes are shown before the ellipsis", (budget) => {
  const shown = activePage().elements.replyStripPreview.textContent ?? "";
  // The graphemes kept before the one ellipsis that marks the cut, as the
  // backend driver's `quote_preview_within_budget` counts them.
  const kept = shown.endsWith("…") ? shown.slice(0, -1) : shown;
  expect(
    graphemeCount(kept) <= Number(budget),
    `the strip shows ${graphemeCount(kept)} graphemes before the ellipsis`,
  );
});

step("the shown text ends with an ellipsis", () => {
  expect(
    (activePage().elements.replyStripPreview.textContent ?? "").endsWith("…"),
    "the shortened preview does not end with an ellipsis",
  );
});

step("the composer shows a reply strip", async () => {
  await open([{ body: "Nanti aku jemput jam 5" }]);
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
  expect(
    !hidden(activePage().elements.replyStrip),
    "the reply strip did not open",
  );
});

step("the visitor has typed {string} without sending", (draft) => {
  const page = activePage();
  page.elements.input.focus();
  typeText(draft);
});

step("the visitor activates the cancel control on the strip", async () => {
  await clickOn(activePage().elements.replyStripCancel);
});

step("the visitor presses Escape in the message input", async () => {
  const page = activePage();
  page.elements.input.focus();
  await pressKey("Escape");
});

step("the reply strip is gone", () => {
  expect(
    hidden(activePage().elements.replyStrip),
    "the reply strip is still showing",
  );
});

step("the message input still holds {string}", (draft) => {
  const { input } = activePage().elements;
  expect(
    input.value === draft,
    `the input holds ${JSON.stringify(input.value)}`,
  );
});

step("no reply strip is shown", async () => {
  await settle();
  expect(
    hidden(activePage().elements.replyStrip),
    "a reply strip is still showing",
  );
});

async function sendAndCommit(body: string): Promise<string> {
  const page = activePage();
  const queued = watchPendingRows(page);
  page.elements.input.focus();
  typeText(body);
  await clickOn(page.elements.send);
  await waitFor(() => queued.length > 0, "the message to be queued");
  const id = queued[0] ?? "";
  await waitFor(() => committedFor(id) !== undefined, "the message to commit");
  await settle();
  return id;
}

step("the visitor sends the message", async () => {
  await sendAndCommit("Oke");
  expect(
    hidden(activePage().elements.replyStrip),
    "the reply strip stayed after sending",
  );
});

step("the next message the visitor sends carries no reply target", async () => {
  const id = await sendAndCommit("Dan satu lagi");
  const attempt = server().sendAttempts.find(
    (candidate) => candidate.clientMessageId === id,
  );
  expect(
    attempt?.replyToMessageId === undefined,
    `the next message was sent replying to ${String(attempt?.replyToMessageId)}`,
  );
  expect(
    committedFor(id)?.replyTo === null,
    "the next message committed as a reply",
  );
});

// --- Rule: Reading a reply ------------------------------------------------

const ORIGINAL = "Nanti aku jemput jam 5";

step("another member has replied to one of the visitor's messages", () => {
  routeRevision(true);
  const original = post({ body: ORIGINAL, sender: visitor() });
  remember("targetId", original.id);
  remember("targetBody", ORIGINAL);
});

/** Ayah's reply, committed now. */
function commitReply(): void {
  const reply = post({
    body: "Oke, aku siap",
    sender: AYAH(),
    replyToMessageId: targetId(),
  });
  remember("replyId", reply.id);
}

step(
  "the reply reaches the visitor through the first history page",
  async () => {
    commitReply();
    await openRoomPage();
  },
);

step(
  "the reply reaches the visitor through an older history page",
  async () => {
    commitReply();
    for (let index = 0; index < 55; index += 1) {
      post({ body: `Filler ${index}`, sender: AYAH() });
    }
    const page = await openRoomPage();
    const replyId = recall<string>("replyId");
    expect(rowFor(replyId) === null, "the reply was already on the first page");
    for (
      let pageLoad = 0;
      pageLoad < 5 && rowFor(replyId) === null;
      pageLoad += 1
    ) {
      await clickOn(page.elements.loadOlder);
      await settle();
    }
  },
);

step(
  "the reply reaches the visitor through the live subscription",
  async () => {
    await openRoomPage();
    commitReply();
    await settle();
  },
);

step(
  "the reply reaches the visitor through reconnect catch-up after a dropped socket",
  async () => {
    const page = await openRoomPage();
    dropSockets(page);
    // Committed while the socket is gone: no push can carry it.
    commitReply();
    expect(
      rowFor(recall<string>("replyId")) === null,
      "the reply arrived by push",
    );
    reconnectSockets(page);
    await settle();
  },
);

step("the reply renders a quote naming the original sender", async () => {
  const replyId = recall<string>("replyId");
  await waitFor(() => rowFor(replyId) !== null, "the reply to render");
  const sender = quoteIn(messageElement(replyId)).querySelector(
    '[data-role="family-chat-message-quote-sender"]',
  );
  expect(
    sender?.textContent === visitor().displayName,
    `the quote names ${JSON.stringify(sender?.textContent)}`,
  );
});

step("the quote shows the original message text", () => {
  const preview = quoteIn(
    messageElement(recall<string>("replyId")),
  ).querySelector('[data-role="family-chat-message-quote-preview"]');
  expect(
    preview?.textContent === recall<string>("targetBody"),
    `the quote shows ${JSON.stringify(preview?.textContent)}`,
  );
});

step("message A exists", async () => {
  await open([{ body: "Message A" }]);
});

step("message B is a reply to A", () => {
  const b = post({
    body: "Message B",
    sender: visitor(),
    replyToMessageId: targetId(),
  });
  remember("replyId", b.id);
});

step("a reply to B is rendered", async () => {
  const c = post({
    body: "Message C",
    sender: AYAH(),
    replyToMessageId: recall<string>("replyId"),
  });
  remember("thirdId", c.id);
  await waitFor(() => rowFor(c.id) !== null, "the reply to B to render");
  expect(
    messageRows().length === 3,
    `the room rendered ${messageRows().length} messages`,
  );
});

step("that reply shows a quote of B", () => {
  const quote = quoteIn(messageElement(recall<string>("thirdId")));
  expect(
    quote.dataset["targetMessageId"] === recall<string>("replyId"),
    `the quote points at ${String(quote.dataset["targetMessageId"])}`,
  );
});

step("that quote shows no quote of its own", () => {
  const quote = quoteIn(messageElement(recall<string>("thirdId")));
  expect(
    quote.querySelector('[data-role="family-chat-message-quote"]') === null,
    "the quote card nests a second quote",
  );
});

async function openWithDistantReply(
  distance: number,
  label: string,
): Promise<void> {
  routeRevision(true);
  const original = post({ body: `${label} original`, sender: visitor() });
  remember("targetId", original.id);
  for (let index = 0; index < distance; index += 1) {
    post({ body: `${label} ${index}`, sender: AYAH() });
  }
  const reply = post({
    body: `${label} reply`,
    sender: AYAH(),
    replyToMessageId: original.id,
  });
  remember("replyId", reply.id);
  await openRoomPage();
  expect(rowFor(reply.id) !== null, "the reply is not on the first page");
}

step("a reply and the message it quotes are both loaded", async () => {
  await openWithDistantReply(10, "Jump");
  expect(rowFor(targetId()) !== null, "the quoted message is not loaded");
});

step(
  "a reply quotes a message two older pages above the loaded window",
  async () => {
    await openWithDistantReply(110, "Distance");
    // The premise, asserted rather than assumed.
    expect(
      rowFor(targetId()) === null,
      "the quoted message was inside the loaded window",
    );
    remember("queriesBeforeJump", historyQueries());
  },
);

step(
  "a reply quotes a message more than five older pages above the loaded window",
  async () => {
    await openWithDistantReply(320, "Unreachable");
    remember("queriesBeforeJump", historyQueries());
  },
);

step("the visitor activates the quote", async () => {
  await clickOn(quoteIn(messageElement(recall<string>("replyId"))));
  await settle();
});

async function expectScrolledTo(id: string): Promise<void> {
  await waitFor(
    () => activePage().scrolledTo.includes(id),
    "the history to scroll to the quoted message",
  );
  expect(isInView(messageElement(id)), "the quoted message is not in view");
}

step("the history scrolls to the original message", async () => {
  await expectScrolledTo(targetId());
});

step("that message is highlighted", async () => {
  await waitFor(
    () => requireTarget().dataset["jumpHighlight"] !== undefined,
    "the quoted message to be highlighted",
  );
});

step("keyboard focus moves to it", async () => {
  await waitFor(
    () => activePage().document.activeElement === requireTarget(),
    "keyboard focus to move to the quoted message",
  );
});

step("older pages are loaded until the original is present", async () => {
  await waitFor(
    () => rowFor(targetId()) !== null,
    "the quoted message to be paged in",
  );
});

step("the history scrolls to it", async () => {
  await expectScrolledTo(targetId());
});

step("no more than five older pages are requested", async () => {
  await settle();
  const requested = historyQueries() - recall<number>("queriesBeforeJump");
  expect(requested <= 5, `the jump requested ${requested} older pages`);
  expect(requested > 0, "the jump requested no older page at all");
});

step(
  "the room states that the message is too far back to jump to",
  async () => {
    await waitFor(
      () => announcement() === JUMP_REFUSED_REMEDIATION,
      "the refused-jump announcement",
    );
    // "States" has to reach a reader who is looking at the screen too.
    await waitFor(
      () => visibleRemediation() === JUMP_REFUSED_REMEDIATION,
      "the refused-jump remediation a sighted reader can see",
    );
  },
);

step("the visitor's system requests reduced motion", () => {
  // The device's media preference: every page this device opens from now
  // on resolves `prefers-reduced-motion: reduce` against the shipped CSS.
  device().reducedMotion = true;
});

step("the visitor jumps to a quoted message", async () => {
  await openWithDistantReply(5, "Reduced motion");
  await clickOn(quoteIn(messageElement(recall<string>("replyId"))));
  await expectScrolledTo(targetId());
});

step("the message is marked without an animated pulse", () => {
  const target = requireTarget();
  expect(
    target.dataset["jumpHighlight"] !== undefined,
    "the quoted message carries no highlight marker",
  );
  const style = computedStyleOf(target);
  expect(
    style.outlineStyle !== "none" && style.outlineStyle !== "",
    "the highlight shows no mark at all",
  );
  expect(
    style.animation === "none" || style.animation === "",
    `the highlight still animates: ${style.animation}`,
  );
  expect(
    !style.animation.includes("family-chat-jump-pulse"),
    "the highlight pulses under reduced motion",
  );
});

// --- Rule: Keyboard reach of the message history --------------------------

/** Every element focus visited in a keyboard journey, in order. */
function recordFocus(trail: HTMLElement[]): void {
  const active = activePage().document.activeElement as HTMLElement | null;
  if (active) trail.push(active);
}

async function pressAndRecord(
  trail: HTMLElement[],
  key: string,
): Promise<void> {
  await pressKey(key);
  recordFocus(trail);
}

step("a visitor opens {string} using only a keyboard", async () => {
  await open([{ body: ORIGINAL }]);
});

step(
  "the visitor moves focus into the history, selects a message, opens the menu, chooses {string}, types, and sends",
  async (label) => {
    const page = activePage();
    const trail: HTMLElement[] = [];
    remember("focusTrail", trail);
    const isMessage = () =>
      (page.document.activeElement as HTMLElement | null)?.dataset?.["role"] ===
      "family-chat-message";
    for (let press = 0; press < 20 && !isMessage(); press += 1) {
      await pressAndRecord(trail, "Tab");
    }
    expect(isMessage(), "Tab never reached the history");
    for (
      let press = 0;
      press < 5 && page.document.activeElement !== requireTarget();
      press += 1
    ) {
      await pressAndRecord(trail, "ArrowUp");
    }
    expect(
      page.document.activeElement === requireTarget(),
      "the arrows never reached the message",
    );
    await pressAndRecord(trail, "Enter");
    for (
      let press = 0;
      press < 5 && page.document.activeElement?.textContent !== label;
      press += 1
    ) {
      await pressAndRecord(trail, "Tab");
    }
    expect(
      page.document.activeElement?.textContent === label,
      `keyboard focus never reached ${JSON.stringify(label)}`,
    );
    await pressAndRecord(trail, "Enter");
    typeText("Oke, aku siap");
    const queued = watchPendingRows(page);
    await pressAndRecord(trail, "Enter");
    await waitFor(() => queued.length > 0, "Enter to send the reply");
    remember("clientMessageId", queued[0]);
    await waitFor(
      () => committedFor(queued[0] ?? "") !== undefined,
      "the reply to commit",
    );
    await settle();
    recordFocus(trail);
  },
);

step("the sent message renders a quote of the selected message", async () => {
  const committed = committedFor(recall<string>("clientMessageId"));
  if (!committed) throw new Error("nothing was committed");
  await waitFor(
    () => rowFor(committed.id) !== null,
    "the sent message to reconcile",
  );
  const quote = quoteIn(messageElement(committed.id));
  expect(
    quote.dataset["targetMessageId"] === targetId(),
    `the sent message quotes ${String(quote.dataset["targetMessageId"])}`,
  );
});

step("focus is never left on a control the visitor cannot operate", () => {
  const page = activePage();
  const trail = recall<HTMLElement[]>("focusTrail");
  expect(trail.length > 0, "no keyboard focus was recorded");
  for (const focused of trail.slice(0, -1)) {
    // Each stop was operable when focus was on it; one that has since been
    // removed with its menu is fine, one that was never usable is not.
    expect(
      !(focused as HTMLButtonElement).disabled,
      `focus landed on a disabled ${focused.dataset["role"] ?? focused.tagName}`,
    );
  }
  const last = trail.at(-1) as HTMLElement;
  expect(
    last === page.elements.input && page.document.activeElement === last,
    `focus ended on ${String(last.dataset["role"] ?? last.tagName)}`,
  );
  expect(
    isRendered(last) && !page.elements.input.disabled,
    "focus ended on an unusable input",
  );
  expect(hidden(menuHost()), "the menu was left open behind the composer");
});

step("the history holds {int} messages", async (count) => {
  const seed: Seed[] = [];
  for (let index = 0; index < Number(count); index += 1) {
    seed.push({ body: `Message ${index}` });
  }
  await open(seed);
});

function rovingStop(page: Page): HTMLElement {
  const stop = page.elements.list.querySelector<HTMLElement>(
    '[data-role="family-chat-message"][tabindex="0"]',
  );
  if (!stop) throw new Error("the history offers no tab stop");
  return stop;
}

step(
  "the visitor presses Tab from the control before the history",
  async () => {
    const page = activePage();
    const order = tabOrder(page.document);
    const stopIndex = order.indexOf(rovingStop(page));
    const before = order[stopIndex - 1];
    if (stopIndex <= 0 || !before)
      throw new Error("nothing precedes the history in tab order");
    before.focus();
    await pressKey("Tab");
  },
);

step("focus enters the history exactly once", async () => {
  const page = activePage();
  const inHistory = () =>
    page.elements.list.contains(page.document.activeElement);
  expect(inHistory(), "Tab did not enter the history");
  expect(
    rovingInvariantHolds(page.elements.list),
    "the history holds more than one tab stop",
  );
  await pressKey("Tab");
  expect(!inHistory(), "a second Tab stayed inside the history");
});

step("the arrow keys move between messages", async () => {
  const page = activePage();
  await pressKey("Tab", { shiftKey: true });
  const before = page.document.activeElement;
  expect(
    before === rovingStop(page),
    "Shift+Tab did not return to the history",
  );
  await pressKey("ArrowUp");
  const after = page.document.activeElement as HTMLElement | null;
  expect(after !== before, "ArrowUp did not move between messages");
  expect(
    after?.dataset["role"] === "family-chat-message",
    "ArrowUp moved focus off the message list",
  );
});

step("a reply quoting a message from {string} is rendered", async (sender) => {
  routeRevision(true);
  const original = post({ body: ORIGINAL, sender: otherMember(sender) });
  remember("targetId", original.id);
  remember("targetBody", ORIGINAL);
  const reply = post({
    body: "Oke, aku siap",
    sender: visitor(),
    replyToMessageId: original.id,
  });
  remember("replyId", reply.id);
  await openRoomPage();
});

step("assistive technology reads that reply", () => {
  // Nothing to do to the page: what a screen reader reads is what the
  // markup already exposes. The two Thens below are that reading.
  quoteIn(messageElement(recall<string>("replyId")));
});

step("the quote exposes an accessible name naming {string}", (sender) => {
  const label = quoteIn(messageElement(recall<string>("replyId"))).getAttribute(
    "aria-label",
  );
  expect(
    label === `Reply to ${sender}: ${ORIGINAL}. Go to that message.`,
    `the quote's accessible name is ${JSON.stringify(label)}`,
  );
});

step("the quote is exposed as an activatable control", () => {
  const quote = quoteIn(
    messageElement(recall<string>("replyId")),
  ) as HTMLButtonElement;
  expect(quote.tagName === "BUTTON", `the quote is a ${quote.tagName}`);
  expect(quote.type === "button", `the quote's type is ${quote.type}`);
  // An explicit role replaces the button's own for assistive technology.
  const role = quote.getAttribute("role") ?? "button";
  expect(role === "button", `the quote is exposed as ${role}`);
  expect(!quote.disabled, "the quote is disabled");
  expect(
    quote.closest('[aria-hidden="true"]') === null,
    "the quote is hidden from assistive technology",
  );
});

// --- Offline queueing of a reply ------------------------------------------

function storedRow(id: string): Record<string, unknown> | undefined {
  return device()
    .persistence.rowsFor(namespaceOf(visitor()))
    .find((row) => row.clientMessageId === id);
}

async function queueOfflineReply(): Promise<void> {
  const page = activePage();
  const id = await replyThroughMenu(requireTarget(), "Oke, aku siap");
  if (!id) throw new Error("the reply was not queued");
  remember("clientMessageId", id);
  await waitFor(
    () => storedRow(id) !== undefined,
    "the reply to reach the device's queue",
  );
  expect(page === activePage(), "queueing the reply navigated away");
}

step("the visitor is offline with the room open", async () => {
  await open([{ body: ORIGINAL }]);
  setDeviceOnline(device(), false);
  await settle();
});

step("the visitor replies to a committed message", async () => {
  await queueOfflineReply();
});

step("the queued message shows status {string}", async (expected) => {
  const id = recall<string>("clientMessageId");
  await waitFor(
    () => shownStatus(requireRow(id)) === expected,
    `the queued reply to show ${JSON.stringify(expected)}`,
  );
});

step("the queued record carries the reply target", () => {
  const row = storedRow(recall<string>("clientMessageId"));
  expect(
    row?.["replyToMessageId"] === targetId(),
    `the queued record carries ${JSON.stringify(row?.["replyToMessageId"])}`,
  );
});

step("an offline reply is queued", async () => {
  await open([{ body: ORIGINAL }]);
  setDeviceOnline(device(), false);
  await settle();
  await queueOfflineReply();
});

step("the visitor reopens {string} while still offline", async () => {
  expect(!device().online, "the device came back online before the reopen");
  await reloadPage();
});

step("the queued reply is still present with its target", async () => {
  const id = recall<string>("clientMessageId");
  // A fresh runtime: the row on screen came back from the device's store.
  await waitFor(
    () => rowFor(id) !== null,
    "the queued reply to be shown again",
  );
  expect(
    shownStatus(requireRow(id)) !== STATUS.SENT &&
      committedFor(id) === undefined,
    "the reply was sent while the device was offline",
  );
  expect(
    storedRow(id)?.["replyToMessageId"] === targetId(),
    "the surviving record lost its reply target",
  );
});

step("the reply reaches status {string} exactly once", async (expected) => {
  const id = recall<string>("clientMessageId");
  expect(expected === STATUS.SENT, `unexpected status ${expected}`);
  await waitFor(
    () => committedFor(id) !== undefined && rowFor(id) === null,
    "the reply to reach Sent",
  );
  const commits = server().sendAttempts.filter(
    (attempt) => attempt.clientMessageId === id && attempt.outcome === "commit",
  );
  expect(commits.length === 1, `the reply was sent ${commits.length} times`);
  const copies = server().messages.filter(
    (message) => message.body === "Oke, aku siap",
  );
  expect(copies.length === 1, `the reply committed ${copies.length} times`);
});

step("the committed message renders its quote", async () => {
  const committed = committedFor(recall<string>("clientMessageId"));
  if (!committed) throw new Error("nothing was committed");
  await waitFor(
    () => rowFor(committed.id) !== null,
    "the committed reply to render",
  );
  const quote = quoteIn(messageElement(committed.id));
  expect(
    quote.dataset["targetMessageId"] === targetId(),
    `the committed reply quotes ${String(quote.dataset["targetMessageId"])}`,
  );
});

step(
  "the outbox holds a queued message stored with no reply target field",
  async () => {
    routeRevision(true);
    post({ body: ORIGINAL, sender: AYAH() });
    const id = "a1b2c3d4-0000-4000-8000-000000000048";
    // The row exactly as a bundle from before replies wrote it: the key is
    // absent, not empty.
    device().persistence.seed(namespaceOf(visitor()), {
      clientMessageId: id,
      body: "Written before replies existed",
      status: STATUS.WAITING,
      attempt: 0,
      retryCount: 0,
      createdAt: device().now - 60_000,
      nextRetryAt: 0,
    });
    remember("clientMessageId", id);
    setDeviceOnline(device(), false);
    await openRoomPage();
    await waitFor(() => rowFor(id) !== null, "the stored message to be shown");
  },
);

step("that message reaches status {string}", async (expected) => {
  const id = recall<string>("clientMessageId");
  expect(expected === STATUS.SENT, `unexpected status ${expected}`);
  await waitFor(
    () => committedFor(id) !== undefined && rowFor(id) === null,
    "the stored message to reach Sent",
  );
});

step("it commits as an ordinary message", () => {
  const id = recall<string>("clientMessageId");
  const attempts = server().sendAttempts.filter(
    (attempt) => attempt.clientMessageId === id,
  );
  expect(
    attempts.every((attempt) => attempt.replyToMessageId === undefined),
    "the stored message was sent with a reply target",
  );
  expect(
    committedFor(id)?.replyTo === null,
    "the stored message committed as a reply",
  );
});

// --- Compatibility revision and rollback floor ----------------------------

step("the compatibility revision is routed", () => {
  // The compatibility revision serves the room with the reply flag off.
  routeRevision(false);
});

step(
  "a browser loaded from the previous revision opens {string}",
  async (pathname) => {
    // The pre-reply bundle is this bundle's flag-off documents: every
    // request it makes is checked against the revision's schema.
    post({ body: "Dinner is ready", sender: AYAH() });
    await openRoomPage({ pathname });
  },
);

step("the room loads", async () => {
  const page = activePage();
  await settle();
  expect(messageRows(page).length > 0, "the room rendered no history");
  expect(
    page.elements.room?.dataset["connectionState"] === "ready",
    "the room did not finish loading",
  );
  expect(
    server().rejectedDocuments.length === 0,
    `the server refused ${JSON.stringify(server().rejectedDocuments)}`,
  );
});

step("the visitor can send a message normally", async () => {
  const id = await sendAndCommit("Masih bisa kirim");
  const committed = committedFor(id);
  expect(committed?.body === "Masih bisa kirim", "the message did not commit");
  expect(rowFor(committed?.id ?? "") !== null, "the sent message is not shown");
  expect(
    server().rejectedDocuments.length === 0,
    "the server refused the send",
  );
});

step(
  "a visitor holds the reply-aware bundle with a reply on screen",
  async () => {
    await open([{ body: "Jam berapa?" }], { replies: true });
    const id = await replyThroughMenu(requireTarget(), "Jam lima");
    await waitFor(
      () => committedFor(id ?? "") !== undefined,
      "the reply to commit",
    );
    await settle();
    remember("firstReplyId", committedFor(id ?? "")?.id);
    quoteIn(messageElement(recall<string>("firstReplyId")));
  },
);

step(
  "the routed slot is rolled back to the compatibility revision",
  async () => {
    routeRevision(false);
    // The route change ends the connections to the rolled-back slot; the
    // page itself, and the bundle it loaded, stay.
    const page = activePage();
    dropSockets(page);
    reconnectSockets(page);
    await settle();
  },
);

step("the visitor replies again with the bundle it still holds", async () => {
  expect(hasActivePage(), "the held page was closed");
  const id = await replyThroughMenu(requireTarget(), "Jam lima ya");
  await waitFor(
    () => committedFor(id ?? "") !== undefined,
    "the second reply to commit",
  );
  await settle();
  remember("secondReplyId", committedFor(id ?? "")?.id);
  const attempt = server().sendAttempts.find(
    (candidate) => candidate.clientMessageId === id,
  );
  expect(
    attempt?.replyToMessageId === targetId(),
    "the second reply was sent without its target",
  );
});

step("existing replies still render their quotes", () => {
  for (const key of ["firstReplyId", "secondReplyId"]) {
    const quote = quoteIn(messageElement(recall<string>(key)));
    expect(
      quote.textContent?.includes("Jam berapa?") === true,
      `the quote lost the original message text: ${JSON.stringify(quote.textContent)}`,
    );
  }
});
