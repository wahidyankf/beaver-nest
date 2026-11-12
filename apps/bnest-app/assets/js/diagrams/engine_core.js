// ADR 004, Decision 3: the only module that imports `mermaid`. engine.js loads it on demand, inside a hidden
// frame (diagram_frame.js), so this module and its chunks cost nothing on a page without a diagram.

import mermaid from "mermaid";
import { LIMITS, mermaidConfig } from "./engine_config.js";

/** Mermaid's own wording for the two limits it enforces. */
const LIMIT_MESSAGE =
  /Edge limit exceeded|Maximum text size in diagram exceeded/u;

/**
 * A draw failure the caller maps to a reason: `syntax` (the parser refused the text), `limits` (the
 * text or edge count is over LIMITS), or `render` (Mermaid failed after the text parsed).
 */
export class DiagramError extends Error {
  /**
   * @param {"syntax" | "limits" | "render"} kind
   * @param {string} message
   * @param {{ cause?: unknown }} [options]
   */
  constructor(kind, message, options) {
    super(message, options);
    this.name = "DiagramError";
    /** @type {"syntax" | "limits" | "render"} */
    this.kind = kind;
  }
}

/** @type {number} */
let drawCount = 0;

/** @returns {string} an id no earlier draw on this page used */
function nextId() {
  drawCount += 1;
  return `bnest-diagram-${drawCount}`;
}

/**
 * @param {unknown} error
 * @param {"syntax" | "render"} kind
 * @returns {DiagramError}
 */
function toDiagramError(error, kind) {
  const message = error instanceof Error ? error.message : String(error);
  const reason = LIMIT_MESSAGE.test(message) ? "limits" : kind;
  return new DiagramError(reason, message, { cause: error });
}

/**
 * Mermaid draws into temporary elements (`d<id>`, and `i<id>` for a sandboxed frame) that a failed
 * render can leave in the body. Removing them is the only cleanup this module does.
 *
 * @param {string} id
 */
function removeLeftovers(id) {
  for (const leftover of [`d${id}`, `i${id}`, id]) {
    document.querySelector(`[id="${leftover}"]`)?.remove();
  }
}

/**
 * Draws one diagram. Resolves to Mermaid's SVG string, unchanged. Rejects with a DiagramError. The page bounds the whole
 * call with its draw timeout and discards this engine when that fires (diagram_draw.js), so no timer is kept here.
 *
 * @param {string} source the diagram text, as the reader's message contained it
 * @param {Record<string, unknown>} themeVariables colours and font from the page tokens
 * @returns {Promise<{ svg: string }>}
 */
export async function renderDiagram(source, themeVariables) {
  if (typeof source !== "string") {
    throw new TypeError("diagram source must be a string");
  }
  // Checked before Mermaid runs: Mermaid replaces an over-long text with its own error diagram
  // instead of throwing, so the reader would otherwise see a drawn error rather than the source.
  if (source.length > LIMITS.maxTextSize) {
    throw new DiagramError("limits", "diagram source is over the size limit");
  }

  const id = nextId();
  try {
    mermaid.initialize(mermaidConfig(themeVariables));

    try {
      await mermaid.parse(source);
    } catch (error) {
      throw toDiagramError(error, "syntax");
    }

    try {
      const { svg } = await mermaid.render(id, source);
      return { svg };
    } catch (error) {
      throw toDiagramError(error, "render");
    }
  } finally {
    removeLeftovers(id);
  }
}
