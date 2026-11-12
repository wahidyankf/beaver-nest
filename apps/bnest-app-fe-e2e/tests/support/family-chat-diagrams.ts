import { type Page } from "@playwright/test";

// Support for family_chat.feature's "Diagrams in messages" rule, in Chromium at the served origin.
//
// The drawing is the real diagram engine (`/assets/js/diagrams/engine.js`) on the page the test origin serves; the
// layout, the 320 px fit and the picture's surface are measured here, not declared. Nothing leaves the origin: the
// request recorder keeps every URL a scenario's page asked for, and the hostile corpus must fire no canary.

/** The bodies the rule's Givens name by kind. The unit adapter (`family_chat_diagrams.steps.ts`) records the same strings. */
export function diagramBody(kind: string): string {
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

/** The diagram source of each mermaid fence in the typed Markdown, in document order. */
export function fenceSourcesOf(typed: string): string[] {
  return [...typed.matchAll(/```mermaid\n([\s\S]*?)\n```/gu)].map(
    (match) => match[1] ?? "",
  );
}

// The message the scenario's typed text belongs to, per page (a page is one scenario's).
const typedBodies = new WeakMap<Page, string>();

export function setTypedBody(page: Page, body: string): void {
  typedBodies.set(page, body);
}

export function typedBodyOf(page: Page): string {
  const body = typedBodies.get(page);
  if (body === undefined)
    throw new Error("no earlier step named the typed message");
  return body;
}

// Every URL a page requests, from the first step that touches it. Attached once per page.
const requested = new WeakMap<Page, string[]>();

export function recordRequests(page: Page): void {
  if (requested.has(page)) return;
  const urls: string[] = [];
  requested.set(page, urls);
  page.on("request", (request) => {
    urls.push(request.url());
  });
}

/** Requests the page made that leave its origin. `data:` images are part of the page and never leave it. */
export function requestsLeavingOrigin(page: Page): string[] {
  const origin = new URL(page.url()).origin;
  return (requested.get(page) ?? []).filter(
    (url) =>
      !url.startsWith("data:") &&
      !url.startsWith(`${origin}/`) &&
      url !== origin,
  );
}

/** The canary a hostile label fires if it runs (`window.bnestDiagramCanary=true`). */
export function canaryFired(page: Page): Promise<boolean> {
  return page.evaluate(
    () =>
      (window as unknown as Record<string, unknown>)["bnestDiagramCanary"] !==
      undefined,
  );
}
