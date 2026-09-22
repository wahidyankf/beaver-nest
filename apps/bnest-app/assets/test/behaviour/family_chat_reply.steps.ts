// Step bindings for the reply scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature -- the `Message
// actions`, `Composing a reply`, `Reading a reply`, and `Keyboard reach of
// the message history` rules, plus the four offline-queue scenarios and the
// compatibility-revision one that sit under other rules.
//
// Split from `family_chat.steps.ts` because they need a different room:
// that file's scenarios open the real `initRoom` with no `document` at all,
// and these are about markup, focus, and key events. `support/reply_room.ts`
// builds the browser-shaped room they share; `verify.ts` registers both
// files' bindings and closes that room after every scenario.
//
// Same dynamic-`import()` discipline as `family_chat.steps.ts`: each handler
// imports what it needs inside its own body, so a missing production module
// fails the scenarios that exercise it rather than the whole file.

import type { StepDefinition, StepHandler } from "./family_chat.steps";
import type { BrowserRoom, PostOptions } from "./support/reply_room";

const registry: StepDefinition[] = [];

function step(expression: string, handler: StepHandler): void {
  registry.push({ expression, handler });
}

export function familyChatReplySteps(): readonly StepDefinition[] {
  return registry;
}

// --- Scenario-scoped state ------------------------------------------------

interface ReplyScenario {
  targetId: string | null;
  targetBody: string;
  replyId: string | null;
  replyBody: string;
  pendingClientMessageId: string | null;
  queuedClientMessageId: string | null;
  fetchesBeforeJump: number;
  selectedName: string;
}

const scenario: ReplyScenario = blankScenario();

/** Undoes a `matchMedia` a scenario installed, so it cannot leak forward. */
let restoreMatchMedia: (() => void) | null = null;

function blankScenario(): ReplyScenario {
  return {
    targetId: null,
    targetBody: "",
    replyId: null,
    replyBody: "",
    pendingClientMessageId: null,
    queuedClientMessageId: null,
    fetchesBeforeJump: 0,
    selectedName: "",
  };
}

export function resetReplyScenario(): void {
  Object.assign(scenario, blankScenario());
  restoreMatchMedia?.();
  restoreMatchMedia = null;
}

// --- Shared helpers -------------------------------------------------------

function support(): Promise<typeof import("./support/reply_room")> {
  return import("./support/reply_room");
}

function actions(): Promise<
  typeof import("../../js/family_chat/message_actions.js")
> {
  return import("../../js/family_chat/message_actions.js");
}

const VISITOR = { senderId: "self", senderDisplayName: "You" };
const AYAH = { senderId: "u-ayah", senderDisplayName: "Ayah" };

/** Opens the shared browser-shaped room, remembering the newest seeded message. */
async function open(
  seed: PostOptions[] = [],
  options: { replies?: boolean } = {},
): Promise<BrowserRoom> {
  const { openBrowserRoom } = await support();
  const room = await openBrowserRoom({ seed, ...options });
  const newest = room.server.newest();
  if (newest) {
    scenario.targetId = newest.id;
    scenario.targetBody = newest.body;
  }
  return room;
}

async function current(): Promise<BrowserRoom> {
  const { currentBrowserRoom } = await support();
  return currentBrowserRoom();
}

/** The room a scenario is acting on, opened with one committed message if it has not opened one yet. */
async function roomWithCommittedMessage(): Promise<BrowserRoom> {
  const { hasBrowserRoom } = await support();
  if (hasBrowserRoom()) return current();
  return open([{ body: "Dinner is ready", ...AYAH }]);
}

function messageElement(messageId: string): HTMLElement {
  const element = document.querySelector<HTMLElement>(
    `[data-role="family-chat-message"][data-message-id="${CSS.escape(messageId)}"]`,
  );
  if (!element) throw new Error(`no rendered message ${messageId}`);
  return element;
}

function requireTarget(): HTMLElement {
  if (scenario.targetId === null)
    throw new Error("this scenario named no message");
  return messageElement(scenario.targetId);
}

function dispatch(target: EventTarget, type: string, init: object = {}): void {
  const constructor = type.startsWith("key")
    ? KeyboardEvent
    : type === "click" || type.startsWith("pointer") || type === "contextmenu"
      ? MouseEvent
      : Event;
  target.dispatchEvent(
    new constructor(type, { bubbles: true, cancelable: true, ...init }),
  );
}

/**
 * Polls rather than awaiting a fixed number of turns: the paths under proof
 * chain several promises each (a page fetch, the outbox's own transport, the
 * store's render), and a fixed `await` count is the kind of assertion that
 * passes until one more link is added to the chain.
 */
async function waitFor(
  predicate: () => boolean,
  describe: string,
  attempts = 200,
): Promise<void> {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  throw new Error(`timed out waiting for ${describe}`);
}

function settle(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 1));
}

async function menuHost(): Promise<HTMLElement> {
  return (await current()).elements.messageActions;
}

function menuButtons(host: HTMLElement): HTMLButtonElement[] {
  return [
    ...host.querySelectorAll<HTMLButtonElement>(
      '[data-role="family-chat-message-action"]',
    ),
  ];
}

async function openMenuOn(element: HTMLElement): Promise<void> {
  const more = element.querySelector('[data-role="family-chat-message-more"]');
  if (!more) throw new Error("the rendered message has no actions control");
  dispatch(more, "click");
  await settle();
}

async function chooseMenuItem(label: string): Promise<void> {
  const host = await menuHost();
  const button = menuButtons(host).find((item) => item.textContent === label);
  if (!button) throw new Error(`the menu offers no ${JSON.stringify(label)}`);
  dispatch(button, "click");
  await settle();
}

function quoteIn(element: HTMLElement): HTMLElement {
  const quote = element.querySelector<HTMLElement>(
    '[data-role="family-chat-message-quote"]',
  );
  if (!quote) throw new Error("the rendered reply carries no quote");
  return quote;
}

function graphemeCount(text: string): number {
  return [
    ...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text),
  ].length;
}

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

/**
 * `hidden` is `boolean | string` in the modern DOM lib, because
 * `hidden="until-found"` is a third state. Nothing here renders that state,
 * but the type still has to be collapsed before it can be asserted on.
 */
function isHidden(element: HTMLElement): boolean {
  return element.hidden !== false;
}

// --- Rule: Message actions ------------------------------------------------

step(
  "a visitor opens {string} with at least one committed message",
  async (context, path) => {
    await open([{ body: "Dinner is ready", ...AYAH }]);
    return { ...context, roomPath: path };
  },
);

step(
  "the visitor presses and holds for {int} milliseconds on that message",
  async (context, duration) => {
    const room = await current();
    const element = requireTarget();
    dispatch(element, "pointerdown", { clientX: 40, clientY: 80 });
    room.clock.advance(Number(duration));
    await settle();
    return context;
  },
);

step(
  "the visitor opens the browser context menu on that message",
  async (context) => {
    dispatch(requireTarget(), "contextmenu");
    await settle();
    return context;
  },
);

step(
  "the visitor activates the actions control revealed on hover on that message",
  async (context) => {
    await openMenuOn(requireTarget());
    return context;
  },
);

step(
  "the visitor moves focus to the message and presses Enter on that message",
  async (context) => {
    const element = requireTarget();
    element.focus();
    dispatch(element, "keydown", { key: "Enter" });
    await settle();
    return context;
  },
);

step("the message action menu opens for that message", async (context) => {
  const host = await menuHost();
  expect(!isHidden(host), "the action menu did not open");
  expect(
    host.dataset["messageId"] === scenario.targetId,
    `the menu opened for ${String(host.dataset["messageId"])}, not ${String(scenario.targetId)}`,
  );
  return context;
});

step("keyboard focus is inside the menu", async (context) => {
  const host = await menuHost();
  expect(
    document.activeElement !== null && host.contains(document.activeElement),
    "keyboard focus is not inside the menu",
  );
  return context;
});

step(
  "the message action menu is open for a committed message",
  async (context) => {
    await open([{ body: "Dinner is ready", ...AYAH }]);
    await openMenuOn(requireTarget());
    return context;
  },
);

step("the visitor presses Escape", async (context) => {
  dispatch(document, "keydown", { key: "Escape" });
  await settle();
  return context;
});

step("the menu closes", async (context) => {
  const host = await menuHost();
  expect(isHidden(host), "the action menu is still open");
  return context;
});

step("keyboard focus is on that same message", (context) => {
  expect(
    document.activeElement === requireTarget(),
    "keyboard focus did not return to the message the menu came from",
  );
  return context;
});

step(
  "the visitor presses a message and moves more than {int} pixels before releasing",
  async (context, tolerance) => {
    const room = await roomWithCommittedMessage();
    const element = requireTarget();
    dispatch(element, "pointerdown", { clientX: 40, clientY: 80 });
    dispatch(element, "pointermove", {
      clientX: 40,
      clientY: 80 + Number(tolerance) + 1,
    });
    room.clock.advance(1000);
    dispatch(element, "pointerup", {});
    await settle();
    return context;
  },
);

step("no action menu opens", async (context) => {
  const host = await menuHost();
  expect(isHidden(host), "a menu opened for a press that became a scroll");
  return context;
});

step(
  "the message action menu is open for one committed message",
  async (context) => {
    const room = await open([
      { body: "Dinner is ready", ...AYAH },
      { body: "On my way", ...VISITOR },
    ]);
    const [first, second] = room.pageSource.all() as unknown as {
      id: string;
    }[];
    if (!first || !second)
      throw new Error("the room was seeded with too few messages");
    scenario.targetId = first.id;
    scenario.replyId = second.id;
    await openMenuOn(messageElement(first.id));
    return context;
  },
);

step("the visitor opens the menu on a different message", async (context) => {
  if (scenario.replyId === null)
    throw new Error("no second message was seeded");
  await openMenuOn(messageElement(scenario.replyId));
  return context;
});

step("only the second message has an open menu", async (context) => {
  const host = await menuHost();
  const hosts = document.querySelectorAll(
    '[data-role="family-chat-message-actions"]',
  );
  expect(hosts.length === 1, `the room rendered ${hosts.length} menu hosts`);
  expect(!isHidden(host), "the second message has no open menu");
  expect(
    host.dataset["messageId"] === scenario.replyId,
    "the menu is still open for the first message",
  );
  return context;
});

step("the visitor opens the action menu on that message", async (context) => {
  await openMenuOn(requireTarget());
  return context;
});

step(
  "the menu offers exactly {string} and {string}",
  async (context, first, second) => {
    const labels = menuButtons(await menuHost()).map(
      (item) => item.textContent,
    );
    expect(
      labels.length === 2 && labels[0] === first && labels[1] === second,
      `the menu offers ${JSON.stringify(labels)}`,
    );
    return context;
  },
);

step("both actions are available", async (context) => {
  const disabled = menuButtons(await menuHost()).filter(
    (item) => item.getAttribute("aria-disabled") === "true",
  );
  expect(
    disabled.length === 0,
    "an action is unavailable on a committed message",
  );
  return context;
});

step(
  "the visitor's own message is in the {string} state",
  async (context, state) => {
    const { STATUS } = await import("../../js/family_chat/outbox.js");
    // The Examples column names the state in the room's own words; only
    // "Retrying" is abbreviated there, because the shipped label carries a
    // trailing delay the scenario has no way to know.
    const status =
      state === "Retrying"
        ? STATUS.RETRYING
        : (Object.values(STATUS).find((value) => value === state) ?? state);
    const room = await open([]);
    scenario.pendingClientMessageId = "c-pending";
    scenario.targetId = scenario.pendingClientMessageId;
    room.room["store"];
    const store = room.room["store"] as {
      renderPending: (message: Record<string, unknown>) => void;
    };
    store.renderPending({
      clientMessageId: scenario.pendingClientMessageId,
      body: "Oke",
      status,
      senderKind: "user",
      senderDisplayName: "You",
    });
    return context;
  },
);

step("the visitor opens the action menu on it", async (context) => {
  await openMenuOn(requireTarget());
  return context;
});

step("{string} is present and unavailable", async (context, label) => {
  const button = menuButtons(await menuHost()).find(
    (item) => item.textContent === label,
  );
  expect(
    button !== undefined,
    `the menu does not offer ${JSON.stringify(label)}`,
  );
  expect(
    button?.getAttribute("aria-disabled") === "true",
    `${JSON.stringify(label)} is available on a message that is not committed`,
  );
  return context;
});

step(
  "the menu states that the message must send before it can be replied to",
  async (context) => {
    const { REPLY_UNAVAILABLE_REASON } =
      await import("../../js/family_chat/reply_target.js");
    const button = menuButtons(await menuHost()).find(
      (item) => item.textContent === "Reply",
    );
    expect(
      button?.getAttribute("aria-description") === REPLY_UNAVAILABLE_REASON,
      `the menu gives no reason: ${String(button?.getAttribute("aria-description"))}`,
    );
    return context;
  },
);

step("{string} remains available", async (context, label) => {
  const button = menuButtons(await menuHost()).find(
    (item) => item.textContent === label,
  );
  expect(
    button !== undefined,
    `the menu does not offer ${JSON.stringify(label)}`,
  );
  expect(
    button?.getAttribute("aria-disabled") !== "true",
    `${JSON.stringify(label)} is unavailable`,
  );
  return context;
});

step("the room holds a committed system message", async (context) => {
  await open([
    {
      body: "Bunda joined the room",
      senderKind: "system",
      senderDisplayName: "System",
      senderId: "system",
    },
  ]);
  return context;
});

step("{string} is available", async (context, label) => {
  const button = menuButtons(await menuHost()).find(
    (item) => item.textContent === label,
  );
  expect(
    button !== undefined,
    `the menu does not offer ${JSON.stringify(label)}`,
  );
  expect(
    button?.getAttribute("aria-disabled") !== "true",
    `${JSON.stringify(label)} is unavailable`,
  );
  return context;
});

step(
  "the visitor opens the action menu on a message whose body is {string}",
  async (context, body) => {
    await open([{ body, ...AYAH }]);
    await openMenuOn(requireTarget());
    return context;
  },
);

step("the visitor chooses {string}", async (context, label) => {
  await chooseMenuItem(label);
  return context;
});

step("the clipboard holds exactly {string}", async (context, expected) => {
  const room = await current();
  await waitFor(() => room.clipboard.writes.length > 0, "a clipboard write");
  expect(
    room.clipboard.writes.length === 1 && room.clipboard.writes[0] === expected,
    `the clipboard holds ${JSON.stringify(room.clipboard.writes)}`,
  );
  return context;
});

step("the room announces that the message was copied", async (context) => {
  const { COPIED_ANNOUNCEMENT } = await actions();
  const room = await current();
  await waitFor(
    () => room.announcement() === COPIED_ANNOUNCEMENT,
    "the copy announcement",
  );
  return context;
});

step("the browser refuses clipboard write access", async (context) => {
  const room = await open([{ body: "Dinner is ready", ...AYAH }]);
  room.clipboard.refuse = true;
  return context;
});

step(
  "the visitor chooses {string} on a committed message",
  async (context, label) => {
    await openMenuOn(requireTarget());
    await chooseMenuItem(label);
    return context;
  },
);

step("the room states that the text could not be copied", async (context) => {
  const { COPY_REFUSED_ANNOUNCEMENT } = await actions();
  const room = await current();
  await waitFor(
    () => room.announcement() === COPY_REFUSED_ANNOUNCEMENT,
    "the refused-copy announcement",
  );
  return context;
});

// --- Rule: Composing a reply ----------------------------------------------

step(
  "the visitor opens the action menu on a message from {string} reading {string}",
  async (context, sender, body) => {
    scenario.selectedName = sender;
    await open([
      {
        body,
        senderId: `u-${sender.toLowerCase()}`,
        senderDisplayName: sender,
      },
    ]);
    await openMenuOn(requireTarget());
    return context;
  },
);

step(
  "the composer shows a reply strip naming {string}",
  async (context, sender) => {
    const { elements } = await current();
    expect(!isHidden(elements.replyStrip), "the reply strip is not showing");
    expect(
      elements.replyStripName.textContent === `Replying to ${sender}`,
      `the strip reads ${JSON.stringify(elements.replyStripName.textContent)}`,
    );
    return context;
  },
);

step("the strip shows the text of that message", async (context) => {
  const { elements } = await current();
  expect(
    elements.replyStripPreview.textContent === scenario.targetBody,
    `the strip shows ${JSON.stringify(elements.replyStripPreview.textContent)}`,
  );
  return context;
});

step("keyboard focus is in the message input", async (context) => {
  const { elements } = await current();
  expect(
    document.activeElement === elements.input,
    "keyboard focus is not in the message input",
  );
  return context;
});

step(
  "the room announces that the visitor is replying to {string}",
  async (context, sender) => {
    const room = await current();
    expect(
      room.announcement() === `Replying to ${sender}.`,
      `the room announced ${JSON.stringify(room.announcement())}`,
    );
    return context;
  },
);

step(
  "the selected message body is {int} graphemes long",
  async (context, length) => {
    const body = "a".repeat(Number(length));
    await open([{ body, ...AYAH }]);
    scenario.targetBody = body;
    return context;
  },
);

step("the reply strip renders it", async (context) => {
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
  return context;
});

step("at most {int} graphemes are shown", async (context, budget) => {
  const { elements } = await current();
  const shown = elements.replyStripPreview.textContent ?? "";
  // The budget plus the one ellipsis that marks the cut -- the same
  // allowance the backend driver's `quote_preview_within_budget` makes.
  const allowed = Number(budget) + 1;
  expect(
    graphemeCount(shown) <= allowed,
    `the strip shows ${graphemeCount(shown)} graphemes`,
  );
  return context;
});

step("the shown text ends with an ellipsis", async (context) => {
  const { elements } = await current();
  expect(
    (elements.replyStripPreview.textContent ?? "").endsWith("…"),
    "the shortened preview does not end with an ellipsis",
  );
  return context;
});

step("the composer shows a reply strip", async (context) => {
  scenario.selectedName = "Ayah";
  await open([{ body: "Nanti aku jemput jam 5", ...AYAH }]);
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
  const { elements } = await current();
  expect(!isHidden(elements.replyStrip), "the reply strip did not open");
  return context;
});

step(
  "the visitor has typed {string} without sending",
  async (context, draft) => {
    const { elements } = await current();
    elements.input.value = draft;
    return context;
  },
);

step(
  "the visitor activates the cancel control on the strip",
  async (context) => {
    const { elements } = await current();
    dispatch(elements.replyStripCancel, "click");
    await settle();
    return context;
  },
);

step("the visitor presses Escape in the message input", async (context) => {
  const { elements } = await current();
  dispatch(elements.input, "keydown", { key: "Escape" });
  await settle();
  return context;
});

step("the reply strip is gone", async (context) => {
  const { elements } = await current();
  expect(isHidden(elements.replyStrip), "the reply strip is still showing");
  return context;
});

step("the message input still holds {string}", async (context, draft) => {
  const { elements } = await current();
  expect(
    elements.input.value === draft,
    `the input holds ${JSON.stringify(elements.input.value)}`,
  );
  return context;
});

step("no reply strip is shown", async (context) => {
  const { elements } = await current();
  expect(isHidden(elements.replyStrip), "a reply strip is still showing");
  return context;
});

step("the visitor sends the message", async (context) => {
  const room = await current();
  const before = room.server.newest()?.id;
  room.elements.input.value = "Oke";
  dispatch(room.elements.composer, "submit");
  await waitFor(
    () => isHidden(room.elements.replyStrip),
    "the reply strip to clear on send",
  );
  // Awaited to the commit, not just to the queue: the Then below asks what
  // the *next* send carries, and a first send still in flight would be the
  // one it read.
  await waitFor(
    () => room.server.newest()?.id !== before,
    "the reply to commit",
  );
  scenario.replyId = room.server.newest()?.id ?? null;
  return context;
});

step(
  "the next message the visitor sends carries no reply target",
  async (context) => {
    const room = await current();
    const before = room.server.newest()?.id;
    room.elements.input.value = "Dan satu lagi";
    dispatch(room.elements.composer, "submit");
    await waitFor(
      () => room.server.newest()?.id !== before,
      "the next committed message",
    );
    const committed = room.server.newest();
    expect(
      committed?.replyTo === null,
      `the next message carried a reply target: ${JSON.stringify(committed?.replyTo)}`,
    );
    return context;
  },
);

// --- Rule: Reading a reply ------------------------------------------------

step(
  "another member has replied to one of the visitor's messages",
  async (context) => {
    const room = await open([{ body: "Nanti aku jemput jam 5", ...VISITOR }]);
    scenario.targetBody = "Nanti aku jemput jam 5";
    const reply = room.server.post({
      body: "Oke, aku siap",
      ...AYAH,
      replyToMessageId: scenario.targetId ?? undefined,
    });
    scenario.replyId = reply.id;
    scenario.replyBody = reply.body;
    return context;
  },
);

step(
  "the reply reaches the visitor through the first history page",
  async (context) => {
    const { reopenBrowserRoom } = await support();
    const room = await reopenBrowserRoom();
    await waitFor(
      () =>
        room.elements.list.querySelectorAll('[data-role="family-chat-message"]')
          .length > 0,
      "the first history page",
    );
    return context;
  },
);

step(
  "the reply reaches the visitor through an older history page",
  async (context) => {
    const { reopenBrowserRoom } = await support();
    const room = await current();
    for (let index = 0; index < 55; index += 1) {
      room.server.post({ body: `Filler ${index}`, ...AYAH });
    }
    const reopened = await reopenBrowserRoom();
    const history = reopened.room["history"] as {
      loadOlder: () => Promise<void>;
    };
    for (let page = 0; page < 5; page += 1) {
      if (
        document.querySelector(
          `[data-message-id="${CSS.escape(scenario.replyId ?? "")}"]`,
        )
      )
        break;
      await history.loadOlder();
    }
    return context;
  },
);

step(
  "the reply reaches the visitor through the live subscription",
  async (context) => {
    const room = await current();
    const reply = room.server.byId(scenario.replyId ?? "");
    const store = room.room["store"] as {
      receiveRemoteMessage: (message: unknown) => Promise<void>;
    };
    await store.receiveRemoteMessage(reply);
    return context;
  },
);

step(
  "the reply reaches the visitor through reconnect catch-up after a dropped socket",
  async (context) => {
    const { mergeMissedMessages } =
      await import("../../js/family_chat/mount_browser_sync.js");
    const room = await current();
    // The gap the socket missed: exactly what `fetchMissedMessages` would
    // have returned, merged through the real dedupe-by-server-ID path.
    const missed = room.server.byId(scenario.replyId ?? "");
    await mergeMissedMessages(room.room as never, [missed]);
    return context;
  },
);

step(
  "the reply renders a quote naming the original sender",
  async (context) => {
    await waitFor(
      () =>
        document.querySelector(
          `[data-message-id="${CSS.escape(scenario.replyId ?? "")}"]`,
        ) !== null,
      "the reply to render",
    );
    const quote = quoteIn(messageElement(scenario.replyId ?? ""));
    const sender = quote.querySelector(
      '[data-role="family-chat-message-quote-sender"]',
    );
    expect(
      sender?.textContent === "You",
      `the quote names ${JSON.stringify(sender?.textContent)}`,
    );
    return context;
  },
);

step("the quote shows the original message text", (context) => {
  const preview = quoteIn(messageElement(scenario.replyId ?? "")).querySelector(
    '[data-role="family-chat-message-quote-preview"]',
  );
  expect(
    preview?.textContent === scenario.targetBody,
    `the quote shows ${JSON.stringify(preview?.textContent)}`,
  );
  return context;
});

step("message A exists", async (context) => {
  const room = await open([{ body: "Message A", ...AYAH }]);
  scenario.targetId = room.server.newest()?.id ?? null;
  return context;
});

step("message B is a reply to A", async (context) => {
  const room = await current();
  const b = room.server.post({
    body: "Message B",
    ...VISITOR,
    replyToMessageId: scenario.targetId ?? undefined,
  });
  scenario.replyId = b.id;
  return context;
});

step("a reply to B is rendered", async (context) => {
  const { reopenBrowserRoom } = await support();
  const room = await current();
  const c = room.server.post({
    body: "Message C",
    ...AYAH,
    replyToMessageId: scenario.replyId ?? undefined,
  });
  scenario.pendingClientMessageId = c.id;
  const reopened = await reopenBrowserRoom();
  await waitFor(
    () =>
      reopened.elements.list.querySelectorAll(
        '[data-role="family-chat-message"]',
      ).length === 3,
    "all three messages to render",
  );
  return context;
});

step("that reply shows a quote of B", (context) => {
  const quote = quoteIn(messageElement(scenario.pendingClientMessageId ?? ""));
  expect(
    quote.dataset["targetMessageId"] === scenario.replyId,
    `the quote points at ${String(quote.dataset["targetMessageId"])}`,
  );
  return context;
});

step("that quote shows no quote of its own", (context) => {
  const quote = quoteIn(messageElement(scenario.pendingClientMessageId ?? ""));
  expect(
    quote.querySelector('[data-role="family-chat-message-quote"]') === null,
    "the quote card nests a second quote",
  );
  return context;
});

step("a reply and the message it quotes are both loaded", async (context) => {
  const { reopenBrowserRoom } = await support();
  const room = await open([{ body: "Jump original", ...VISITOR }]);
  const reply = room.server.post({
    body: "Jump reply",
    ...AYAH,
    replyToMessageId: scenario.targetId ?? undefined,
  });
  scenario.replyId = reply.id;
  const reopened = await reopenBrowserRoom();
  await waitFor(
    () =>
      reopened.elements.list.querySelectorAll(
        '[data-role="family-chat-message"]',
      ).length === 2,
    "both messages to render",
  );
  return context;
});

step(
  "a reply quotes a message two older pages above the loaded window",
  async (context) => {
    const { reopenBrowserRoom } = await support();
    const room = await open([{ body: "Distant original", ...VISITOR }]);
    for (let index = 0; index < 110; index += 1) {
      room.server.post({ body: `Distance ${index}`, ...AYAH });
    }
    const reply = room.server.post({
      body: "Distant reply",
      ...AYAH,
      replyToMessageId: scenario.targetId ?? undefined,
    });
    scenario.replyId = reply.id;
    const reopened = await reopenBrowserRoom();
    await waitFor(
      () =>
        document.querySelector(
          `[data-message-id="${CSS.escape(reply.id)}"]`,
        ) !== null,
      "the reply to render",
    );
    // The premise, asserted rather than assumed.
    expect(
      document.querySelector(
        `[data-message-id="${CSS.escape(scenario.targetId ?? "")}"]`,
      ) === null,
      "the quoted message was inside the loaded window after all",
    );
    scenario.fetchesBeforeJump = reopened.fetchCalls.count;
    return context;
  },
);

step(
  "a reply quotes a message more than five older pages above the loaded window",
  async (context) => {
    const { reopenBrowserRoom } = await support();
    const room = await open([{ body: "Unreachable original", ...VISITOR }]);
    for (let index = 0; index < 320; index += 1) {
      room.server.post({ body: `Distance ${index}`, ...AYAH });
    }
    const reply = room.server.post({
      body: "Unreachable reply",
      ...AYAH,
      replyToMessageId: scenario.targetId ?? undefined,
    });
    scenario.replyId = reply.id;
    const reopened = await reopenBrowserRoom();
    await waitFor(
      () =>
        document.querySelector(
          `[data-message-id="${CSS.escape(reply.id)}"]`,
        ) !== null,
      "the reply to render",
    );
    scenario.fetchesBeforeJump = reopened.fetchCalls.count;
    return context;
  },
);

step("the visitor activates the quote", async (context) => {
  const quote = quoteIn(messageElement(scenario.replyId ?? ""));
  dispatch(quote, "click");
  await settle();
  return context;
});

step("the history scrolls to the original message", async (context) => {
  const room = await current();
  await waitFor(
    () => room.scrolledTo.includes(scenario.targetId ?? ""),
    "the history to scroll to the quoted message",
  );
  return context;
});

step("that message is highlighted", async (context) => {
  await waitFor(
    () => requireTarget().dataset["jumpHighlight"] !== undefined,
    "the quoted message to be highlighted",
  );
  return context;
});

step("keyboard focus moves to it", async (context) => {
  await waitFor(
    () => document.activeElement === requireTarget(),
    "keyboard focus to move to the quoted message",
  );
  return context;
});

step(
  "older pages are loaded until the original is present",
  async (context) => {
    await waitFor(
      () =>
        document.querySelector(
          `[data-message-id="${CSS.escape(scenario.targetId ?? "")}"]`,
        ) !== null,
      "the quoted message to be paged in",
    );
    return context;
  },
);

step("the history scrolls to it", async (context) => {
  const room = await current();
  await waitFor(
    () => room.scrolledTo.includes(scenario.targetId ?? ""),
    "the history to scroll to the quoted message",
  );
  return context;
});

step("no more than five older pages are requested", async (context) => {
  const { MAX_JUMP_PAGES } =
    await import("../../js/family_chat/jump_to_message.js");
  const room = await current();
  await settle();
  const requested = room.fetchCalls.count - scenario.fetchesBeforeJump;
  expect(
    MAX_JUMP_PAGES === 5,
    `the bound the scenario names is 5, the module's is ${MAX_JUMP_PAGES}`,
  );
  expect(
    requested <= MAX_JUMP_PAGES,
    `the jump requested ${requested} older pages`,
  );
  return context;
});

step(
  "the room states that the message is too far back to jump to",
  async (context) => {
    const { JUMP_REFUSED_REMEDIATION } =
      await import("../../js/family_chat/jump_to_message.js");
    const room = await current();
    await waitFor(
      () => room.announcement() === JUMP_REFUSED_REMEDIATION,
      "the refused-jump announcement",
    );
    // "States" has to reach a reader who is looking at the screen too. The
    // live region is 1x1 and clipped, so announcing there alone leaves a
    // sighted member watching 250 messages load and then nothing happen.
    await waitFor(
      () => room.visibleRemediation() === JUMP_REFUSED_REMEDIATION,
      "the refused-jump remediation a sighted reader can see",
    );
    return context;
  },
);

step("the visitor's system requests reduced motion", (context) => {
  // The preference is installed for real, rather than recorded in a context
  // field nothing reads: a harness that merely remembered the intention
  // would let this scenario pass against an implementation that consulted
  // the preference and ignored it.
  //
  // Today nothing in the room's JavaScript asks -- the highlight is an
  // attribute and the stylesheet answers the media query, which is what the
  // Then below pins. FE_E2E asserts the computed `animation-name` under a
  // real `prefers-reduced-motion`; this layer owns the seam that makes that
  // possible, and now also fails if a future implementation starts reading
  // the preference and gets it wrong.
  const query = "(prefers-reduced-motion: reduce)";
  const previous = globalThis.matchMedia;
  globalThis.matchMedia = ((input: string) =>
    ({
      addEventListener: () => {},
      addListener: () => {},
      dispatchEvent: () => false,
      matches: input === query,
      media: input,
      onchange: null,
      removeEventListener: () => {},
      removeListener: () => {},
    }) as unknown as MediaQueryList) as typeof globalThis.matchMedia;
  restoreMatchMedia = () => {
    globalThis.matchMedia = previous;
  };
  return context;
});

step("the visitor jumps to a quoted message", async (context) => {
  const { reopenBrowserRoom } = await support();
  const room = await open([{ body: "Reduced motion original", ...VISITOR }]);
  const reply = room.server.post({
    body: "Reduced motion reply",
    ...AYAH,
    replyToMessageId: scenario.targetId ?? undefined,
  });
  scenario.replyId = reply.id;
  const reopened = await reopenBrowserRoom();
  await waitFor(
    () =>
      document.querySelector(`[data-message-id="${CSS.escape(reply.id)}"]`) !==
      null,
    "the reply to render",
  );
  dispatch(quoteIn(messageElement(reply.id)), "click");
  await waitFor(
    () => reopened.scrolledTo.includes(scenario.targetId ?? ""),
    "the jump to land",
  );
  return context;
});

step("the message is marked without an animated pulse", (context) => {
  const target = requireTarget();
  expect(
    target.dataset["jumpHighlight"] !== undefined,
    "the quoted message carries no highlight marker",
  );
  expect(
    target.style.animation === "",
    `the highlight was scripted as an animation: ${target.style.animation}`,
  );
  return context;
});

// --- Rule: Keyboard reach of the message history --------------------------

step(
  "a visitor opens {string} using only a keyboard",
  async (context, path) => {
    scenario.selectedName = "Ayah";
    await open([{ body: "Nanti aku jemput jam 5", ...AYAH }]);
    return { ...context, roomPath: path };
  },
);

step(
  "the visitor moves focus into the history, selects a message, opens the menu, chooses {string}, types, and sends",
  async (context, label) => {
    const room = await current();
    const store = room.room["store"] as {
      rovingCurrent: () => HTMLElement | null;
    };
    const stop = store.rovingCurrent();
    if (!stop) throw new Error("the history offers no tab stop to enter");
    stop.focus();
    dispatch(stop, "keydown", { key: "Enter" });
    await settle();

    const host = room.elements.messageActions;
    const item = menuButtons(host).find(
      (button) => button.textContent === label,
    );
    if (!item) throw new Error(`the menu offers no ${JSON.stringify(label)}`);
    expect(document.activeElement === item, "the menu did not take focus");
    // A browser turns Enter on a focused button into a click; happy-dom has
    // no default-action engine, so the click is dispatched directly.
    dispatch(item, "click");
    await settle();

    room.elements.input.value = "Oke, aku siap";
    dispatch(room.elements.input, "keydown", { key: "Enter" });
    await waitFor(
      () => room.server.newest()?.replyTo !== null,
      "the reply to commit",
    );
    return context;
  },
);

step(
  "the sent message renders a quote of the selected message",
  async (context) => {
    const room = await current();
    const committed = room.server.newest();
    if (!committed) throw new Error("nothing was committed");
    await waitFor(
      () =>
        document.querySelector(
          `[data-message-id="${CSS.escape(committed.id)}"]`,
        ) !== null,
      "the sent message to reconcile",
    );
    const quote = quoteIn(messageElement(committed.id));
    expect(
      quote.dataset["targetMessageId"] === scenario.targetId,
      `the sent message quotes ${String(quote.dataset["targetMessageId"])}`,
    );
    return context;
  },
);

step(
  "focus is never left on a control the visitor cannot operate",
  async (context) => {
    const room = await current();
    const focused = document.activeElement as HTMLElement | null;
    expect(focused !== null, "nothing holds keyboard focus");
    expect(
      focused === room.elements.input,
      `focus ended on ${String(focused?.dataset["role"] ?? focused?.tagName)}`,
    );
    expect(!room.elements.input.disabled, "focus ended on a disabled input");
    expect(
      isHidden(room.elements.messageActions),
      "the menu was left open behind the composer",
    );
    return context;
  },
);

step("the history holds {int} messages", async (context, count) => {
  const seed: PostOptions[] = [];
  for (let index = 0; index < Number(count); index += 1) {
    seed.push({ body: `Message ${index}`, ...AYAH });
  }
  await open(seed);
  return context;
});

step(
  "the visitor presses Tab from the control before the history",
  async (context) => {
    const room = await current();
    // happy-dom has no sequential-focus engine, so Tab itself is FE_E2E's to
    // press. What this layer owns is what Tab would find: the control before
    // the history, and then the one message the roving stop leaves reachable.
    room.elements.loadOlder.focus();
    const stop = room.elements.list.querySelector<HTMLElement>(
      '[data-role="family-chat-message"][tabindex="0"]',
    );
    if (!stop) throw new Error("the history offers no tab stop");
    stop.focus();
    return context;
  },
);

step("focus enters the history exactly once", async (context) => {
  const { rovingInvariantHolds } =
    await import("../../js/family_chat/roving_focus.js");
  const room = await current();
  const reachable = [
    ...room.elements.list.querySelectorAll<HTMLElement>(
      '[data-role="family-chat-message"]',
    ),
  ].filter((item) => item.tabIndex >= 0);
  expect(
    rovingInvariantHolds(room.elements.list),
    "the history does not hold exactly one tab stop",
  );
  expect(
    reachable.length === 1,
    `${reachable.length} messages are reachable by Tab`,
  );
  return context;
});

step("the arrow keys move between messages", async (context) => {
  const before = document.activeElement;
  dispatch(document.activeElement as HTMLElement, "keydown", {
    key: "ArrowUp",
  });
  await settle();
  const after = document.activeElement;
  expect(after !== before, "ArrowUp did not move between messages");
  expect(
    after instanceof HTMLElement &&
      after.dataset["role"] === "family-chat-message",
    "ArrowUp moved focus off the message list",
  );
  return context;
});

step(
  "a reply quoting a message from {string} is rendered",
  async (context, sender) => {
    const { reopenBrowserRoom } = await support();
    scenario.selectedName = sender;
    const room = await open([
      {
        body: "Nanti aku jemput jam 5",
        senderId: `u-${sender.toLowerCase()}`,
        senderDisplayName: sender,
      },
    ]);
    const reply = room.server.post({
      body: "Oke, aku siap",
      ...VISITOR,
      replyToMessageId: scenario.targetId ?? undefined,
    });
    scenario.replyId = reply.id;
    const reopened = await reopenBrowserRoom();
    await waitFor(
      () =>
        reopened.elements.list.querySelectorAll(
          '[data-role="family-chat-message"]',
        ).length === 2,
      "the reply to render",
    );
    return context;
  },
);

step("assistive technology reads that reply", (context) => {
  // Nothing to do to the page: what a screen reader reads is what the markup
  // already exposes. The two Thens below are that reading.
  quoteIn(messageElement(scenario.replyId ?? ""));
  return context;
});

step(
  "the quote exposes an accessible name naming {string}",
  (context, sender) => {
    const quote = quoteIn(messageElement(scenario.replyId ?? ""));
    const label = quote.getAttribute("aria-label") ?? "";
    expect(
      label ===
        `Reply to ${sender}: ${scenario.targetBody}. Go to that message.`,
      `the quote's accessible name is ${JSON.stringify(label)}`,
    );
    return context;
  },
);

step("the quote is exposed as an activatable control", (context) => {
  const quote = quoteIn(
    messageElement(scenario.replyId ?? ""),
  ) as HTMLButtonElement;
  expect(quote.tagName === "BUTTON", `the quote is a ${quote.tagName}`);
  expect(quote.type === "button", `the quote's type is ${quote.type}`);
  return context;
});

// --- Offline queueing of a reply ------------------------------------------

step("the visitor is offline with the room open", async (context) => {
  const room = await open([{ body: "Nanti aku jemput jam 5", ...AYAH }]);
  const outbox = room.room["outbox"] as {
    reportBrowserEvent: (name: string) => void;
  };
  outbox.reportBrowserEvent("offline");
  // The shared steps this scenario inherits (`the network recovers`) read
  // the room off the Gherkin context, exactly as `family_chat.steps.ts`
  // leaves it for its own document-free room.
  return { ...context, room: room.room };
});

step("the visitor replies to a committed message", async (context) => {
  const room = await current();
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
  room.elements.input.value = "Oke, aku siap";
  dispatch(room.elements.composer, "submit");
  await waitFor(
    () => room.persistence.rows.size > 0,
    "the reply to reach the queue",
  );
  const [row] = [...room.persistence.rows.values()];
  scenario.queuedClientMessageId = (row?.["clientMessageId"] as string) ?? null;
  return context;
});

step("the queued message shows status {string}", async (context, expected) => {
  const room = await current();
  const outbox = room.room["outbox"] as { status: (id: string) => string };
  const status = outbox.status(scenario.queuedClientMessageId ?? "");
  expect(
    status === expected,
    `the queued reply shows status ${JSON.stringify(status)}`,
  );
  return context;
});

step("the queued record carries the reply target", async (context) => {
  const room = await current();
  const row = room.persistence.rows.get(scenario.queuedClientMessageId ?? "");
  expect(
    row?.["replyToMessageId"] === scenario.targetId,
    `the queued record carries ${JSON.stringify(row?.["replyToMessageId"])}`,
  );
  return context;
});

step("an offline reply is queued", async (context) => {
  const room = await open([{ body: "Nanti aku jemput jam 5", ...AYAH }]);
  const outbox = room.room["outbox"] as {
    reportBrowserEvent: (name: string) => void;
  };
  outbox.reportBrowserEvent("offline");
  await openMenuOn(requireTarget());
  await chooseMenuItem("Reply");
  room.elements.input.value = "Oke, aku siap";
  dispatch(room.elements.composer, "submit");
  await waitFor(
    () => room.persistence.rows.size > 0,
    "the reply to reach the queue",
  );
  const [row] = [...room.persistence.rows.values()];
  scenario.queuedClientMessageId = (row?.["clientMessageId"] as string) ?? null;
  return { ...context, room: room.room };
});

step(
  "the visitor reopens {string} while still offline",
  async (context, path) => {
    const { reopenBrowserRoom } = await support();
    const reopened = await reopenBrowserRoom({ offline: true });
    return { ...context, room: reopened.room, roomPath: path };
  },
);

step("the queued reply is still present with its target", async (context) => {
  const room = await current();
  const outbox = room.room["outbox"] as {
    pendingMessages: () => { clientMessageId: string }[];
  };
  const present = outbox
    .pendingMessages()
    .some(
      (message) => message.clientMessageId === scenario.queuedClientMessageId,
    );
  expect(present, "the queued reply did not survive the reopen");
  const row = room.persistence.rows.get(scenario.queuedClientMessageId ?? "");
  expect(
    row?.["replyToMessageId"] === scenario.targetId,
    "the surviving record lost its reply target",
  );
  return context;
});

step(
  "the reply reaches status {string} exactly once",
  async (context, expected) => {
    const room = await current();
    const outbox = room.room["outbox"] as {
      waitForStatus: (id: string, status: string) => Promise<string>;
    };
    const id = scenario.queuedClientMessageId ?? "";
    const status = await outbox.waitForStatus(id, expected);
    expect(status === expected, `the reply reached ${JSON.stringify(status)}`);
    const committedWithBody = room.pageSource
      .all()
      .filter(
        (message) =>
          (message as unknown as { body: string }).body === "Oke, aku siap",
      );
    expect(
      committedWithBody.length === 1,
      `the reply committed ${committedWithBody.length} times`,
    );
    return context;
  },
);

step("the committed message renders its quote", async (context) => {
  const room = await current();
  const committed = room.server.newest();
  if (!committed) throw new Error("nothing was committed");
  await waitFor(
    () =>
      document.querySelector(
        `[data-message-id="${CSS.escape(committed.id)}"]`,
      ) !== null,
    "the committed reply to reconcile",
  );
  const quote = quoteIn(messageElement(committed.id));
  expect(
    quote.dataset["targetMessageId"] === scenario.targetId,
    `the committed reply quotes ${String(quote.dataset["targetMessageId"])}`,
  );
  return context;
});

step(
  "the outbox holds a queued message stored with no reply target field",
  async (context) => {
    const { seedQueuedMessage } =
      await import("../../js/family_chat/outbox.js");
    const room = await open([{ body: "Nanti aku jemput jam 5", ...AYAH }]);
    const seeded = await seedQueuedMessage({
      ageMs: 0,
      userId: room.visitor.id,
      roomSlug: "ruang-keluarga",
      clock: room.clock as never,
    });
    scenario.queuedClientMessageId = seeded.clientMessageId;
    return { ...context, room: room.room };
  },
);

step("that message reaches status {string}", async (context, expected) => {
  const room = await current();
  const outbox = room.room["outbox"] as {
    waitForStatus: (id: string, status: string) => Promise<string>;
  };
  const status = await outbox.waitForStatus(
    scenario.queuedClientMessageId ?? "",
    expected,
  );
  expect(
    status === expected,
    `the seeded message reached ${JSON.stringify(status)}`,
  );
  return context;
});

step("it commits as an ordinary message", async (context) => {
  const room = await current();
  const outbox = room.room["outbox"] as {
    committedMessage: (id: string) => { replyTo?: unknown } | null;
  };
  const committed = outbox.committedMessage(
    scenario.queuedClientMessageId ?? "",
  );
  expect(committed !== null, "the seeded message never committed");
  expect(
    committed?.replyTo === null || committed?.replyTo === undefined,
    `the seeded message committed with a reply target: ${JSON.stringify(committed?.replyTo)}`,
  );
  return context;
});

// --- Compatibility revision -----------------------------------------------

step("the compatibility revision is routed", async (context) => {
  // The compatibility revision is this same bundle with the flag off; which
  // revision Caddy routes is FE_E2E's (`promoteCandidateWithReplyFlag`).
  // What this layer owns is what that flag does to the room.
  await open([{ body: "Dinner is ready", ...AYAH }], { replies: false });
  return context;
});

step(
  "a browser loaded from the previous revision opens {string}",
  async (context, path) => {
    const room = await current();
    expect(
      isHidden(room.elements.messageActions),
      "the flag-off room opened with an action menu showing",
    );
    return { ...context, roomPath: path };
  },
);

step("the room loads", async (context) => {
  const room = await current();
  expect(
    room.elements.list.querySelectorAll('[data-role="family-chat-message"]')
      .length > 0,
    "the flag-off room rendered no history",
  );
  expect(
    isHidden(room.elements.replyStrip),
    "the flag-off room shows a reply strip",
  );
  return context;
});

// --- The rollback floor ---------------------------------------------------
//
// Which slot Caddy routes, and whether a browser truly keeps its bundle across
// the route change, is FE_E2E's (`rollBackRoutedSlot`). What this layer owns is
// the half that makes the rollback survivable at all: a reply-aware bundle
// renders a quote from whatever the server answers with, on a freshly built
// room rather than only on a live arrival. The floor still serves `replyTo`
// (tech-doc 002) -- so if hydration ever stopped rendering quotes, a rollback
// would silently drop every quote card, and this fails first.

step(
  "a visitor holds the reply-aware bundle with a reply on screen",
  async (context) => {
    const { reopenBrowserRoom } = await support();
    const room = await open([{ body: "Jam berapa?", ...AYAH }], {
      replies: true,
    });
    scenario.targetId = room.server.newest()?.id ?? null;
    scenario.replyId = room.server.post({
      body: "Jam lima",
      ...VISITOR,
      replyToMessageId: scenario.targetId ?? undefined,
    }).id;
    // This layer has no live push -- `post` appends to the page source and a
    // build is what reads it. The subscription path is FE_E2E's; what this
    // layer owns is hydration, which is the half a rollback actually exercises.
    await reopenBrowserRoom();
    await settle();
    return context;
  },
);

step(
  "the routed slot is rolled back to the compatibility revision",
  async (context) => {
    // No route to move here. The decision this layer holds is that the
    // server's answer keeps its quote regardless of the room's own flag,
    // which is what the floor relies on.
    const room = await current();
    const answered = room.server.byId(scenario.replyId ?? "");
    expect(
      answered?.replyTo != null,
      "the server dropped the quote from a committed reply",
    );
    return context;
  },
);

step(
  "the visitor replies again with the bundle it still holds",
  async (context) => {
    // A reply committed after the rollback. Asserting the quote already on
    // screen would assert markup rendered before it, which would survive the
    // floor answering with nothing.
    const { reopenBrowserRoom } = await support();
    const room = await current();
    room.server.post({
      body: "Jam lima ya",
      ...VISITOR,
      replyToMessageId: scenario.targetId ?? undefined,
    });
    await reopenBrowserRoom();
    await settle();
    return context;
  },
);

step("existing replies still render their quotes", async (context) => {
  const room = await current();
  for (const body of ["Jam lima", "Jam lima ya"]) {
    const rendered = [
      ...room.elements.list.querySelectorAll<HTMLElement>(
        '[data-role="family-chat-message"]',
      ),
    ].find((node) => node.textContent?.includes(body));
    expect(rendered !== undefined, `the reply ${body} is not in the room`);
    const quote = quoteIn(rendered as HTMLElement);
    expect(
      quote.textContent?.includes("Jam berapa?") === true,
      `the quote lost the original message text: ${JSON.stringify(quote.textContent)}`,
    );
  }
  return context;
});

step("the visitor can send a message normally", async (context) => {
  const room = await current();
  const before = room.server.newest()?.id;
  room.elements.input.value = "Masih bisa kirim";
  dispatch(room.elements.composer, "submit");
  await waitFor(
    () => room.server.newest()?.id !== before,
    "the message to commit",
  );
  expect(
    room.server.newest()?.body === "Masih bisa kirim",
    "the flag-off room could not send",
  );
  return context;
});
