// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/scroll_region_names.js`: the name a scrollable table or code block is given while
// it overflows its box. Both chat rooms use it, so a screen reader announces the same names in each (ADR 003,
// Decision 6; ADR 004). happy-dom has no layout, so overflow is declared on the element the way a browser measures it.

import { describe, expect, it } from "vitest";
import {
  nameScrollRegion,
  syncScrollRegionNames,
  unnameScrollRegion,
} from "../../js/scroll_region_names.js";

/** Declares an element as overflowing its box, the way a browser measures a wide table or code block. */
function overflow(element: HTMLElement): void {
  Object.defineProperty(element, "scrollWidth", {
    configurable: true,
    value: 1000,
  });
  Object.defineProperty(element, "clientWidth", {
    configurable: true,
    value: 300,
  });
}

/** Declares an element as exactly its box: nothing to scroll. */
function fits(element: HTMLElement): void {
  Object.defineProperty(element, "scrollWidth", {
    configurable: true,
    value: 300,
  });
  Object.defineProperty(element, "clientWidth", {
    configurable: true,
    value: 300,
  });
}

function rendered(html: string): HTMLElement {
  const root = document.createElement("div");
  root.innerHTML = html;
  document.body.replaceChildren(root);
  return root;
}

describe("nameScrollRegion", () => {
  it("names a table Table, scrollable", () => {
    const table = rendered(
      "<table><tr><td>Rice</td></tr></table>",
    ).querySelector("table") as HTMLElement;
    nameScrollRegion(table);
    expect(table.getAttribute("aria-label")).toBe("Table, scrollable");
    expect(table.hasAttribute("role")).toBe(false);
  });

  it("names a code block Code, scrollable and gives it the group role", () => {
    const pre = rendered("<pre><code>rice</code></pre>").querySelector(
      "pre",
    ) as HTMLElement;
    nameScrollRegion(pre);
    expect(pre.getAttribute("aria-label")).toBe("Code, scrollable");
    expect(pre.getAttribute("role")).toBe("group");
  });

  it("keeps a name the author gave", () => {
    const table = rendered(
      '<table aria-label="Prices"><tr><td>Rice</td></tr></table>',
    ).querySelector("table") as HTMLElement;
    nameScrollRegion(table);
    expect(table.getAttribute("aria-label")).toBe("Prices");
  });
});

describe("unnameScrollRegion", () => {
  it("removes only the name this module added", () => {
    const pre = rendered(
      '<pre role="region" aria-label="Keep"><code>rice</code></pre>',
    ).querySelector("pre") as HTMLElement;
    nameScrollRegion(pre);
    unnameScrollRegion(pre);
    expect(pre.getAttribute("aria-label")).toBe("Keep");
    expect(pre.getAttribute("role")).toBe("region");
  });

  it("removes the name and role it added once the region fits", () => {
    const pre = rendered("<pre><code>rice</code></pre>").querySelector(
      "pre",
    ) as HTMLElement;
    nameScrollRegion(pre);
    unnameScrollRegion(pre);
    expect(pre.hasAttribute("aria-label")).toBe(false);
    expect(pre.hasAttribute("role")).toBe(false);
  });
});

describe("syncScrollRegionNames", () => {
  it("names each overflowing table and code block under the root and no other", () => {
    const root = rendered(
      "<table><tr><td>Wide</td></tr></table><pre><code>wide</code></pre><table><tr><td>Narrow</td></tr></table><p>Text</p>",
    );
    const [wide, wideCode, narrow] = [
      root.querySelector("table") as HTMLElement,
      root.querySelector("pre") as HTMLElement,
      root.querySelectorAll("table")[1] as HTMLElement,
    ];
    overflow(wide);
    overflow(wideCode);
    fits(narrow);
    syncScrollRegionNames(root);
    expect(wide.getAttribute("aria-label")).toBe("Table, scrollable");
    expect(wideCode.getAttribute("aria-label")).toBe("Code, scrollable");
    expect(narrow.hasAttribute("aria-label")).toBe(false);
  });

  it("removes a name when its region stops overflowing after a resize", () => {
    const root = rendered("<pre><code>wide</code></pre>");
    const pre = root.querySelector("pre") as HTMLElement;
    overflow(pre);
    syncScrollRegionNames(root);
    fits(pre);
    syncScrollRegionNames(root);
    expect(pre.hasAttribute("aria-label")).toBe(false);
  });
});
