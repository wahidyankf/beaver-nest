// Step bindings for the `Diagrams in messages` rule of specs/apps/bnest/app-fe/behaviours/family_chat.feature
// (ADR 004, Decision 3).
//
// The room is the one `family_chat.steps.ts` opens (`support/browser_room.ts`). The page loads a stand-in for the
// diagram engine with the engine's contract (`support/fake_diagram_engine.ts`), so the shipped renderer runs its own
// queue, cache, figure and placement code. Mermaid's real layout, the 320 px fit, the injection canary and the
// request recorder are proved in Chromium (`bnest-app-fe-e2e`).
//
// A message's body is the Markdown the feature's docstring holds, as the member typed it. Each body that a server
// reply needs has a recorded production rendering in `support/family_chat_rendered_bodies.json`.

import { rovingInvariantHolds } from "../../js/family_chat/roving_focus.js";
import {
  activePage,
  committedFor,
  computedStyleOf,
  device,
  messageRows,
  otherMember,
  post,
  rowFor,
  sendThroughComposer,
  setDiagramEngineAvailable,
  waitFor,
} from "./support/browser_room";
import { recall, recallOr, remember } from "./support/scenario_memory";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import {
  CANVAS_SELECTOR,
  declaredDiagramBlock,
  PICTURE_SELECTOR,
  PICTURE_WIDTH_RULE,
} from "../support/diagram_css";
import {
  declarationsFor,
  lengthPx,
  resolveVars,
  type Environment,
} from "../support/shipped_css";

// Each attempt waits about a millisecond, so this stays inside the Vitest test timeout (5 seconds) and a missed
// condition fails the scenario instead of leaving its page open.
const SETTLE_ATTEMPTS = 2_000;

// The messages the Given steps name by kind. The end-to-end adapter (`family-chat-diagrams.ts`) records the same
// strings, so a change here is a change there.
function diagramBody(kind: string): string {
  if (kind === "oversized flowchart") {
    // Each "é" is two bytes, so the source passes the 6,000-byte cap while the message stays within the 4,000-grapheme
    // limit that a message body is checked against. The server refuses the diagram as too large.
    return `\`\`\`mermaid\nflowchart TD\n  A --> B\n%% ${"é".repeat(3100)}\n\`\`\``;
  }
  if (kind === "unsupported diagram") {
    return "```mermaid\narchitecture-beta\n  group api(cloud)[API]\n```";
  }
  if (kind === "five flowcharts") {
    // Four are drawn; the fifth is refused as surplus.
    return Array.from(
      { length: 5 },
      (_unused, index) =>
        `\`\`\`mermaid\nflowchart TD\n  A${index + 1} --> B${index + 1}\n\`\`\``,
    ).join("\n\n");
  }
  throw new Error(`no diagram message is named ${JSON.stringify(kind)}`);
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

// --- Then: a wide diagram's bubble on a desktop column -------------------------------------------------------------

/** The message list's width at a viewport: the room's column less its gutters, as the shipped CSS sets them. */
function messageListWidthPx(env: Environment): number {
  const shell = declarationsFor(".family-chat-shell", env);
  const gutter = lengthPx(resolveVars(shell["--hearth-gutter"] ?? ""), env);
  const column = lengthPx(shell["max-width"] ?? "", env);
  return Math.min(column, env.width) - 2 * gutter;
}

step(
  "the diagram bubble takes at least 80 percent of the message list width",
  () => {
    // A message with a diagram takes the shared diagram share of the list (chat_shared.css), and its bubble is that
    // less the avatar and the gap beside it. The measured width is the Playwright adapter's.
    const { viewport } = device();
    const env: Environment = {
      width: viewport.width,
      height: viewport.height,
      coarse: false,
    };
    const share = Number.parseFloat(
      resolveVars(
        declarationsFor(".family-chat-message:has(.bnest-diagram-canvas)", env)[
          "width"
        ] ?? "",
      ),
    );
    expect(
      Number.isFinite(share),
      "the diagram message has no share of the list",
    );
    const avatar = lengthPx(
      declarationsFor(".family-chat-message-avatar", env)["width"] ?? "",
      env,
    );
    const gap = lengthPx(
      declarationsFor(".family-chat-message", env)["column-gap"] ?? "",
      env,
    );
    const list = messageListWidthPx(env);
    const bubble = (share / 100) * list - avatar - gap;
    expect(
      bubble / list >= 0.8,
      `the diagram bubble is ${Math.round((100 * bubble) / list)}% of a ${list.toFixed(0)} px list`,
    );
  },
);

export function familyChatDiagramSteps(): readonly StepDefinition[] {
  return registry;
}

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

/** The message the scenario is about: another member's (by server id) or the visitor's own send (by client id). */
function targetRow(): HTMLElement | null {
  const key = recallOr<string | null>(
    "markdownTarget",
    recallOr<string | null>("clientMessageId", null),
  );
  if (key === null) throw new Error("no earlier step named a message");
  const committed = committedFor(key);
  return rowFor(committed?.id ?? key);
}

function bodyOf(): HTMLElement | null {
  return (
    targetRow()?.querySelector<HTMLElement>(
      '[data-role="family-chat-message-body"]',
    ) ?? null
  );
}

/** The rendered body of the target message; `committed` waits until the server's copy replaces a pending one. */
async function settledBody(committed = true): Promise<HTMLElement> {
  await waitFor(
    () => {
      const row = targetRow();
      return (
        row !== null &&
        bodyOf() !== null &&
        (!committed || row.dataset["deliveryState"] === "committed")
      );
    },
    "the message to render",
    SETTLE_ATTEMPTS,
  );
  const body = bodyOf();
  if (!body) throw new Error("the message renders no body element");
  return body;
}

/** The Markdown the member typed for this message, as the docstring holds it. */
function typedBody(): string {
  return recall<string>("typedBody");
}

/** The diagram source of each mermaid fence the typed Markdown holds, in document order. */
function fenceSourcesOf(typed: string): string[] {
  return [...typed.matchAll(/```mermaid\n([\s\S]*?)\n```/gu)].map(
    (match) => match[1] ?? "",
  );
}

function drawnFiguresIn(body: HTMLElement): HTMLElement[] {
  return [
    ...body.querySelectorAll<HTMLElement>(
      'figure[data-bnest-diagram-state="drawn"]',
    ),
  ];
}

function labelledFigureIn(
  body: HTMLElement,
  label: string,
): HTMLElement | undefined {
  return drawnFiguresIn(body).find((figure) =>
    figure
      .querySelector(".bnest-diagram-canvas")
      ?.getAttribute("aria-label")
      ?.startsWith(`${label}.`),
  );
}

/** The text of every code block a body shows, with the line break a fence keeps at its end removed. */
function sourcesShownIn(body: HTMLElement): string[] {
  return [...body.querySelectorAll("pre")].map((pre) =>
    (pre.textContent ?? "").replace(/\s+$/u, ""),
  );
}

// --- Given and When: what the messages are ---------------------------------------------

// The menu steps of family_chat_reply.steps.ts name their message by `targetId`, so a message a Given or When
// names is also the target for them.
function nameTarget(id: string, body: string): void {
  remember("markdownTarget", id);
  remember("targetId", id);
  remember("typedBody", body);
}

step("{word} has sent this family chat message:", (sender, body) => {
  nameTarget(post({ body, sender: otherMember(sender) }).id, body);
});

step("{word} has sent the diagram message {string}", (sender, kind) => {
  const body = diagramBody(kind);
  nameTarget(post({ body, sender: otherMember(sender) }).id, body);
});

step("the diagram engine cannot be loaded", () => {
  setDiagramEngineAvailable(false);
});

step(
  "{word} sends this family chat message while the visitor watches:",
  async (sender, body) => {
    const message = post({ body, sender: otherMember(sender) });
    nameTarget(message.id, body);
    await waitFor(
      () => rowFor(message.id) !== null,
      "the live message to reach the room",
      SETTLE_ATTEMPTS,
    );
  },
);

step("the visitor sends this family chat message:", async (body) => {
  const id = await sendThroughComposer(body);
  if (id === null) throw new Error("the room refused to queue the message");
  remember("clientMessageId", id);
  remember("typedBody", body);
});

// --- Then: what the room drew, showed, and offered -------------------------------------

step("the message shows a diagram labelled {string}", async (label) => {
  await waitFor(
    () => {
      const body = bodyOf();
      return body !== null && labelledFigureIn(body, label) !== undefined;
    },
    `a drawn diagram labelled ${label}`,
    SETTLE_ATTEMPTS,
  );
});

step("the message shows the note {string}", async (note) => {
  await settledBody();
  await waitFor(
    () => (bodyOf()?.textContent ?? "").includes(note),
    `the note ${JSON.stringify(note)}`,
    SETTLE_ATTEMPTS,
  );
});

step("the message keeps its diagram source as text", async () => {
  const expected = fenceSourcesOf(typedBody());
  expect(expected.length > 0, "the typed message holds no mermaid fence");
  await waitFor(
    () => {
      const body = bodyOf();
      if (body === null) return false;
      const shown = sourcesShownIn(body);
      return expected.every((source) =>
        shown.includes(source.replace(/\s+$/u, "")),
      );
    },
    "every diagram source to be shown as text",
    SETTLE_ATTEMPTS,
  );
});

step(
  "the message shows the diagram source as typed text with no drawing",
  async () => {
    const body = await settledBody(false);
    expect(
      body.dataset["bodyFormat"] === "text",
      `the body is ${String(body.dataset["bodyFormat"])}, not text`,
    );
    expect(
      body.textContent === typedBody(),
      `the body reads ${JSON.stringify(body.textContent)}`,
    );
    expect(
      body.querySelector("figure, pre") === null,
      "a pending message holds a drawing",
    );
  },
);

step("the message shows {int} drawn diagrams", async (count) => {
  await waitFor(
    () => bodyOf()?.querySelector('pre[data-bnest-diagram="mermaid"]') === null,
    "every marked diagram to be settled",
    SETTLE_ATTEMPTS,
  );
  const body = await settledBody();
  const drawn = drawnFiguresIn(body).length;
  expect(drawn === Number(count), `${drawn} drawn diagrams, not ${count}`);
});

step("no script from the message runs", async () => {
  const body = await settledBody();
  expect(
    body.querySelector("script") === null,
    "the message holds a script element",
  );
  for (const element of [body, ...body.querySelectorAll("*")]) {
    for (const name of element.getAttributeNames()) {
      expect(
        !name.startsWith("on"),
        `${element.tagName} has the attribute ${name}`,
      );
    }
  }
  const page = activePage().window as unknown as Record<string, unknown>;
  expect(
    page["bnestDiagramCanary"] === undefined,
    "the diagram text ran script",
  );
});

// The diagram message is the row a drawn figure sits in. The scenario's last named message can be a later plain
// message, so this never reads the remembered target.
function diagramRow(): HTMLElement {
  const row = messageRows().find(
    (candidate) => drawnFiguresIn(candidate).length > 0,
  );
  if (!row) throw new Error("no message in the history holds a drawn diagram");
  return row;
}

step("the diagram message shows a diagram labelled {string}", async (label) => {
  await waitFor(
    () => {
      const row = messageRows().find(
        (candidate) => labelledFigureIn(candidate, label) !== undefined,
      );
      return row !== undefined;
    },
    `a drawn diagram labelled ${label} in a message`,
    SETTLE_ATTEMPTS,
  );
});

step("the diagram message adds no tab stop", () => {
  const row = diagramRow();
  const figure = drawnFiguresIn(row)[0];
  if (!figure) throw new Error("no diagram is drawn");
  const canvas = figure.querySelector<HTMLElement>(".bnest-diagram-canvas");
  const summary = figure.querySelector<HTMLElement>(
    ".bnest-diagram-source > summary",
  );
  expect(canvas?.tabIndex === -1, "the picture's canvas is a tab stop");
  expect(summary?.tabIndex === -1, "the source summary is a tab stop");
  expect(row.tabIndex === -1, "the diagram message is the keyboard stop");
  expect(
    rovingInvariantHolds(activePage().elements.list),
    "the history lost its single tab stop",
  );
});

step("the clipboard holds the message as typed", async () => {
  await waitFor(
    () => device().clipboard.writes.length > 0,
    "the copied text",
    SETTLE_ATTEMPTS,
  );
  expect(
    device().clipboard.writes.at(-1) === typedBody(),
    `the clipboard holds ${JSON.stringify(device().clipboard.writes.at(-1))}`,
  );
});

step("the reply quotes the typed message as plain text", async () => {
  await settledBody();
  const row = targetRow();
  const preview = row?.querySelector<HTMLElement>(
    '[data-role="family-chat-message-quote-preview"]',
  );
  expect(
    preview !== null && preview !== undefined,
    "the reply carries no quote preview",
  );
  // The server's quote preview collapses every run of whitespace (`Message.body_preview/1`), so the typed Markdown
  // is compared in that form: its characters, shown as plain text, with no drawing in the quote.
  const collapsed = typedBody().replace(/\s+/gu, " ").trim();
  expect(
    preview?.textContent === collapsed && preview.children.length === 0,
    `the quote reads ${JSON.stringify(preview?.textContent)}`,
  );
});

step(
  "the drawn diagram sits on its own paper surface in the own bubble",
  async () => {
    const body = await settledBody();
    await waitFor(
      () => drawnFiguresIn(body).length > 0,
      "the diagram to be drawn",
      SETTLE_ATTEMPTS,
    );
    const surface = declaredDiagramBlock(".bnest-diagram");
    expect(
      surface.includes("background: var(--bnest-paper);"),
      "the figure has no paper surface",
    );
    expect(
      surface.includes("color: var(--bnest-ink);"),
      "the figure has no ink colour",
    );
    expect(
      surface.includes("border: 2px solid var(--bnest-ink-soft);"),
      "the figure has no border",
    );
  },
);

step("the diagram fits the message bubble", async () => {
  const body = await settledBody();
  await waitFor(
    () => drawnFiguresIn(body).length > 0,
    "the diagram to be drawn",
    SETTLE_ATTEMPTS,
  );
  const canvas = declaredDiagramBlock(CANVAS_SELECTOR);
  expect(
    canvas.includes("max-width: 100%;"),
    "the canvas is wider than its bubble",
  );
  expect(
    canvas.includes("overflow-x: auto;"),
    "the canvas does not scroll inside itself",
  );
  const picture = declaredDiagramBlock(PICTURE_SELECTOR);
  expect(
    picture.includes(PICTURE_WIDTH_RULE),
    "the picture is not limited to the bubble width",
  );
  const bubble = targetRow()?.querySelector<HTMLElement>(
    ".family-chat-message-bubble",
  );
  if (!bubble) throw new Error("the message has no bubble");
  expect(
    computedStyleOf(bubble).getPropertyValue("min-width") === "0",
    "the bubble does not allow shrinking",
  );
});

// A wide diagram: the picture keeps its readable width (never below 0.75 of its natural width, nor 30rem), so the
// canvas scrolls inside its own box instead of shrinking the text (ADR 004, Decision 5). The rendered widths are
// measured in Chromium (`bnest-app-fe-e2e`).
step("the diagram keeps a readable size", async () => {
  const body = await settledBody();
  await waitFor(
    () => drawnFiguresIn(body).length > 0,
    "the diagram to be drawn",
    SETTLE_ATTEMPTS,
  );
  const picture = declaredDiagramBlock(PICTURE_SELECTOR);
  expect(
    picture.includes(PICTURE_WIDTH_RULE),
    "the picture may shrink below its readable width",
  );
  expect(
    !picture.includes("min-width:"),
    "the picture still has a shrink-only minimum",
  );
});

step("the diagram scrolls inside its own box", async () => {
  const body = await settledBody();
  await waitFor(
    () => drawnFiguresIn(body).length > 0,
    "the diagram to be drawn",
    SETTLE_ATTEMPTS,
  );
  const canvas = declaredDiagramBlock(CANVAS_SELECTOR);
  expect(
    canvas.includes("overflow-x: auto;"),
    "the canvas does not scroll inside its own box",
  );
  expect(
    canvas.includes("max-width: 100%;"),
    "the canvas is wider than its bubble",
  );
});
