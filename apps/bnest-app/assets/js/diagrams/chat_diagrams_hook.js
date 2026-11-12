// ADR 004, Decision 3 (lifecycle): the Codex conversation draws its diagrams when it mounts and stops
// watching when it is destroyed. One watcher serves the whole conversation, so a patch that adds or
// changes a reply needs no hook update.
//
// The same hook keeps the conversation on its newest content (scroll_follow.js) and names its overflowing tables and
// code blocks the way Family Chat does (scroll_region_names.js), so both rooms read the same to a screen reader.

import { observeDiagrams } from "./mermaid_diagrams.js";
import { createBottomFollower } from "../scroll_follow.js";
import { syncScrollRegionNames } from "../scroll_region_names.js";

/** The regions a Codex reply can hold that scroll sideways, the same ones Family Chat names. */
const SCROLL_REGIONS = ".markdown-body table, .markdown-body pre";

/**
 * What the conversation's hook holds while it is mounted.
 * @typedef {Object} ChatDiagramsState
 * @property {{ disconnect(): void } | null} watcher
 * @property {{ pin(): void, dispose(): void } | null} follower
 * @property {MutationObserver | null} names
 * @property {(() => void) | null} onResize
 * @property {(() => void) | null} onSubmit
 * @property {HTMLFormElement | null} form
 */

/**
 * Releases everything the hook started. Safe to call when nothing is running, so a second mount never leaves the
 * first watchers running.
 * @param {ChatDiagramsState} state
 */
function releaseWatchers(state) {
  state.watcher?.disconnect();
  state.watcher = null;
  state.follower?.dispose();
  state.follower = null;
  state.names?.disconnect();
  state.names = null;
  if (state.onResize) window.removeEventListener("resize", state.onResize);
  state.onResize = null;
  if (state.onSubmit)
    state.form?.removeEventListener("submit", state.onSubmit, true);
  state.onSubmit = null;
  state.form = null;
}

/** @type {import("phoenix_live_view").Hook<ChatDiagramsState>} */
export const ChatDiagrams = {
  mounted() {
    releaseWatchers(this);

    this.watcher = observeDiagrams(this.el, { focusable: true });
    this.follower = createBottomFollower(this.el);

    // A LiveView patch of the reply can reset the name the browser added to a table or code block: the server does not
    // render it, so the patch removes it with no child change. Attribute changes are therefore watched too.
    const name = () => syncScrollRegionNames(this.el, SCROLL_REGIONS);
    this.names = new MutationObserver(name);
    this.names.observe(this.el, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-label", "role"],
    });
    this.onResize = name;
    window.addEventListener("resize", name);
    name();

    // The reader's own message goes to the bottom even when they had scrolled up to reread the reply.
    const composer = document.querySelector("form#chat-composer-form");
    this.form = composer instanceof HTMLFormElement ? composer : null;
    const follower = this.follower;
    this.onSubmit = () => follower?.pin();
    this.form?.addEventListener("submit", this.onSubmit, true);
  },

  destroyed() {
    releaseWatchers(this);
  },
};
