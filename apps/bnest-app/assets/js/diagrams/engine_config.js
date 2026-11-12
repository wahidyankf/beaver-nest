// ADR 004, Decision 3: the one place that decides how Mermaid runs. It is pure, so tests read it
// without loading Mermaid. engine_core.js is the only caller.

import { LIMITS as SHARED_LIMITS } from "./diagram_limits.js";

/**
 * Limits from ADR 004, Decision 2 and Decision 3, read from diagram_limits.js so the renderer's checks and Mermaid's
 * config share one number. Mermaid enforces both values through its config; engine_core.js also checks the text
 * length before Mermaid runs (the source is at most `maxSourceBytes` bytes, so this is never the looser check).
 */
export const LIMITS = Object.freeze({
  maxTextSize: SHARED_LIMITS.maxSourceBytes,
  maxEdges: SHARED_LIMITS.maxEdges,
});

// Keys a `%%{init}%%` directive inside a diagram can never change. Mermaid's own list is these six
// keys; htmlLabels, flowchart and layout are added so a directive cannot switch labels back to HTML
// or select the ELK layout (its loader is a stub in this build).
const SECURE_KEYS = Object.freeze([
  "secure",
  "securityLevel",
  "startOnLoad",
  "maxTextSize",
  "suppressErrorRendering",
  "maxEdges",
  "htmlLabels",
  "flowchart",
  "layout",
]);

// The image cannot load web fonts, so the fallback is a system stack (ADR 004, Decision 3).
const FALLBACK_FONT = "system-ui, sans-serif";

/**
 * @param {Record<string, unknown>} themeVariables
 * @returns {Record<string, string>} the entries whose value is a string; others are dropped
 */
function stringValuesOnly(themeVariables) {
  /** @type {Record<string, string>} */
  const values = {};
  for (const [key, value] of Object.entries(themeVariables)) {
    if (typeof value === "string") values[key] = value;
  }
  return values;
}

/**
 * Builds a new strict Mermaid config for one draw.
 *
 * @param {Record<string, unknown>} themeVariables colours and font from the page tokens
 * @returns {import("mermaid").MermaidConfig}
 */
export function mermaidConfig(themeVariables) {
  const variables = stringValuesOnly(themeVariables);

  /** @type {import("mermaid").MermaidConfig} */
  const config = {
    startOnLoad: false,
    securityLevel: "strict",
    logLevel: "fatal",
    suppressErrorRendering: true,
    maxTextSize: LIMITS.maxTextSize,
    maxEdges: LIMITS.maxEdges,
    htmlLabels: false,
    // Mermaid reads the global htmlLabels first; the flowchart key is kept for the diagram that still reads it.
    flowchart: { htmlLabels: false },
    secure: [...SECURE_KEYS],
    // Every diagram reads this key. Mermaid's default is `elk`, whose loader is a stub here.
    layout: "dagre",
    theme: "base",
    themeVariables: variables,
    fontFamily: variables["fontFamily"] ?? FALLBACK_FONT,
  };
  return config;
}
