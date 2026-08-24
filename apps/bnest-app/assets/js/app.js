// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/bnest_app";
import topbar from "../vendor/topbar";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");

if (!csrfToken) {
  throw new Error("Missing CSRF token meta tag");
}

const chatStorageKey = "bnest.chat.v1";
const sifatAllahStorageKey = "bnest.sifat-allah.v1";

const storedChat = () => {
  try {
    return window.sessionStorage.getItem(chatStorageKey) ?? "";
  } catch {
    return "";
  }
};

/** @param {unknown} snapshot */
const persistChat = (snapshot) => {
  try {
    window.sessionStorage.setItem(chatStorageKey, JSON.stringify(snapshot));
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
};

const clearStoredChat = () => {
  try {
    window.sessionStorage.removeItem(chatStorageKey);
  } catch {
    // Clearing the server-side view must still succeed when storage is unavailable.
  }
};

const swipeThreshold = 56;

/** @typedef {{ pointerId: number, x: number, y: number }} SwipeStart */
/**
 * @typedef {{
 *   onPointerDown: (event: PointerEvent) => void,
 *   onPointerUp: (event: PointerEvent) => void,
 *   onPointerCancel: (event: PointerEvent) => void
 * }} SifatSwipeState
 */

/** @param {EventTarget | null} target */
const isInteractiveTarget = (target) =>
  target instanceof Element &&
  Boolean(target.closest("button, a, input, select, textarea, label"));

/** @param {Element} element @param {PointerEvent} event */
const releasePointerCapture = (element, event) => {
  if (element.hasPointerCapture(event.pointerId)) {
    element.releasePointerCapture(event.pointerId);
  }
};

/** @param {Element} element @param {PointerEvent} event */
const startSwipe = (element, event) => {
  if (!event.isPrimary || isInteractiveTarget(event.target)) return null;

  element.setPointerCapture(event.pointerId);
  return { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
};

/**
 * @param {{
 *   el: HTMLElement,
 *   pushEvent: (event: string, payload: {direction: "left" | "right"}) => void
 * }} hook
 * @param {SwipeStart | null} start
 * @param {PointerEvent} event
 */
const finishSwipe = (hook, start, event) => {
  if (!start || start.pointerId !== event.pointerId) return null;

  const distanceX = event.clientX - start.x;
  const distanceY = event.clientY - start.y;
  releasePointerCapture(hook.el, event);

  if (
    Math.abs(distanceX) < swipeThreshold ||
    Math.abs(distanceX) <= Math.abs(distanceY)
  ) {
    return null;
  }

  hook.pushEvent(hook.el.dataset["swipeEvent"] ?? "swipe-study", {
    direction: distanceX < 0 ? "left" : "right",
  });

  return null;
};

/** @type {import("phoenix_live_view").Hook<SifatSwipeState>} */
const SifatSwipe = {
  mounted() {
    /** @type {SwipeStart | null} */
    let start = null;

    /** @param {PointerEvent} event */
    this.onPointerDown = (event) => {
      start = startSwipe(this.el, event);
    };

    /** @param {PointerEvent} event */
    this.onPointerUp = (event) => {
      start = finishSwipe(this, start, event);
    };

    /** @param {PointerEvent} event */
    this.onPointerCancel = (event) => {
      start = null;
      releasePointerCapture(this.el, event);
    };

    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("pointercancel", this.onPointerCancel);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown);
    this.el.removeEventListener("pointerup", this.onPointerUp);
    this.el.removeEventListener("pointercancel", this.onPointerCancel);
  },
};

const storedSifatAllah = () => {
  try {
    return window.localStorage.getItem(sifatAllahStorageKey) ?? "";
  } catch {
    return "";
  }
};

/** @param {unknown} snapshot */
const persistSifatAllah = (snapshot) => {
  try {
    window.localStorage.setItem(sifatAllahStorageKey, JSON.stringify(snapshot));
  } catch {
    // The learning flow still works when browser storage is unavailable.
  }
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({
    _csrf_token: csrfToken,
    chat: storedChat(),
    sifat_allah: storedSifatAllah(),
  }),
  hooks: { ...colocatedHooks, SifatSwipe },
});

window.addEventListener("phx:persist-chat", (event) => {
  if (event instanceof CustomEvent) persistChat(event.detail);
});

window.addEventListener("phx:clear-chat-storage", () => {
  clearStoredChat();
});

window.addEventListener("phx:persist-sifat-allah", (event) => {
  if (event instanceof CustomEvent) persistSifatAllah(event.detail);
});

window.addEventListener("keydown", (event) => {
  const composer = event.target;

  if (
    event.key !== "Enter" ||
    !event.shiftKey ||
    event.isComposing ||
    !(composer instanceof HTMLTextAreaElement) ||
    composer.dataset["role"] !== "chat-composer"
  ) {
    return;
  }

  event.preventDefault();
  composer.form?.requestSubmit();
});

if ("serviceWorker" in navigator) {
  window.addEventListener(
    "load",
    () => {
      navigator.serviceWorker.register("/service-worker.js").catch(() => {
        // Installation remains available when a browser disables service workers.
      });
    },
    { once: true },
  );
}

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env["NODE_ENV"] === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      /** @type {string | null} */
      let keyDown = null;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
