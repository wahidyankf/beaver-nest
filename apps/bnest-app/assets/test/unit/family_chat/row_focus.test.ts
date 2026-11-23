// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/row_focus.js`: swapping or
// removing a rendered row keeps keyboard focus where it was.

import { describe, expect, it } from "vitest";
import {
  removeKeepingFocus,
  replaceKeepingFocus,
} from "../../../js/family_chat/row_focus.js";

function row(text: string): HTMLElement {
  const el = document.createElement("div");
  el.tabIndex = -1;
  el.textContent = text;
  document.body.append(el);
  return el;
}

describe("replaceKeepingFocus", () => {
  it("moves focus to the replacement when the old row held it", () => {
    const oldNode = row("old");
    const newNode = document.createElement("div");
    newNode.tabIndex = -1;
    oldNode.focus();
    replaceKeepingFocus(oldNode, newNode);
    expect(document.activeElement).toBe(newNode);
  });

  it("leaves focus alone when the old row did not hold it", () => {
    const oldNode = row("old");
    const newNode = document.createElement("div");
    replaceKeepingFocus(oldNode, newNode);
    expect(document.activeElement).not.toBe(newNode);
    expect(document.body.contains(newNode)).toBe(true);
  });
});

describe("removeKeepingFocus", () => {
  it("moves focus to the successor when the removed row held it", () => {
    const oldNode = row("old");
    const successor = row("next");
    oldNode.focus();
    removeKeepingFocus(oldNode, successor);
    expect(document.body.contains(oldNode)).toBe(false);
    expect(document.activeElement).toBe(successor);
  });

  it("leaves focus alone when the removed row did not hold it", () => {
    const oldNode = row("old");
    const successor = row("next");
    successor.focus();
    removeKeepingFocus(oldNode, successor);
    expect(document.body.contains(oldNode)).toBe(false);
    expect(document.activeElement).toBe(successor);
  });
});
