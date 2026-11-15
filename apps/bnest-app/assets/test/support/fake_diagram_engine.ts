// A stand-in for the lazily loaded diagram engine (`assets/js/diagrams/engine.js`) in the Vitest scenarios of Family
// Chat and of Codex replies. It keeps the engine contract (`ENGINE_API` 1, `loadEngine`), so the shipped renderer
// runs its real queue, cache, figure and placement code against it. Mermaid's own layout needs a real browser, so the
// picture here is a plain SVG; Chromium draws the real engine in `bnest-app-fe-e2e`. This is the one fake of the
// engine: a scenario that needs another answer wraps `renderDiagram` rather than copying it.

export const ENGINE_API = 1;

/** A flowchart line that ends in an arrow is a syntax error here, as a dangling edge is for Mermaid. */
export async function renderDiagram(source: string): Promise<{ svg: string }> {
  const lines = source.trimEnd().split("\n");
  if ((lines.at(-1) ?? "").trimEnd().endsWith("-->")) {
    throw Object.assign(new Error("Parse error"), {
      name: "DiagramError",
      kind: "syntax",
    });
  }
  const edges = source.split("-->").length - 1;
  const width = 360 + 80 * edges;
  // Text is escaped, as Mermaid escapes a label, so a label that looks like markup stays text in the picture.
  const text = source
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
  return {
    svg: `<svg viewBox="0 0 ${width} 418"><g><text>${text}</text></g></svg>`,
  };
}

// While held, the start waits, as the real module's start waits for its request to finish. A scenario holds it to press
// keys while a marked diagram is still its source, then releases it. Open by default, so other scenarios are unchanged.
// The hold lives on globalThis: the page imports this module through its own address, which Vitest evaluates as a
// separate module instance, so a module-level variable would hold nothing the page's loadEngine can see.
interface EngineHold {
  start: Promise<void>;
  open: () => void;
}
const HOLD_KEY = Symbol.for("bnest.test.diagramEngineHold");

function engineHold(): { current: EngineHold | null } {
  const host = globalThis as typeof globalThis & {
    [HOLD_KEY]?: { current: EngineHold | null };
  };
  host[HOLD_KEY] ??= { current: null };
  return host[HOLD_KEY];
}

export function holdDiagramEngine(): void {
  let open: () => void = () => undefined;
  const start = new Promise<void>((resolve) => {
    open = resolve;
  });
  engineHold().current = { start, open };
}

export function releaseDiagramEngine(): void {
  const hold = engineHold();
  hold.current?.open();
  hold.current = null;
}

/** The module's start, with engine.js's contract: the engine's API, once it has started. */
export async function loadEngine(): Promise<{
  renderDiagram: typeof renderDiagram;
}> {
  const hold = engineHold().current;
  if (hold) await hold.start;
  return { renderDiagram };
}
