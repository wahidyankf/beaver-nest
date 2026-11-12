// ADR 004, Decision 3: where the engine runs. Mermaid draws by changing the DOM and measuring it hundreds of times,
// and each measurement makes the browser match the page's `:has()` rules again over every element below the root.
// In the page that cost grows with the size of the drawing: 60 edges took about 6 s. A hidden same-origin frame
// has no style sheet, so the same draw takes a fraction of that, and it no longer depends on the page's CSS.

import { LIMITS } from "./diagram_limits.js";

const FRAME_STYLE =
  "position:fixed;top:0;left:-99999px;width:1280px;height:960px;border:0;visibility:hidden;pointer-events:none";

/**
 * What a script in the frame calls to say it has the engine (`resolve`) or cannot have it (`reject`). The frame
 * element carries it under this name; engine.js reads it through `frameElement`.
 */
export const HOST_PROPERTY = "bnestEngineHost";

/**
 * The frame's own Content-Security-Policy. It refuses every request except the engine's script from this origin,
 * the styles a draw writes, and data pictures, so a diagram cannot make the browser fetch an outside picture,
 * stylesheet or font. The page's policy does not reach the frame, so the frame carries its own. The server's
 * gate refuses the diagram syntax that could ask for a picture; this policy holds even if that gate is passed.
 */
export const FRAME_POLICY =
  "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src data:";

/** The frame each started engine runs in, by the engine it handed over (see removeEngineFrame). @type {WeakMap<object, HTMLIFrameElement>} */
const frames = new WeakMap();

/**
 * The hidden, inert frame in standards mode (a document with a doctype, like the page), not yet in the body. The
 * policy is its first markup, so it applies before the engine's script is added.
 *
 * @param {Document} doc
 * @returns {HTMLIFrameElement}
 */
function hiddenFrame(doc) {
  const frame = doc.createElement("iframe");
  frame.setAttribute("aria-hidden", "true");
  frame.setAttribute("tabindex", "-1");
  frame.setAttribute("style", FRAME_STYLE);
  frame.inert = true;
  frame.srcdoc = `<!doctype html><meta http-equiv="Content-Security-Policy" content="${FRAME_POLICY}">`;
  return frame;
}

/**
 * Loads a module as a script in a hidden same-origin frame and resolves to the API that module hands to its host.
 * The API must pass `accept`; any other hand-over is a failure. The frame stays in the body while its load succeeds,
 * and it is removed when the load fails, so the caller can start again with a new frame.
 *
 * @param {Document} doc
 * @param {string} address the module's address
 * @param {{ setTimer: (callback: () => void, ms: number) => number, clearTimer: (handle: number) => void }} timers
 * @param {(api: unknown) => boolean} accept whether a value handed over is the API the caller needs
 * @returns {Promise<unknown>}
 */
export function loadEngineInFrame(doc, address, timers, accept) {
  return new Promise((resolve, reject) => {
    const frame = hiddenFrame(doc);

    /** @param {unknown} error */
    const fail = (error) => {
      timers.clearTimer(timer);
      frame.remove();
      reject(error);
    };
    // The start covers the chunk fetches of a first load (about 1.4 MB on a slow phone), so it has its own limit.
    const timer = timers.setTimer(
      () => fail(new Error("the diagram engine did not start")),
      LIMITS.engineStartTimeoutMs,
    );
    /** @param {unknown} api */
    const ready = (api) => {
      if (!accept(api)) {
        fail(new Error("the diagram frame gave no engine"));
        return;
      }
      timers.clearTimer(timer);
      if (typeof api === "object" && api !== null) frames.set(api, frame);
      resolve(api);
    };
    Object.defineProperty(frame, HOST_PROPERTY, {
      value: { resolve: ready, reject: fail },
    });
    frame.addEventListener(
      "load",
      () => {
        const frameDoc = frame.contentDocument;
        if (frameDoc === null) {
          fail(new Error("the diagram frame has no document"));
          return;
        }
        const script = frameDoc.createElement("script");
        script.type = "module";
        script.src = new URL(address, doc.baseURI).href;
        script.addEventListener("error", () =>
          fail(new Error("the diagram engine did not load")),
        );
        frameDoc.head.append(script);
      },
      { once: true },
    );
    doc.body.append(frame);
  });
}

/**
 * Removes the frame a started engine runs in, so the engine and any draw still pending in it are gone. The next start
 * makes a new frame. A value no start handed over is ignored.
 *
 * @param {unknown} engine
 */
export function removeEngineFrame(engine) {
  if (typeof engine !== "object" || engine === null) return;
  frames.get(engine)?.remove();
  frames.delete(engine);
}
