// ADR 004, Decision 2 (server rules 3 to 5) and Decision 3 (the browser's client copy). The browser
// checks the same rules again before it asks the engine to draw, so these tests fix the client's
// behaviour; the Elixir drift test fixes that it matches the server.

import { describe, expect, it } from "vitest";
import {
  KINDS,
  LIMITS,
  NOT_ALLOWED_TOKENS,
  NOT_ALLOWED_WORDS,
  checkSource,
  diagramKind,
} from "../../../js/diagrams/diagram_limits.js";

const FLOW = "flowchart TD\n  A --> B";

describe("limits", () => {
  it("sets the ADR 004 numbers, from one frozen object", () => {
    expect(LIMITS).toEqual({
      maxSourceBytes: 6000,
      maxLines: 200,
      maxEdges: 60,
      maxPerMessage: 4,
      maxPerPage: 30,
      renderTimeoutMs: 8000,
      engineStartTimeoutMs: 20000,
      maxSvgChars: 300000,
      cacheEntries: 24,
      engineRetryMs: 30000,
      prefetchMarginPx: 300,
    });
    expect(Object.isFrozen(LIMITS)).toBe(true);
  });
});

describe("diagram kinds", () => {
  it("accepts exactly the nine type words the server allows", () => {
    expect(Object.keys(KINDS).sort()).toEqual(
      [
        "flowchart",
        "graph",
        "sequenceDiagram",
        "classDiagram",
        "stateDiagram",
        "stateDiagram-v2",
        "erDiagram",
        "pie",
        "gantt",
      ].sort(),
    );
  });

  it.each([
    ["flowchart TD\n  A --> B", "Flowchart"],
    ["graph LR\n  A --> B", "Flowchart"],
    ["flowchart", "Flowchart"],
    ["sequenceDiagram\n  A->>B: hi", "Sequence diagram"],
    ["classDiagram\n  class A", "Class diagram"],
    ["stateDiagram\n  [*] --> A", "State diagram"],
    ["stateDiagram-v2\n  [*] --> A", "State diagram"],
    ["erDiagram\n  A ||--o{ B : has", "Entity-relationship diagram"],
    ['pie\n  "A" : 1', "Pie chart"],
    ["gantt\n  title Plan", "Gantt chart"],
  ])("names %j as %s", (source, label) => {
    expect(diagramKind(source)).toBe(label);
  });

  it("finds the type line after blank lines and %% comments", () => {
    expect(diagramKind("\n%% a note\n\n   flowchart TD\n  A --> B")).toBe(
      "Flowchart",
    );
  });

  it.each([
    "architecture-beta\n  group api(cloud)[API]",
    "flowchart-elk TD\n  A --> B",
    "flowchartTD\n  A --> B",
    "mindmap\n  root",
    "%% only a comment",
    "",
  ])("returns no name for the unsupported or empty source %j", (source) => {
    expect(diagramKind(source)).toBeNull();
  });
});

describe("checkSource size", () => {
  it("accepts the reference flowchart", () => {
    expect(checkSource(FLOW)).toBe(true);
  });

  it("refuses a source of more than 6000 bytes", () => {
    expect(checkSource(`flowchart TD\n${"A".repeat(6000)}`)).toBe(false);
  });

  it("counts UTF-8 bytes, not characters", () => {
    // 13 bytes of header plus 2994 two-byte characters is 6001 bytes but only 3007 characters.
    expect(checkSource(`flowchart TD\n${"é".repeat(2994)}`)).toBe(false);
    expect(checkSource(`flowchart TD\n${"é".repeat(2993)}`)).toBe(true);
  });

  it("accepts exactly 200 lines and refuses 201", () => {
    const lines = ["flowchart TD", ...Array<string>(199).fill("A --> B")];
    expect(checkSource(lines.join("\n"))).toBe(true);
    expect(checkSource([...lines, "C --> D"].join("\n"))).toBe(false);
  });

  it("does not count the trailing newline as a line", () => {
    const lines = ["flowchart TD", ...Array<string>(199).fill("A --> B")];
    expect(checkSource(`${lines.join("\n")}\n\n`)).toBe(true);
  });
});

describe("checkSource type and settings", () => {
  it("refuses an unsupported type", () => {
    expect(checkSource("architecture-beta\n  group api(cloud)[API]")).toBe(
      false,
    );
    expect(checkSource("flowchart-elk TD\n  A --> B")).toBe(false);
  });

  it("refuses front matter, which is not a type line", () => {
    expect(checkSource("---\ntitle: x\n---\nflowchart TD\n  A --> B")).toBe(
      false,
    );
  });

  it.each([
    "flowchart TD\n  %%{init: {'securityLevel': 'loose'}}%%\n  A --> B",
    "%%{init: {'theme': 'dark'}}%%\nflowchart TD\n  A --> B",
  ])("refuses a init directive anywhere in the source: %j", (source) => {
    expect(checkSource(source)).toBe(false);
  });

  it.each([
    "flowchart TD\n  A --> B\n  click A callback",
    "flowchart TD\n  A --> B\n    link A https://example.com",
    "flowchart TD\n  A --> B\n  links A",
    "flowchart TD\n  A --> B\n  callback A",
  ])("refuses a click, callback or link line: %j", (source) => {
    expect(checkSource(source)).toBe(false);
  });

  it("allows linkStyle, which styles and does not link", () => {
    expect(
      checkSource("flowchart TD\n  A --> B\n  linkStyle 0 stroke:red"),
    ).toBe(true);
  });

  // The keyword counts anywhere on a line, as a whole word: `A-->B; click A "url"` is a link too. The server's
  // gate (ChatMarkdown.not_allowed?/1) makes the same decision, and the drift test cannot see it, so both are tested.
  it.each([
    'flowchart TD\n  A-->B; click A "https://example.com"',
    'flowchart TD\n  A-->B;click A "u"',
    'flowchart TD\n  A --> B\n  A --> C; href A "https://example.com"',
    "flowchart TD\n  A --> B; call run()",
    "flowchart TD\n  A --> B; callback A",
    "flowchart TD\n  A --> B; link A u",
    "flowchart TD\n  A --> B; Click A u",
    "flowchart TD\n  A --> B; click A u",
    "flowchart TD\n  A --> B click A u",
    "flowchart TD\n  A --> B links A",
  ])(
    "refuses a link keyword that is a whole word anywhere on a line: %j",
    (source) => {
      expect(checkSource(source)).toBe(false);
    },
  );

  it.each(["flowchart TD\n  A --> clicker", "flowchart TD\n  hrefs --> B"])(
    "allows a longer word that only starts with a keyword: %j",
    (source) => {
      expect(checkSource(source)).toBe(true);
    },
  );

  // The lists the server's gate also uses (ChatMarkdown.diagram_limits/0); the Elixir drift test compares them.
  it("exports the words and tokens the server refuses", () => {
    expect([...NOT_ALLOWED_WORDS].sort()).toEqual(
      ["callback", "call", "click", "href", "link", "links"].sort(),
    );
    expect([...NOT_ALLOWED_TOKENS].sort()).toEqual(["%%{", "@{"].sort());
  });

  // Shape data (`A@{ ... }`) can make Mermaid fetch a picture (`img:`) while it draws, so the whole syntax is refused.
  it.each([
    'flowchart TD\n  A@{ shape: imageSquare, img: "https://images.example.test/x.png" } --> B',
    'flowchart TD\n  A@{ icon: "fa:user" } --> B',
    'flowchart TD\n  A@{ shape: rect, label: "Plain" } --> B',
  ])("refuses shape data, which can load a picture: %j", (source) => {
    expect(checkSource(source)).toBe(false);
  });

  it("allows an at sign that is not shape data", () => {
    expect(checkSource('flowchart TD\n  A["mail@example.test"] --> B')).toBe(
      true,
    );
  });

  it("refuses a keyword next to a hyphen, the conservative reading of a whole word", () => {
    expect(
      checkSource("flowchart TD\n  A --> B\n  %% a click-through note"),
    ).toBe(false);
  });
});
