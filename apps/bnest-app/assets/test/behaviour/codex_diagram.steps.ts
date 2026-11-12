// Vitest bindings for the browser-only Codex reply diagram scenarios of chat.feature (tag `@fe-vitest-unit`, ADR 004).
// They drive the shipped renderer (`createDiagramRenderer`) on a happy-dom page with a fake engine. The server
// markup each reply carries is built here from the same fixture replies the server and Playwright use
// (`test/support/codex_fixture_replies.json`), so the sources are the ones a reader would see. Real layout, the
// service worker, the network and the LiveView patch are proved in Chromium (`bnest-app-fe-e2e`).

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Window } from "happy-dom";
import { expect } from "vitest";
import {
  createDiagramRenderer,
  type RendererDeps,
} from "../../js/diagrams/mermaid_diagrams.js";
import { setFocusable } from "../../js/diagrams/diagram_figure.js";
import { checkSource, LIMITS } from "../../js/diagrams/diagram_limits.js";
import { renderDiagram as fakeRender } from "../support/fake_diagram_engine";
import type { StepDefinition, StepHandler } from "./family_chat.steps";
import {
  CANVAS_SELECTOR,
  declaredDiagramBlock,
  PICTURE_SELECTOR,
  PICTURE_WIDTH_RULE,
} from "../support/diagram_css";

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  here,
  "../../../test/support/codex_fixture_replies.json",
);
// The production rendering of each pinned reply, from `codex_rendered_replies.json`. This binding reads the stored pin,
// so it goes red only after the pin is regenerated. The ExUnit gate (`codex_rendered_replies_test.exs`) is the one
// that detects a change to the server's output, and it fails at once. Regenerate the pin only for an intended change.
const RENDERED_REPLIES = JSON.parse(
  readFileSync(
    path.resolve(here, "../support/codex_rendered_replies.json"),
    "utf8",
  ),
) as Record<string, string>;

function renderedReply(prompt: string): Node[] {
  const html = RENDERED_REPLIES[prompt];
  if (html === undefined)
    throw new Error(`no pinned rendering for ${JSON.stringify(prompt)}`);
  const holder = document.createElement("div");
  holder.innerHTML = html;
  return [...holder.childNodes];
}

const MARKER = 'pre[data-bnest-diagram="mermaid"]';
const GLOBAL_NAMES = [
  "window",
  "document",
  "Element",
  "HTMLElement",
  "Node",
  "MutationObserver",
] as const;

const FIXTURES = JSON.parse(readFileSync(FIXTURE_PATH, "utf8")) as Record<
  string,
  { text: string }
>;

/** The mermaid fences of one canned reply, in order. */
function diagramsOf(prompt: string): string[] {
  const text = FIXTURES[prompt]?.text;
  if (text === undefined)
    throw new Error(`no fixture reply for ${JSON.stringify(prompt)}`);
  return [...text.matchAll(/```mermaid\n([\s\S]*?)\n```/gu)].map(
    (match) => match[1] ?? "",
  );
}

function sourceOf(prompt: string, index = 0): string {
  const source = diagramsOf(prompt)[index];
  if (source === undefined)
    throw new Error(
      `fixture ${JSON.stringify(prompt)} has no diagram ${index}`,
    );
  return source;
}

const FLOWCHART = "flowchart TD\n  A --> B";
const SVG_URL_PREFIX = "data:image/svg+xml";
// An attribute or a CSS url that names another origin. A namespace URL (`xmlns="http://..."`) is not a request.
const EXTERNAL_REFERENCE =
  /\b(?:href|src)\s*=\s*["']?\s*https?:|url\(\s*["']?\s*https?:/iu;
// What a hostile reply would have Mermaid draw if it let markup through: a script, an event handler, a foreign
// object, an external image and a javascript: link. The renderer's SVG check must refuse it.
const HOSTILE_SVG =
  '<svg viewBox="0 0 10 10" onload="window.__bnestRan = 1"><script>window.__bnestRan = 1</script>' +
  '<foreignObject><img src="https://evil.test/a.png"></foreignObject>' +
  '<image href="https://evil.test/b.png"/><a href="javascript:window.__bnestRan = 1"><text>x</text></a></svg>';

interface Scene {
  window: Window;
  root: HTMLElement;
  renderer: ReturnType<typeof createDiagramRenderer> | null;
  watcher: { disconnect(): void } | null;
  engineAvailable: boolean;
  importCount: number;
  renderCount: number;
  nextReply: number;
  figure: Element | null;
  largest: string | null;
  /** When set, the engine answers every draw with this SVG (the hostile scenario). */
  hostileSvg: string | null;
  /** Starts that still fail before the engine loads (the first start in the retry scenario). */
  engineFailuresLeft: number;
  /** Added to the renderer's clock, so the retry window passes without a wait. */
  clockOffset: number;
}

let scene: Scene | null = null;
let saved: Map<string, unknown> = new Map();

function dependencies(state: Scene): RendererDeps {
  const engine = {
    ENGINE_API: 1,
    renderDiagram: async (source: string) => {
      state.renderCount += 1;
      if (state.hostileSvg !== null) return { svg: state.hostileSvg };
      return fakeRender(source);
    },
  };
  return {
    importEngine: async () => {
      state.importCount += 1;
      if (!state.engineAvailable)
        throw new Error("the diagram engine could not be fetched");
      if (state.engineFailuresLeft > 0) {
        state.engineFailuresLeft -= 1;
        throw new Error("the diagram engine failed to start");
      }
      return engine;
    },
    readTheme: () => ({
      themeVariables: {},
      themeSignature: "codex-fixture-theme",
    }),
    now: () => performance.now() + state.clockOffset,
    // No draw in these scenarios waits on the timeout, so the timer never needs to fire.
    setTimer: () => 0,
    clearTimer: () => undefined,
    yieldTurn: () => new Promise((resolve) => setTimeout(resolve, 0)),
    // No viewport observer: every marked diagram is drawn as soon as it is seen.
    createIntersectionObserver: () => null,
  };
}

function installGlobals(window: Window): void {
  saved = new Map();
  const values: Record<(typeof GLOBAL_NAMES)[number], unknown> = {
    window,
    document: window.document,
    Element: window.Element,
    HTMLElement: window.HTMLElement,
    Node: window.Node,
    MutationObserver: window.MutationObserver,
  };
  for (const name of GLOBAL_NAMES) {
    saved.set(name, Reflect.get(globalThis, name));
    Reflect.set(globalThis, name, values[name]);
  }
}

function restoreGlobals(): void {
  for (const [name, value] of saved) Reflect.set(globalThis, name, value);
  saved = new Map();
}

function ensureScene(): Scene {
  if (scene !== null) return scene;
  const window = new Window({ url: "https://bnest.test/chat" });
  installGlobals(window);
  const root = document.createElement("div");
  root.id = "chat-conversation";
  document.body.append(root);
  // The renderer's fake engine reports its calls into this scene, so the scene is built first.
  const state: Scene = {
    window,
    root,
    renderer: null,
    watcher: null,
    engineAvailable: true,
    importCount: 0,
    renderCount: 0,
    nextReply: 1,
    figure: null,
    largest: null,
    hostileSvg: null,
    engineFailuresLeft: 0,
    clockOffset: 0,
  };
  state.renderer = createDiagramRenderer(dependencies(state));
  scene = state;
  return state;
}

/** Stops the watcher and removes the page, so no scenario reaches the next one. */
export function resetCodexDiagram(): void {
  if (scene !== null) {
    scene.watcher?.disconnect();
    scene.window.close();
  }
  scene = null;
  restoreGlobals();
}

function markedBlock(source: string): Element {
  const pre = document.createElement("pre");
  pre.setAttribute("data-bnest-diagram", "mermaid");
  const code = document.createElement("code");
  code.textContent = source;
  pre.append(code);
  return pre;
}

// What the server writes for a fence it refuses: an ordinary code block, then a note.
function paragraph(text: string): Element {
  const p = document.createElement("p");
  p.textContent = text;
  return p;
}

function addReply(state: Scene, children: Node[]): void {
  const article = document.createElement("article");
  article.setAttribute("data-role", "assistant-message");
  article.id = `assistant-message-${state.nextReply}`;
  state.nextReply += 1;
  const body = document.createElement("div");
  body.className = "markdown-body";
  body.append(...children);
  article.append(body);
  state.root.append(article);
}

// Draws every marked diagram in the page: one watcher per conversation, as the ChatDiagrams hook keeps.
async function drawMarked(state: Scene): Promise<void> {
  if (state.renderer === null)
    throw new Error("the diagram renderer is not ready");
  state.watcher ??= state.renderer.observeDiagrams(state.root, {
    focusable: true,
  });
  await settle(state);
}

// Lets the renderer's queue run until no marked diagram is left in the page.
async function settle(state: Scene): Promise<void> {
  for (let turn = 0; turn < 200; turn += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0));
    if (state.root.querySelector(MARKER) === null) return;
  }
  throw new Error("a marked diagram was never replaced");
}

function drawnFigures(state: Scene): Element[] {
  return [
    ...state.root.querySelectorAll(
      'figure.bnest-diagram[data-bnest-diagram-state="drawn"]',
    ),
  ];
}

function latestFigure(state: Scene): Element {
  const figure = drawnFigures(state).at(-1);
  if (figure === undefined) throw new Error("no drawn diagram is on the page");
  return figure;
}

function bindMarked(prompt: string, index = 0): StepHandler {
  return async (context) => {
    const state = ensureScene();
    addReply(state, [markedBlock(sourceOf(prompt, index))]);
    return context;
  };
}

function givenDrawn(prompt: string): StepHandler {
  return async (context) => {
    const state = ensureScene();
    addReply(state, [markedBlock(sourceOf(prompt))]);
    await drawMarked(state);
    state.figure = latestFigure(state);
    return context;
  };
}

const step = (expression: string, handler: StepHandler): StepDefinition => ({
  expression,
  handler,
});

/** Each step returns the context it was given; the scene is the state the scenario shares. */
export function codexDiagramSteps(): StepDefinition[] {
  return [
    // Given
    step("the diagram engine cannot be loaded", async (context) => {
      ensureScene().engineAvailable = false;
      return context;
    }),
    step("the first start of the diagram engine fails", async (context) => {
      ensureScene().engineFailuresLeft = 1;
      return context;
    }),
    step(
      "a completed Codex reply marks a flowchart for drawing",
      bindMarked("Show a flowchart"),
    ),
    step(
      "a completed Codex reply marks a flowchart with a syntax error for drawing",
      bindMarked("Show a broken diagram"),
    ),
    step(
      "a completed Codex reply holds hostile diagram text",
      async (context) => {
        const state = ensureScene();
        // Mermaid escapes the diagram text, so this engine stands in for one that let markup through. The renderer's
        // SVG check (the real svgToImage) must refuse the picture, and the text stays as text.
        state.hostileSvg = HOSTILE_SVG;
        // The reply is what the server renders for the hostile fixture: the labels fence marked, the click and the
        // shape-data fences refused with their notes. Removing the shape-data gate on the server changes this output.
        addReply(state, renderedReply("Show hostile diagram text"));
        return context;
      },
    ),
    step(
      "a completed Codex reply shows a drawn flowchart with its source open",
      async (context) => {
        const state = ensureScene();
        await givenDrawn("Show a flowchart")(context);
        latestFigure(state).querySelector("details")?.setAttribute("open", "");
        return context;
      },
    ),
    step(
      "a completed Codex reply shows a drawn flowchart",
      givenDrawn("Show a flowchart"),
    ),
    step(
      "a completed Codex reply marks a wide flowchart for drawing",
      bindMarked("Show a wide flowchart"),
    ),
    step(
      "a completed Codex reply marks the largest allowed flowchart for drawing",
      async (context) => {
        const state = ensureScene();
        const source = sourceOf("Show the largest allowed flowchart");
        state.largest = source;
        addReply(state, [markedBlock(source)]);
        return context;
      },
    ),
    step("a completed Codex reply has no diagram", async (context) => {
      addReply(ensureScene(), [
        paragraph("Here is a plain answer. It has no diagram."),
      ]);
      return context;
    }),

    // When
    step("the browser draws the marked diagrams", async (context) => {
      await drawMarked(ensureScene());
      return context;
    }),
    step("a later reply changes the conversation", async (context) => {
      const state = ensureScene();
      addReply(state, [paragraph("Here is a plain answer.")]);
      await settle(state);
      return context;
    }),
    step("the visitor clears the chat in the browser", async (context) => {
      ensureScene().root.replaceChildren();
      return context;
    }),
    step("a later reply marks a flowchart for drawing", async (context) => {
      const state = ensureScene();
      addReply(state, [markedBlock(sourceOf("Show a second flowchart"))]);
      await settle(state);
      return context;
    }),
    step("the diagram engine retry window has passed", async (context) => {
      ensureScene().clockOffset += LIMITS.engineRetryMs;
      return context;
    }),
    step("the network is cut", async (context) => {
      // The engine is already in memory after its first load, so cutting the network must not stop a draw.
      ensureScene().engineAvailable = false;
      return context;
    }),
    step("the browser draws the same flowchart again", async (context) => {
      const state = ensureScene();
      addReply(state, [markedBlock(FLOWCHART)]);
      await settle(state);
      return context;
    }),
    step("the chat page loads", async (context) => {
      await drawMarked(ensureScene());
      return context;
    }),

    // Then
    step("the picture is labelled {string}", async (context, label: string) => {
      const canvas = latestFigure(ensureScene()).querySelector(
        ".bnest-diagram-canvas",
      );
      expect(canvas?.getAttribute("role")).toBe("img");
      expect(canvas?.getAttribute("aria-label")?.startsWith(`${label}.`)).toBe(
        true,
      );
      return context;
    }),
    step(
      "the diagram source {string} is kept as text",
      async (context, source: string) => {
        const texts = [
          ...ensureScene().root.querySelectorAll("figure pre code"),
        ].map((code) => code.textContent ?? "");
        expect(texts.some((text) => text.includes(source))).toBe(true);
        return context;
      },
    ),
    step("the picture loads nothing from another origin", async (context) => {
      const state = ensureScene();
      // A figure must exist before the loop, so an empty page cannot pass. Each picture is decoded and checked.
      const figures = [...state.root.querySelectorAll("figure.bnest-diagram")];
      expect(figures.length).toBeGreaterThan(0);
      for (const figure of figures) {
        const img = figure.querySelector("img");
        if (figure.getAttribute("data-bnest-diagram-state") === "drawn") {
          expect(img).not.toBeNull();
        }
        if (img === null) continue;
        const src = img.getAttribute("src") ?? "";
        expect(src.startsWith(SVG_URL_PREFIX)).toBe(true);
        const svg = decodeURIComponent(src.slice(src.indexOf(",") + 1));
        expect(svg.startsWith("<svg")).toBe(true);
        expect(EXTERNAL_REFERENCE.test(svg)).toBe(false);
      }
      for (const element of state.root.querySelectorAll(
        "figure [src], figure [href]",
      )) {
        for (const name of ["src", "href"]) {
          const value = element.getAttribute(name) ?? "";
          expect(/^https?:/iu.test(value)).toBe(false);
        }
      }
      return context;
    }),
    step(
      "the diagram shows the note {string}",
      async (context, note: string) => {
        const notes = [
          ...ensureScene().root.querySelectorAll("figure p.bnest-diagram-note"),
        ];
        expect(notes.map((element) => element.textContent)).toContain(note);
        return context;
      },
    ),
    step(
      "no script or event handler from the diagram text runs",
      async (context) => {
        const state = ensureScene();
        expect(state.root.querySelector("script")).toBeNull();
        for (const element of state.root.querySelectorAll("*")) {
          for (const attribute of element.getAttributeNames()) {
            expect(attribute.startsWith("on")).toBe(false);
          }
        }
        return context;
      },
    ),
    step(
      "the diagram with shape data is not drawn and shows the note that settings are not allowed",
      async (context) => {
        const root = ensureScene().root;
        const shape = [...root.querySelectorAll("code.language-mermaid")].find(
          (code) => (code.textContent ?? "").includes("imageSquare"),
        );
        expect(shape).toBeDefined();
        const pre = shape?.closest("pre");
        expect(pre?.hasAttribute("data-bnest-diagram")).toBe(false);
        // No element the server marked for drawing carries the shape-data text.
        for (const marked of root.querySelectorAll("[data-bnest-diagram]")) {
          expect(marked.textContent ?? "").not.toContain("imageSquare");
        }
        expect(pre?.nextElementSibling?.querySelector("em")?.textContent).toBe(
          "Diagram not drawn: it uses settings that are not allowed.",
        );
        return context;
      },
    ),
    step("the diagram text shows as text only", async (context) => {
      // The hostile picture is refused by the SVG check, so its figure is the note with the source as text.
      const figure = ensureScene().root.querySelector(
        'figure.bnest-diagram[data-reason="unsafe"]',
      );
      expect(figure).not.toBeNull();
      expect(figure?.querySelector("img")).toBeNull();
      const code = figure?.querySelector("pre code");
      expect(code?.children.length).toBe(0);
      expect(code?.textContent).toContain("<script>");
      return context;
    }),
    step("the picture is the same node as before", async (context) => {
      const state = ensureScene();
      expect(state.figure).not.toBeNull();
      expect(state.root.querySelector("figure")).toBe(state.figure);
      return context;
    }),
    step("the diagram source is still open", async (context) => {
      const state = ensureScene();
      expect(state.figure?.querySelector("details")?.hasAttribute("open")).toBe(
        true,
      );
      return context;
    }),
    step(
      "the conversation holds {int} flowchart picture(s)",
      async (context, count: string) => {
        expect(drawnFigures(ensureScene())).toHaveLength(Number(count));
        return context;
      },
    ),
    step("no diagram picture remains", async (context) => {
      expect(
        ensureScene().root.querySelectorAll("figure.bnest-diagram"),
      ).toHaveLength(0);
      return context;
    }),
    step("the picture fits its own box at 320 pixels", async (context) => {
      // The width of a narrow picture is its natural width, so the declared rule keeps it inside its box (the
      // layout itself is measured in Chromium by bnest-app-fe-e2e).
      const figure = latestFigure(ensureScene());
      expect(
        figure
          .querySelector("img")
          ?.style.getPropertyValue("--bnest-diagram-width"),
      ).not.toBe("");
      expect(
        declaredDiagramBlock(CANVAS_SELECTOR).includes("max-width: 100%;"),
      ).toBe(true);
      expect(
        declaredDiagramBlock(PICTURE_SELECTOR).includes(PICTURE_WIDTH_RULE),
      ).toBe(true);
      return context;
    }),
    step("the picture keeps a readable size at 320 pixels", async (context) => {
      // The picture is never narrower than 0.75 of its natural width or 30rem: a 16 px label stays at 12 px or more.
      const picture = declaredDiagramBlock(PICTURE_SELECTOR);
      expect(
        picture.includes(PICTURE_WIDTH_RULE),
        "the picture may shrink below its readable width",
      ).toBe(true);
      expect(
        picture.includes("min-width:"),
        "the picture still has a shrink-only minimum",
      ).toBe(false);
      return context;
    }),
    step(
      "the picture scrolls inside its own box at 320 pixels",
      async (context) => {
        // The layout is measured in Chromium. Here: the picture is a focusable image box that declares its own
        // natural width, which the stylesheet keeps at its readable width and scrolls beyond the bubble.
        const figure = latestFigure(ensureScene());
        const canvas = figure.querySelector(".bnest-diagram-canvas");
        const img = figure.querySelector("img");
        // happy-dom has no layout: the canvas is given a wider picture than its box, then the product's own focus rule
        // runs again. The overflow itself is measured in Chromium (codex_diagrams_layout.steps.ts).
        if (canvas instanceof HTMLElement) {
          Object.defineProperty(canvas, "scrollWidth", {
            configurable: true,
            value: 900,
          });
          Object.defineProperty(canvas, "clientWidth", {
            configurable: true,
            value: 320,
          });
        }
        if (!(figure instanceof HTMLElement))
          throw new Error("the latest figure is not an element");
        setFocusable(figure, true);
        expect(canvas?.getAttribute("tabindex")).toBe("0");
        expect(img?.getAttribute("width")).not.toBeNull();
        expect(img?.style.getPropertyValue("--bnest-diagram-width")).toBe(
          `${img?.getAttribute("width")}px`,
        );
        expect(
          declaredDiagramBlock(CANVAS_SELECTOR).includes("overflow-x: auto;"),
        ).toBe(true);
        expect(
          declaredDiagramBlock(PICTURE_SELECTOR).includes(PICTURE_WIDTH_RULE),
        ).toBe(true);
        return context;
      },
    ),
    step("the diagram engine stays available", async (context) => {
      const state = ensureScene();
      expect(state.importCount).toBe(1);
      expect(drawnFigures(state).length).toBeGreaterThan(0);
      return context;
    }),
    step("the diagram engine was not requested", async (context) => {
      expect(ensureScene().importCount).toBe(0);
      return context;
    }),
    step(
      "the largest allowed flowchart is drawn within the draw time limit",
      async (context) => {
        // The time is measured and bounded in Chromium (bnest-app-fe-e2e). Here the source must pass the limits the
        // server and the browser share, and the renderer must draw it.
        const state = ensureScene();
        expect(state.largest).not.toBeNull();
        expect(checkSource(state.largest ?? "")).toBe(true);
        expect(drawnFigures(state).length).toBeGreaterThan(0);
        return context;
      },
    ),
  ];
}
