// Plain Vitest unit coverage for `js/family_chat/accessibility.js`, the
// FE_UNIT-layer structural proxy behind the room's keyboard-reachability
// and horizontal-scroll scenarios.
//
// Runs in the default (node) environment on purpose: `accessibility.js` is a
// Node-only prover -- it reads the shipped template and stylesheet from
// disk, and builds its own DOM to render into. A browser never loads it (see
// `room_parts.js`), so the environment it is proven in is the environment it
// runs in.
//
// What this file is for is the sensitivity of the check itself. A structural
// proxy that cannot fail is worse than no proxy, because it reports safety
// it never looked for.

import { describe, expect, it } from "vitest";
import {
  createAccessibility,
  renderProbeList,
} from "../../../js/family_chat/accessibility.js";

describe("createAccessibility", () => {
  it("reports the room keyboard-reachable for the shipped renderer", () => {
    expect(createAccessibility().keyboardReachable()).toBe(true);
  });

  it("reports no horizontal scroll for the shipped stylesheet", () => {
    expect(createAccessibility().hasHorizontalScroll()).toBe(false);
  });
});

describe("renderProbeList", () => {
  it("renders through the real message renderer, not a stand-in", () => {
    const list = renderProbeList(4);
    const items = list.querySelectorAll('[data-role="family-chat-message"]');

    expect(items).toHaveLength(4);
    // The bubble, the body handle, and the actions control are the shipped
    // renderer's own output; a hand-built probe would not carry them.
    expect(
      list.querySelectorAll('[data-role="family-chat-message-body"]'),
    ).toHaveLength(4);
    expect(
      list.querySelectorAll('[data-role="family-chat-message-more"]'),
    ).toHaveLength(4);
  });

  it("carries the roving invariant the check is looking for", () => {
    const list = renderProbeList(4);
    const stops = [
      ...list.querySelectorAll('[data-role="family-chat-message"]'),
    ].filter((item) => (item as HTMLElement).tabIndex === 0);

    expect(stops).toHaveLength(1);
  });
});
