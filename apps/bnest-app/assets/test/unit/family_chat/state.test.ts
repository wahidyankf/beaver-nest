// Plain Vitest unit coverage for `js/family_chat/store.js` (tech-doc 007's
// File Impact list: "state.test.ts"). `store.js` keeps only the *logical*
// history/scroll-anchor/live-region invariants that do not need a real
// browser layout engine (see its own file comment and the feature file's
// `@integration-exempt` tags on the scenarios it backs) -- real pixel
// scroll/focus behavior is `family_chat.js`'s `createRealStore`, proven at
// FE_E2E. This file exercises the public API `family_chat.steps.ts` drives
// indirectly, plus the branches it never reaches (an unscrolled remote
// arrival, and construction with no options at all).

import { describe, expect, it } from "vitest";
import { createStore } from "../../../js/family_chat/store.js";

describe("createStore", () => {
  it("has no preserved anchor and starts at the bottom by default", () => {
    const store = createStore();
    expect(store.scrollAnchorPreserved()).toBe(false);
    expect(store.isAtBottom()).toBe(true);
    expect(store.lastLiveRegionAnnouncement()).toBeNull();
    expect(store.newMessagesIndicatorLabel()).toBeNull();
  });

  it("preserves the reading anchor across an older-page load", async () => {
    const store = createStore({ scrolledToOlderMessage: true });
    expect(store.scrollAnchorPreserved()).toBe(true);

    await store.loadOlderPage();
    // The anchor (the message that was first on screen before the prepend)
    // is still present in the history after two older messages are added
    // ahead of it.
    expect(store.scrollAnchorPreserved()).toBe(true);
  });

  it("auto-follows a remote arrival while already at the bottom", async () => {
    const store = createStore();
    await store.receiveRemoteMessage();

    expect(store.isAtBottom()).toBe(true);
    expect(store.newMessagesIndicatorLabel()).toBeNull();
    // Auto-following the transcript is not the same as a screen-reader
    // announcement of a brand-new arrival while scrolled away; announcement
    // is exercised by the "scrolled away" case below, which is the one the
    // Gherkin scenario actually asserts on.
  });

  it("shows the new-messages indicator and announces without moving focus when scrolled away", async () => {
    const store = createStore({ focusInComposer: true });
    await store.receiveRemoteMessage({ scrolledAwayFromBottom: true });

    expect(store.isAtBottom()).toBe(false);
    expect(store.newMessagesIndicatorLabel()).toBe("New messages below");
    expect(store.lastLiveRegionAnnouncement()).toContain("New message:");
    expect(store.focusMovedFromComposer()).toBe(false);
  });
});
