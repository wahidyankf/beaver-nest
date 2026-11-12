// Reads the `bodyHtml` a Family Chat message carries (ADR 003, Decision 2) for the step definitions. Every
// predicate looks only at the HTML it is given, and an absent value (undefined) is false, so a response that
// lost the field fails the scenario instead of passing it. The image rules mirror
// `BnestApp.Test.FamilyChatBodyHtml` in the integration layer.

const WRAPPER_CLASS = "message-content markdown-body family-chat-message-body";
const WRAPPER_ROLE = "family-chat-message-body";

function attributeOf(tag: string, name: string): string | undefined {
  return new RegExp(`\\s${name}="([^"]*)"`, "u").exec(tag)?.[1];
}

function tagTargets(
  html: string,
  tag: string,
  attribute: string,
): (string | undefined)[] {
  return [...html.matchAll(new RegExp(`<${tag}\\b[^>]*>`, "gu"))].map(
    ([match]) => attributeOf(match ?? "", attribute),
  );
}

/**
 * True when the HTML is one `div` with the shared Family Chat classes and the body role. A valueless attribute such
 * as LiveView's root marker `phx-r` is allowed: the shared component emits it in every room, and it is inert here.
 */
export function isMessageBodyElement(html: string | undefined): boolean {
  if (html === undefined) return false;
  const match =
    /^<div((?:\s+[a-zA-Z][\w-]*(?:="[^"]*")?)*)\s*>.*<\/div>$/su.exec(html);
  if (!match) return false;
  const attributes = new Map<string, string | undefined>();
  for (const [, name, value] of (match[1] ?? "").matchAll(
    /([a-zA-Z][\w-]*)(?:="([^"]*)")?/gu,
  )) {
    if (name !== undefined) attributes.set(name, value);
  }
  return (
    attributes.get("class") === WRAPPER_CLASS &&
    attributes.get("data-role") === WRAPPER_ROLE
  );
}

/** True when the HTML contains the fragment. */
export function htmlContains(
  html: string | undefined,
  fragment: string,
): boolean {
  return html !== undefined && html.includes(fragment);
}

// The marked `mermaid` fence the browser draws (ADR 004, Decision 2): the `pre` with its one marker value.
const DIAGRAM_MARKER = '<pre data-bnest-diagram="mermaid"><code>';

/** True when the HTML marks a `mermaid` fence for drawing. */
export function marksDiagram(html: string | undefined): boolean {
  return html !== undefined && html.includes(DIAGRAM_MARKER);
}

/**
 * True when the HTML keeps a `mermaid` fence as an ordinary code block with the server's note: the code block is
 * `language-mermaid`, no marker is present, and the note reads `Diagram not drawn: <note>.`.
 */
export function keepsDiagramNote(
  html: string | undefined,
  note: string,
): boolean {
  return (
    html !== undefined &&
    html.includes('<pre><code class="language-mermaid">') &&
    !html.includes("data-bnest-diagram") &&
    html.includes(`<p><em>Diagram not drawn: ${note}.</em></p>`)
  );
}

/** True when the HTML is present and does not contain the fragment. */
export function htmlLacks(html: string | undefined, fragment: string): boolean {
  return html !== undefined && !html.includes(fragment);
}

/**
 * True when the HTML shows the image the way the Codex chat decides (ADR 003, Decision 1), for the decision the
 * feature names: `inline` (the only image is an `<img>` whose `src` is the address as written), `link only` (no
 * `<img>`, the only link goes to the address, and its text says the image is not shown), `withheld` (no `<img>`,
 * the note says the image is not shown, and the address appears nowhere), or `repository` (the only image is an
 * `<img>` whose `src` is the repository route for the path). An unknown decision throws.
 */
export function showsImage(
  html: string | undefined,
  decision: string,
  address: string,
): boolean {
  if (html === undefined) return false;
  const sources = tagTargets(html, "img", "src");
  const links = tagTargets(html, "a", "href");
  switch (decision) {
    case "inline":
      return sources.length === 1 && sources[0] === address;
    case "repository":
      return sources.length === 1 && sources[0] === `/chat/images/${address}`;
    case "link only":
      return (
        sources.length === 0 &&
        links.length === 1 &&
        links[0] === address &&
        html.includes("(image not shown)")
      );
    case "withheld":
      return (
        sources.length === 0 &&
        html.includes("[image not shown: ") &&
        !html.includes(address)
      );
    default:
      throw new Error(`unknown image decision: ${decision}`);
  }
}
