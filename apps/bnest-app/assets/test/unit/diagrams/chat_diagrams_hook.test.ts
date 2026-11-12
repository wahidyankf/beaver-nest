// @vitest-environment happy-dom
// ADR 004, Decision 3 (lifecycle): the Codex conversation starts watching on mount and stops on destroy,
// with the focusable option the Codex chat needs. app.js must register the hook under its name.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";

const observeDiagrams = vi.hoisted(() => vi.fn());

vi.mock("../../../js/diagrams/mermaid_diagrams.js", () => ({
  observeDiagrams,
}));

import { ChatDiagrams } from "../../../js/diagrams/chat_diagrams_hook.js";

interface HookUnderTest {
  el: HTMLElement;
  mounted(): void;
  destroyed(): void;
}

describe("ChatDiagrams hook", () => {
  it("starts watching the conversation on mount, with focusable true", () => {
    observeDiagrams.mockReset().mockReturnValue({ disconnect: vi.fn() });
    const el = document.createElement("div");
    const hook = { el, ...ChatDiagrams } as unknown as HookUnderTest;

    hook.mounted();

    expect(observeDiagrams).toHaveBeenCalledTimes(1);
    expect(observeDiagrams).toHaveBeenCalledWith(el, { focusable: true });
  });

  it("stops watching when the element is destroyed", () => {
    const disconnect = vi.fn();
    observeDiagrams.mockReset().mockReturnValue({ disconnect });
    const hook = {
      el: document.createElement("div"),
      ...ChatDiagrams,
    } as unknown as HookUnderTest;

    hook.mounted();
    hook.destroyed();

    expect(disconnect).toHaveBeenCalledTimes(1);
  });

  it("does nothing on destroy when it never mounted", () => {
    const hook = {
      el: document.createElement("div"),
      ...ChatDiagrams,
    } as unknown as HookUnderTest;

    expect(() => hook.destroyed()).not.toThrow();
  });
});

describe("ChatDiagrams hook, scroll region names", () => {
  it("names a table again when a patch removes the name the browser added", async () => {
    observeDiagrams.mockReset().mockReturnValue({ disconnect: vi.fn() });
    const el = document.createElement("div");
    el.innerHTML = '<div class="markdown-body"><table></table></div>';
    const table = el.querySelector("table") as HTMLTableElement;
    // happy-dom has no layout: the table is made to overflow, as a wide table does in a bubble.
    Object.defineProperty(table, "scrollWidth", {
      configurable: true,
      value: 500,
    });
    Object.defineProperty(table, "clientWidth", {
      configurable: true,
      value: 200,
    });
    const hook = { el, ...ChatDiagrams } as unknown as HookUnderTest;

    hook.mounted();
    expect(table.getAttribute("aria-label")).toBe("Table, scrollable");

    // A LiveView patch of the reply resets attributes the server does not render, with no child change.
    table.removeAttribute("aria-label");
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(table.getAttribute("aria-label")).toBe("Table, scrollable");
    hook.destroyed();
  });
});

describe("app.js registration", () => {
  const appJs = readFileSync(
    resolve(import.meta.dirname, "../../../js/app.js"),
    "utf8",
  );

  it("imports the hook from the diagrams module", () => {
    expect(appJs).toMatch(
      /import\s*\{\s*ChatDiagrams\s*\}\s*from\s*["']\.\/diagrams\/chat_diagrams_hook\.js["']/u,
    );
  });

  it("registers the hook under the name the markup uses", () => {
    expect(appJs).toMatch(/hooks:\s*\{[^}]*\bChatDiagrams\b[^}]*\}/u);
  });
});
