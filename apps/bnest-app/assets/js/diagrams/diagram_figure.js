// ADR 004, Decisions 1, 3 and 5: the figure a diagram becomes. The picture is shown through an <img> with
// a data: URL, so the SVG never becomes page markup. Every string from the author (the source, the
// labels) goes in with textContent, and the DOM is built with createElement only.

import { LIMITS } from "./diagram_limits.js";

/**
 * The note a reader sees for each failure. One wording for both phases: "Diagram not drawn: <reason>.", the
 * same form as the server's refusal note (ChatMarkdown.refusal_note/1), so a reader never sees two phrasings.
 * `render` (Mermaid failed after the text parsed) reuses the syntax note.
 *
 * @type {Readonly<Record<string, string>>}
 */
export const FALLBACK_NOTES = Object.freeze({
  syntax: "Diagram not drawn: it has a syntax error.",
  render: "Diagram not drawn: it has a syntax error.",
  limits: "Diagram not drawn: it is too large.",
  timeout: "Diagram not drawn: it took too long to draw.",
  unavailable: "Diagram not drawn: the diagram tool did not load.",
  unsafe: "Diagram not drawn: its picture failed a safety check.",
  "page-limit": `Diagram not drawn: only the first ${LIMITS.maxPerPage} diagrams on a page are drawn.`,
});

const SVG_URL_PREFIX = "data:image/svg+xml;charset=utf-8,";

/**
 * Markup that must never reach the picture. `on*=` is an attribute of a tag; text that merely contains
 * `onerror=` is escaped by Mermaid, so it does not match.
 */
const REFUSED_MARKUP = [
  /<script/iu,
  /<foreignObject/iu,
  /<iframe/iu,
  /<image/iu,
  /<[a-z][^>]*\son[a-z]+\s*=/iu,
  /javascript:/iu,
];

/**
 * @param {number} value
 * @returns {number} a whole number from 1 to 4000
 */
function clampSize(value) {
  return Math.min(4000, Math.max(1, Math.round(value)));
}

/**
 * Checks Mermaid's SVG and turns it into an image address. Throws when the text is not an SVG within the
 * size limit, has no positive viewBox, or contains any refused markup.
 *
 * @param {string} svg
 * @returns {{ src: string, width: number, height: number }}
 */
export function svgToImage(svg) {
  if (
    typeof svg !== "string" ||
    svg.length > LIMITS.maxSvgChars ||
    !svg.startsWith("<svg")
  ) {
    throw new Error("unsafe picture: not an svg within the size limit");
  }
  if (REFUSED_MARKUP.some((pattern) => pattern.test(svg))) {
    throw new Error("unsafe picture: refused markup");
  }

  const viewBox = /viewBox\s*=\s*["']([^"']*)["']/iu.exec(svg)?.[1];
  const numbers = (viewBox ?? "")
    .trim()
    .split(/[\s,]+/u)
    .map(Number);
  const [, , width, height] = numbers;
  if (
    numbers.length !== 4 ||
    !numbers.every((value) => Number.isFinite(value)) ||
    width === undefined ||
    height === undefined ||
    width <= 0 ||
    height <= 0
  ) {
    throw new Error("unsafe picture: no positive viewBox");
  }

  return {
    src: SVG_URL_PREFIX + encodeURIComponent(svg),
    width: clampSize(width),
    height: clampSize(height),
  };
}

/**
 * @param {string} tag
 * @param {string} [className]
 * @returns {HTMLElement}
 */
function element(tag, className) {
  const node = document.createElement(tag);
  if (className !== undefined) node.className = className;
  return node;
}

/**
 * Sets whether the canvas and the source summary are keyboard stops. The Codex chat wants the canvas
 * focusable so a keyboard reader can scroll a wide picture. Family Chat keeps both out of the tab order, and
 * raises the source when its message is the history's stop and the picture only while it overflows
 * (ADR 004, Decision 3 and ADR 003, Decision 6; family_chat/message_content_stops.js applies that).
 *
 * @param {HTMLElement} figure
 * @param {boolean} focusable
 */
export function setFocusable(figure, focusable) {
  const canvas = figure.querySelector(".bnest-diagram-canvas");
  // A picture that fits its box has nothing to scroll, so it is not a keyboard stop. Measured where it is shown.
  if (canvas instanceof HTMLElement) {
    canvas.tabIndex =
      focusable && canvas.scrollWidth > canvas.clientWidth ? 0 : -1;
  }

  const summary = figure.querySelector(".bnest-diagram-source > summary");
  if (summary instanceof HTMLElement) {
    if (focusable) summary.removeAttribute("tabindex");
    else summary.tabIndex = -1;
  }
}

/**
 * The figure for a drawn diagram: the picture (a labelled canvas) and the source in a disclosure.
 *
 * @param {{
 *   image: { src: string, width: number, height: number },
 *   kind: string,
 *   source: string,
 *   focusable: boolean
 * }} options
 * @returns {HTMLElement}
 */
export function drawnFigure({ image, kind, source, focusable }) {
  const figure = element("figure", "bnest-diagram");
  figure.dataset["bnestDiagramState"] = "drawn";
  figure.setAttribute("aria-live", "off");

  const canvas = element("div", "bnest-diagram-canvas");
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", `${kind}. The diagram source follows.`);

  const img = document.createElement("img");
  img.alt = "";
  img.src = image.src;
  img.width = image.width;
  img.height = image.height;
  img.decoding = "async";
  img.style.setProperty("--bnest-diagram-width", `${image.width}px`);
  canvas.append(img);

  const details = element("details", "bnest-diagram-source");
  const summary = document.createElement("summary");
  summary.textContent = "Diagram source";
  const code = document.createElement("code");
  code.textContent = source;
  const pre = document.createElement("pre");
  pre.append(code);
  details.append(summary, pre);

  figure.append(canvas, details);
  setFocusable(figure, focusable);
  return figure;
}

/**
 * The figure for a diagram that was not drawn: a note saying why, and the source as text.
 *
 * @param {{ reason: keyof typeof FALLBACK_NOTES, source: string }} options
 * @returns {HTMLElement}
 */
export function fallbackFigure({ reason, source }) {
  const figure = element("figure", "bnest-diagram");
  figure.dataset["bnestDiagramState"] = "fallback";
  figure.dataset["reason"] = reason;
  // Not in ADR 004's fallback markup; added so a Codex reply's polite live region does not read the note
  // again when it is inserted, the same as the drawn figure.
  figure.setAttribute("aria-live", "off");

  const note = element("p", "bnest-diagram-note");
  note.setAttribute("role", "note");
  note.textContent = FALLBACK_NOTES[reason] ?? FALLBACK_NOTES["syntax"] ?? "";

  const code = document.createElement("code");
  code.textContent = source;
  const pre = document.createElement("pre");
  pre.append(code);

  figure.append(note, pre);
  return figure;
}
