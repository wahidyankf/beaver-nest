// ADR 004, Decision 2 and Decision 3: the caps and the type allowlist the browser uses. The server
// (BnestAppWeb.ChatMarkdown.diagram_limits/0) is the authority: it refuses an unsafe fence before the
// browser sees a marker. These checks are a second line, and the Elixir drift test keeps the shared
// numbers equal.

/**
 * The numbers ADR 004 sets. `maxSourceBytes`, `maxLines`, `maxPerMessage` and the type words are shared
 * with the server; the rest are browser-only.
 */
export const LIMITS = Object.freeze({
  maxSourceBytes: 6000,
  maxLines: 200,
  maxEdges: 60,
  maxPerMessage: 4,
  maxPerPage: 30,
  renderTimeoutMs: 8000,
  // The first start of the engine (a frame and the chunks it fetches). Browser-only; a draw keeps renderTimeoutMs.
  engineStartTimeoutMs: 20000,
  maxSvgChars: 300000,
  cacheEntries: 24,
  engineRetryMs: 30000,
  prefetchMarginPx: 300,
});

/**
 * The first word of a type line, mapped to the name a reader hears for the diagram (the accessible
 * name). Only these words are drawn.
 *
 * @type {Readonly<Record<string, string>>}
 */
export const KINDS = Object.freeze({
  flowchart: "Flowchart",
  graph: "Flowchart",
  sequenceDiagram: "Sequence diagram",
  classDiagram: "Class diagram",
  stateDiagram: "State diagram",
  "stateDiagram-v2": "State diagram",
  erDiagram: "Entity-relationship diagram",
  pie: "Pie chart",
  gantt: "Gantt chart",
});

/**
 * The words a diagram may not contain, as whole words, without case. A diagram that links or runs code is refused,
 * and so is one whose shape data (`@{`) can name a picture. The server's gate (ChatMarkdown.not_allowed?/1) refuses
 * the same list, and the drift test keeps the two equal.
 *
 * @type {readonly string[]}
 */
export const NOT_ALLOWED_WORDS = Object.freeze([
  "callback",
  "call",
  "click",
  "href",
  "link",
  "links",
]);

/**
 * The character sequences a diagram may not contain: a directive (`%%{`) and shape data (`@{`).
 *
 * @type {readonly string[]}
 */
export const NOT_ALLOWED_TOKENS = Object.freeze(["%%{", "@{"]);

/**
 * A word boundary is any character that is not a letter, a digit or an underscore, so a space, a no-break space,
 * a `;` or a hyphen all end a word. The server's gate uses the same boundary.
 */
const NOT_ALLOWED_WORD = new RegExp(
  `(?<![\\p{L}\\p{N}_])(?:${NOT_ALLOWED_WORDS.join("|")})(?![\\p{L}\\p{N}_])`,
  "iu",
);

const encoder = new TextEncoder();

/**
 * The first line that is neither blank nor a `%%` comment is the type line.
 *
 * @param {string[]} lines
 * @returns {string | undefined}
 */
function typeLine(lines) {
  return lines
    .map((line) => line.trim())
    .find((line) => line !== "" && !line.startsWith("%%"));
}

/**
 * The accessible name of the diagram in `source`, or `null` when the type is not allowed.
 *
 * @param {string} source
 * @returns {string | null}
 */
export function diagramKind(source) {
  const line = typeLine(source.split("\n"));
  if (line === undefined) return null;
  const [word] = line.split(/\s+/u);
  if (word === undefined || !Object.hasOwn(KINDS, word)) return null;
  return KINDS[word] ?? null;
}

/**
 * True when `source` passes the browser's copy of the server rules: at most `maxSourceBytes` UTF-8
 * bytes, at most `maxLines` lines (a trailing newline is not a line), an allowed type, and no token from
 * NOT_ALLOWED_TOKENS and no word from NOT_ALLOWED_WORDS.
 *
 * @param {string} source
 * @returns {boolean}
 */
export function checkSource(source) {
  if (encoder.encode(source).byteLength > LIMITS.maxSourceBytes) return false;

  const lines = source.replace(/\n+$/u, "").split("\n");
  if (lines.length > LIMITS.maxLines) return false;
  if (diagramKind(source) === null) return false;
  if (NOT_ALLOWED_TOKENS.some((token) => source.includes(token))) return false;

  return !NOT_ALLOWED_WORD.test(source);
}
