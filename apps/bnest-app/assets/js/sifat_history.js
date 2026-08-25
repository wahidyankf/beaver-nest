const sifatHistoryStateKey = "bnestSifatMode";

/** @param {"mission" | "active"} mode */
const sifatHistoryState = (mode) => ({
  ...(window.history.state && typeof window.history.state === "object"
    ? window.history.state
    : {}),
  [sifatHistoryStateKey]: mode,
});

/**
 * @typedef {{
 *   onHistoryEntry: () => void,
 *   onHistoryBack: () => void,
 *   onPopState: (event: PopStateEvent) => void
 * }} SifatHistoryState
 */

/** @type {import("phoenix_live_view").Hook<SifatHistoryState>} */
export const SifatHistory = {
  mounted() {
    if (!window.history.state?.[sifatHistoryStateKey]) {
      window.history.replaceState(
        sifatHistoryState("mission"),
        "",
        window.location.href,
      );
    }

    this.onHistoryEntry = () => {
      window.history.pushState(
        sifatHistoryState("active"),
        "",
        window.location.href,
      );
    };

    this.onHistoryBack = () => {
      if (window.history.state?.[sifatHistoryStateKey] === "active") {
        window.history.back();
      } else {
        this.pushEvent("dashboard", {});
      }
    };

    /** @param {PopStateEvent} event */
    this.onPopState = (event) => {
      if (event.state?.[sifatHistoryStateKey] === "mission") {
        this.pushEvent("dashboard", {});
      }
    };

    window.addEventListener("phx:sifat-history-entry", this.onHistoryEntry);
    window.addEventListener("phx:sifat-history-back", this.onHistoryBack);
    window.addEventListener("popstate", this.onPopState);
  },

  destroyed() {
    window.removeEventListener("phx:sifat-history-entry", this.onHistoryEntry);
    window.removeEventListener("phx:sifat-history-back", this.onHistoryBack);
    window.removeEventListener("popstate", this.onPopState);
  },
};
