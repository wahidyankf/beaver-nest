// @vitest-environment happy-dom
// ADR 004, Decision 3 (lifecycle) and Decision 4 (caps, timeout, engine retry). The engine is replaced by
// a fake, because real layout needs a browser (Chromium e2e checks the drawn picture). Timers and the
// viewport observer are injected, so every test runs without waiting.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  createDiagramRenderer,
  type RendererDeps,
} from "../../../js/diagrams/mermaid_diagrams.js";
import { LIMITS } from "../../../js/diagrams/diagram_limits.js";

const SELECTOR = 'pre[data-bnest-diagram="mermaid"]';
const SOURCE = "flowchart TD\n  A --> B";
const OK_SVG = '<svg viewBox="0 0 360 418"><g><text>A</text></g></svg>';
const THEME_A = {
  themeVariables: { primaryColor: "rgb(216, 241, 236)" },
  themeSignature: "primaryColor=rgb(216, 241, 236)",
};
const THEME_B = {
  themeVariables: { primaryColor: "rgb(0, 0, 0)" },
  themeSignature: "primaryColor=rgb(0, 0, 0)",
};

type Theme = typeof THEME_A;
type Callback = (
  entries: { target: Element; isIntersecting: boolean }[],
) => void;

interface FakeIntersection {
  observe(target: Element): void;
  unobserve(target: Element): void;
  disconnect(): void;
  intersect(target: Element): void;
  observed: Set<Element>;
  disconnected: boolean;
}

interface Harness {
  renderer: ReturnType<typeof createDiagramRenderer>;
  root: HTMLElement;
  renderDiagram: ReturnType<
    typeof vi.fn<
      (
        source: string,
        theme: Record<string, string>,
      ) => Promise<{ svg: string }>
    >
  >;
  importEngine: ReturnType<typeof vi.fn<() => Promise<unknown>>>;
  discard: ReturnType<typeof vi.fn<() => void>>;
  yieldTurn: ReturnType<typeof vi.fn<() => Promise<void>>>;
  clock: { now: number };
  theme: { current: Theme };
  fireTimers(): void;
  section(): HTMLElement;
  intersection: FakeIntersection | null;
}

/** A fresh page root and a renderer whose engine, theme, clock and timers the test controls. */
function harness({
  intersection = false,
}: { intersection?: boolean } = {}): Harness {
  const root = document.createElement("div");
  document.body.append(root);

  const renderDiagram = vi.fn<
    (source: string, theme: Record<string, string>) => Promise<{ svg: string }>
  >(async () => ({ svg: OK_SVG }));
  const discard = vi.fn<() => void>();
  const engine = { ENGINE_API: 1, renderDiagram, discard };
  const importEngine = vi.fn<() => Promise<unknown>>(async () => engine);
  const yieldTurn = vi.fn<() => Promise<void>>(async () => undefined);
  const clock = { now: 0 };
  const theme = { current: THEME_A };
  const timers: { callback: () => void; cleared: boolean }[] = [];

  const state: { intersection: FakeIntersection | null } = {
    intersection: null,
  };
  const createIntersectionObserver = (
    callback: Callback,
  ): FakeIntersection | null => {
    if (!intersection) return null;
    const observed = new Set<Element>();
    const fake: FakeIntersection = {
      observed,
      disconnected: false,
      observe: (target) => observed.add(target),
      unobserve: (target) => observed.delete(target),
      disconnect() {
        observed.clear();
        this.disconnected = true;
      },
      intersect: (target) => callback([{ target, isIntersecting: true }]),
    };
    state.intersection = fake;
    return fake;
  };

  // Timer handles are numbers, as in the browser; each maps to its fake timer.
  let nextHandle = 1;
  const handles = new Map<number, { callback: () => void; cleared: boolean }>();

  const deps: RendererDeps = {
    importEngine,
    readTheme: () => theme.current,
    now: () => clock.now,
    setTimer: (callback) => {
      const handle = nextHandle;
      nextHandle += 1;
      const timer = { callback, cleared: false };
      timers.push(timer);
      handles.set(handle, timer);
      return handle;
    },
    clearTimer: (handle) => {
      const timer = handles.get(handle);
      if (timer !== undefined) timer.cleared = true;
    },
    yieldTurn,
    createIntersectionObserver,
  };

  return {
    renderer: createDiagramRenderer(deps),
    root,
    renderDiagram,
    importEngine,
    discard,
    yieldTurn,
    clock,
    theme,
    get intersection() {
      return state.intersection;
    },
    fireTimers() {
      for (const timer of timers.splice(0)) {
        if (!timer.cleared) timer.callback();
      }
    },
    /** A new container inside the page, so the diagrams in it stay connected. */
    section() {
      const div = document.createElement("div");
      root.append(div);
      return div;
    },
  };
}

/** A marked diagram exactly as the server writes it: the source is text inside the code element. */
function marked(source: string): HTMLPreElement {
  const pre = document.createElement("pre");
  pre.setAttribute("data-bnest-diagram", "mermaid");
  const code = document.createElement("code");
  code.textContent = source;
  pre.append(code);
  return pre;
}

/** Lets every queued promise and mutation record run. */
const flush = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

const drawnIn = (root: ParentNode) =>
  root.querySelectorAll('figure[data-bnest-diagram-state="drawn"]').length;

const reasonIn = (root: ParentNode) =>
  root.querySelector("figure[data-reason]")?.getAttribute("data-reason") ??
  null;

/** An engine error with the name and kind the engine module gives a parse failure. */
function engineError(
  kind: "syntax" | "limits" | "render",
  message: string,
): Error {
  return Object.assign(new Error(message), { name: "DiagramError", kind });
}

describe("drawing marked diagrams", () => {
  let page: Harness;

  beforeEach(() => {
    page = harness();
  });

  afterEach(() => {
    page.root.remove();
  });

  it("replaces a marked diagram with a drawn figure and leaves unmarked code alone", async () => {
    const plain = document.createElement("pre");
    const plainCode = document.createElement("code");
    plainCode.className = "language-mermaid";
    plainCode.textContent = SOURCE;
    plain.append(plainCode);
    page.root.append(plain, marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(drawnIn(page.root)).toBe(1);
    expect(page.root.querySelector(SELECTOR)).toBeNull();
    expect(
      page.root.querySelector(
        "pre:not([data-bnest-diagram]) > code.language-mermaid",
      ),
    ).not.toBeNull();
  });

  it("does not load the engine when the page has no marked diagram", async () => {
    page.root.append(document.createElement("p"));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(page.importEngine).not.toHaveBeenCalled();
  });

  it("loads the engine once for many diagrams and draws with the exact source and theme", async () => {
    page.root.append(marked(SOURCE), marked("graph LR\n  C --> D"));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(page.importEngine).toHaveBeenCalledTimes(1);
    expect(page.renderDiagram).toHaveBeenCalledWith(
      SOURCE,
      THEME_A.themeVariables,
    );
  });
});

describe("the serial draw queue", () => {
  it("draws one diagram at a time and starts the next only after the first resolves", async () => {
    const page = harness();
    const resolvers: (() => void)[] = [];
    page.renderDiagram.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolvers.push(() => resolve({ svg: OK_SVG }));
        }),
    );
    page.root.append(
      marked("flowchart TD\n  A --> B"),
      marked("flowchart TD\n  C --> D"),
    );

    page.renderer.observeDiagrams(page.root);
    await flush();
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);

    resolvers[0]?.();
    await flush();
    expect(page.renderDiagram).toHaveBeenCalledTimes(2);
    resolvers[1]?.();
    await flush();
    expect(drawnIn(page.root)).toBe(2);
  });

  it("yields to the event loop between draws", async () => {
    const page = harness();
    page.root.append(
      marked("flowchart TD\n  A --> B"),
      marked("flowchart TD\n  C --> D"),
    );

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(page.yieldTurn).toHaveBeenCalledTimes(2);
  });
});

describe("the viewport gate", () => {
  it("does not draw a diagram until it is near the viewport", async () => {
    const page = harness({ intersection: true });
    const pre = marked(SOURCE);
    page.root.append(pre);

    page.renderer.observeDiagrams(page.root);
    await flush();
    expect(page.renderDiagram).not.toHaveBeenCalled();

    page.intersection?.intersect(pre);
    await flush();
    expect(drawnIn(page.root)).toBe(1);
  });

  it("draws at once when there is no viewport observer", async () => {
    const page = harness({ intersection: false });
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(drawnIn(page.root)).toBe(1);
  });
});

describe("the cache", () => {
  it("places a repeat of a drawn source at once, without drawing it again", async () => {
    const page = harness();
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    const second = page.section();
    second.append(marked(SOURCE));
    page.renderer.observeDiagrams(second);

    expect(drawnIn(second)).toBe(1);
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
  });

  it("draws a source again when the theme signature changes", async () => {
    const page = harness();
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    page.theme.current = THEME_B;
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(page.renderDiagram).toHaveBeenCalledTimes(2);
  });

  it("draws one picture for two diagrams with the same source in one batch, and clones the second", async () => {
    const page = harness();
    page.root.append(marked(SOURCE), marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    const figures = [...page.root.querySelectorAll("figure")];
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
    expect(figures).toHaveLength(2);
    expect(figures[0]).not.toBe(figures[1]);
  });

  it("keeps a syntax failure, so the same source is not sent to the engine again", async () => {
    const page = harness();
    page.renderDiagram.mockRejectedValueOnce(
      engineError("syntax", "Parse error on line 2"),
    );
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    const second = page.section();
    second.append(marked(SOURCE));
    page.renderer.observeDiagrams(second);

    expect(reasonIn(second)).toBe("syntax");
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
  });

  it("evicts the oldest of the 24 entries", async () => {
    const page = harness();
    const sources = Array.from(
      { length: LIMITS.cacheEntries + 1 },
      (_, index) => `flowchart TD\n  A${index} --> B`,
    );
    page.root.append(...sources.map((source) => marked(source)));
    page.renderer.observeDiagrams(page.root);
    await flush();
    expect(page.renderDiagram).toHaveBeenCalledTimes(LIMITS.cacheEntries + 1);

    const again = page.section();
    again.append(marked(sources[0] ?? ""));
    page.renderer.observeDiagrams(again);
    await flush();

    expect(page.renderDiagram).toHaveBeenCalledTimes(LIMITS.cacheEntries + 2);
  });
});

describe("limits before the engine loads", () => {
  it("shows a source over 6000 bytes as limits, without loading the engine", async () => {
    const page = harness();
    page.root.append(
      marked(`flowchart TD\n${"A".repeat(LIMITS.maxSourceBytes)}`),
    );

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("limits");
    expect(page.importEngine).not.toHaveBeenCalled();
  });

  it("shows an unsupported type as limits, without loading the engine", async () => {
    const page = harness();
    page.root.append(marked("architecture-beta\n  group api(cloud)[API]"));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("limits");
    expect(page.importEngine).not.toHaveBeenCalled();
  });
});

describe("engine failures", () => {
  it("shows a parse error as syntax and keeps the source as text", async () => {
    const page = harness();
    page.renderDiagram.mockRejectedValueOnce(
      engineError("syntax", "Parse error"),
    );
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("syntax");
    expect(page.root.querySelector("figure pre > code")?.textContent).toBe(
      SOURCE,
    );
  });

  it("shows a size or edge error from the engine as limits", async () => {
    const page = harness();
    page.renderDiagram.mockRejectedValueOnce(
      engineError("limits", "Edge limit exceeded"),
    );
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("limits");
  });

  it("shows a failure after a valid parse as render", async () => {
    const page = harness();
    page.renderDiagram.mockRejectedValueOnce(
      engineError("render", "layout exploded"),
    );
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("render");
  });

  it("shows a picture that fails the SVG check as unsafe, and keeps it as a failure", async () => {
    const page = harness();
    page.renderDiagram.mockResolvedValueOnce({
      svg: '<svg viewBox="0 0 10 10"><script>x()</script></svg>',
    });
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("unsafe");
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
  });

  it("gives unavailable when the engine module does not load, and keeps the source", async () => {
    const page = harness();
    page.importEngine.mockRejectedValueOnce(new Error("chunk request aborted"));
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("unavailable");
    expect(page.root.querySelector("figure pre > code")?.textContent).toBe(
      SOURCE,
    );
  });

  it("gives unavailable for an engine with another API version", async () => {
    const page = harness();
    page.importEngine.mockResolvedValueOnce({
      ENGINE_API: 2,
      renderDiagram: page.renderDiagram,
    });
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("unavailable");
  });

  it("remembers a failed load for 30 seconds, then tries again", async () => {
    const page = harness();
    page.importEngine.mockRejectedValueOnce(new Error("offline"));
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();
    expect(page.importEngine).toHaveBeenCalledTimes(1);

    page.clock.now = LIMITS.engineRetryMs - 1;
    const inWindow = page.section();
    inWindow.append(marked("graph LR\n  C --> D"));
    page.renderer.observeDiagrams(inWindow);
    await flush();
    expect(reasonIn(inWindow)).toBe("unavailable");
    expect(page.importEngine).toHaveBeenCalledTimes(1);

    page.clock.now = LIMITS.engineRetryMs;
    const afterWindow = page.section();
    afterWindow.append(marked("graph LR\n  E --> F"));
    page.root.append(afterWindow);
    page.renderer.observeDiagrams(afterWindow);
    await flush();
    expect(page.importEngine).toHaveBeenCalledTimes(2);
    expect(drawnIn(afterWindow)).toBe(1);
  });

  it("does not keep an unavailable result, so the source draws after the window", async () => {
    const page = harness();
    page.importEngine.mockRejectedValueOnce(new Error("offline"));
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    page.clock.now = LIMITS.engineRetryMs;
    const again = page.section();
    again.append(marked(SOURCE));
    page.renderer.observeDiagrams(again);
    await flush();

    expect(drawnIn(again)).toBe(1);
  });
});

describe("the draw timeout", () => {
  it("shows a diagram that takes longer than 8 seconds as timeout", async () => {
    const page = harness();
    page.renderDiagram.mockImplementationOnce(
      () => new Promise<{ svg: string }>(() => undefined),
    );
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();
    page.fireTimers();
    await flush();

    expect(reasonIn(page.root)).toBe("timeout");
  });

  it("does not keep a timeout, so the next draw of the same source tries the engine again", async () => {
    const page = harness();
    page.renderDiagram.mockImplementationOnce(
      () => new Promise<{ svg: string }>(() => undefined),
    );
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();
    page.fireTimers();
    await flush();

    const again = page.section();
    again.append(marked(SOURCE));
    page.renderer.observeDiagrams(again);
    await flush();

    expect(drawnIn(again)).toBe(1);
    expect(page.renderDiagram).toHaveBeenCalledTimes(2);
  });

  it("ignores a late result after the timeout", async () => {
    const page = harness();
    let late: ((value: { svg: string }) => void) | undefined;
    page.renderDiagram.mockImplementationOnce(
      () => new Promise((resolve) => (late = resolve)),
    );
    page.root.append(marked(SOURCE));

    page.renderer.observeDiagrams(page.root);
    await flush();
    page.fireTimers();
    await flush();
    late?.({ svg: OK_SVG });
    await flush();

    expect(reasonIn(page.root)).toBe("timeout");
    expect(drawnIn(page.root)).toBe(0);
  });
});

describe("a timed-out engine", () => {
  it("is discarded, so the next draw starts the engine again", async () => {
    const page = harness();
    page.renderDiagram.mockImplementationOnce(
      () => new Promise<{ svg: string }>(() => undefined),
    );
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();
    page.fireTimers();
    await flush();

    expect(page.discard).toHaveBeenCalledTimes(1);

    const again = page.section();
    again.append(marked(SOURCE));
    page.renderer.observeDiagrams(again);
    await flush();

    expect(page.importEngine).toHaveBeenCalledTimes(2);
    expect(drawnIn(again)).toBe(1);
  });

  it("is kept when a draw fails for another reason", async () => {
    const page = harness();
    page.renderDiagram.mockImplementationOnce(async () => {
      throw new Error("the render broke");
    });
    page.root.append(marked(SOURCE));
    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(reasonIn(page.root)).toBe("render");
    expect(page.discard).not.toHaveBeenCalled();
  });
});

describe("the page cap", () => {
  it("draws 30 diagrams on a page and keeps the rest as source with a note", async () => {
    const page = harness();
    const sources = Array.from(
      { length: LIMITS.maxPerPage + 1 },
      (_, index) => `flowchart TD\n  A${index} --> B`,
    );
    page.root.append(...sources.map((source) => marked(source)));

    page.renderer.observeDiagrams(page.root);
    await flush();

    expect(drawnIn(page.root)).toBe(LIMITS.maxPerPage);
    expect(
      page.root.querySelectorAll('figure[data-reason="page-limit"]'),
    ).toHaveLength(1);
  });
});

describe("removal and disconnect", () => {
  it("fills the cache but does not place a diagram whose node was removed while it drew", async () => {
    const page = harness();
    let finish: ((value: { svg: string }) => void) | undefined;
    page.renderDiagram.mockImplementationOnce(
      () => new Promise((resolve) => (finish = resolve)),
    );
    const pre = marked(SOURCE);
    page.root.append(pre);

    page.renderer.observeDiagrams(page.root);
    await flush();
    pre.remove();
    finish?.({ svg: OK_SVG });
    await flush();

    expect(drawnIn(page.root)).toBe(0);

    const later = page.section();
    later.append(marked(SOURCE));
    page.renderer.observeDiagrams(later);
    expect(drawnIn(later)).toBe(1);
    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
  });

  it("stops watching after disconnect, including a diagram waiting for the viewport", async () => {
    const page = harness({ intersection: true });
    const pre = marked(SOURCE);
    page.root.append(pre);

    const watcher = page.renderer.observeDiagrams(page.root);
    await flush();
    watcher.disconnect();
    page.intersection?.intersect(pre);
    page.root.append(marked("graph LR\n  C --> D"));
    await flush();

    expect(page.renderDiagram).not.toHaveBeenCalled();
    expect(page.intersection?.disconnected).toBe(true);
  });
});

describe("the observer", () => {
  it("draws a diagram added after the first scan", async () => {
    const page = harness();
    const watcher = page.renderer.observeDiagrams(page.root);

    page.root.append(marked(SOURCE));
    await flush();

    expect(drawnIn(page.root)).toBe(1);
    watcher.disconnect();
  });

  it("draws a diagram when its marker attribute is set later", async () => {
    const page = harness();
    const pre = document.createElement("pre");
    const code = document.createElement("code");
    code.textContent = SOURCE;
    pre.append(code);
    page.root.append(pre);
    const watcher = page.renderer.observeDiagrams(page.root);
    await flush();
    expect(page.renderDiagram).not.toHaveBeenCalled();

    pre.setAttribute("data-bnest-diagram", "mermaid");
    await flush();

    expect(drawnIn(page.root)).toBe(1);
    watcher.disconnect();
  });

  it("does not draw its own figure again", async () => {
    const page = harness();
    const watcher = page.renderer.observeDiagrams(page.root);
    page.root.append(marked(SOURCE));
    await flush();
    await flush();

    expect(page.renderDiagram).toHaveBeenCalledTimes(1);
    watcher.disconnect();
  });
});

describe("the focusable option", () => {
  // The picture overflows only where the browser lays it out, so a picture in this test fits its box and is not a stop.
  it("keeps a picture that fits out of the tab order when focusable is true", async () => {
    const page = harness();
    page.root.append(marked(SOURCE));

    const watcher = page.renderer.observeDiagrams(page.root, {
      focusable: true,
    });
    await flush();

    expect(
      page.root
        .querySelector(".bnest-diagram-canvas")
        ?.getAttribute("tabindex"),
    ).toBe("-1");
    watcher.disconnect();
  });

  it("removes the canvas and summary from the tab order by default", async () => {
    const page = harness();
    page.root.append(marked(SOURCE));

    const watcher = page.renderer.observeDiagrams(page.root);
    await flush();

    expect(
      page.root
        .querySelector(".bnest-diagram-canvas")
        ?.getAttribute("tabindex"),
    ).toBe("-1");
    expect(
      page.root
        .querySelector(".bnest-diagram-source > summary")
        ?.getAttribute("tabindex"),
    ).toBe("-1");
    watcher.disconnect();
  });
});
