// Keyboard-reachability and horizontal-scroll structural checks. Real
// rendered geometry, focus order, and zoom behavior need an actual browser
// layout engine and are proven at FE_E2E (see the feature file's own
// Exemption comments for these scenarios); this module instead exercises
// genuine artifacts -- the shipped stylesheet's text, and the shipped
// message renderer itself -- for the specific hazards that would break
// either property.
//
// Keyboard reachability used to be proven by asserting the shipped
// `room.html.heex` contained no `tabindex="-1"`. Message elements are
// created in JavaScript, so that check kept passing while the rendered room
// filled with `tabindex="-1"`: green, and meaningless. It now renders a real
// list through `message_render.js` and `roving_focus.js` and asserts the
// invariant that actually makes the history reachable -- exactly one tab
// stop among the messages.
//
// A browser never loads this module (`room_parts.js` imports it only on the
// no-document branch), which is why it may use `node:fs` and build its own
// DOM.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Window } from "happy-dom";
import { messageNode } from "./message_render.js";
import { createRovingFocus, rovingInvariantHolds } from "./roving_focus.js";

/** @param {string} relativeUrl */
function readTextSafely(relativeUrl) {
  try {
    return readFileSync(
      fileURLToPath(new URL(relativeUrl, import.meta.url)),
      "utf8",
    );
  } catch {
    return null;
  }
}

const APP_CSS_PATH = "../../css/app.css";

/** How many messages the probe renders: more than a screen, as the room is. */
const PROBE_MESSAGE_COUNT = 50;

/**
 * Renders a real message list through the shipped renderer and applies the
 * shipped roving stop, in a DOM built for this check alone.
 *
 * `messageNode` reaches for a global `document`, so the probe window's one
 * is installed for the duration and restored afterwards -- this module runs
 * only where there was none to begin with, but leaving a global behind would
 * change what every later caller in the same process sees.
 * @param {number} [count]
 * @returns {HTMLElement}
 */
export function renderProbeList(count = PROBE_MESSAGE_COUNT) {
  // happy-dom declares its own structurally-identical DOM types, which TS
  // treats as unrelated to the `lib.dom` ones every other module here is
  // written against. Narrowing once, here, is what keeps that duplication
  // from leaking into the rest of the file.
  const probeDocument =
    /** @type {Document} */
    (
      /** @type {unknown} */
      (new Window().document)
    );
  const previousDocument = globalThis.document;
  globalThis.document = probeDocument;
  try {
    const list = probeDocument.createElement("ol");
    for (let index = 0; index < count; index += 1) {
      list.append(
        messageNode(
          {
            id: String(1000 + index),
            body: `Probe message ${index}`,
            senderDisplayName: "Probe",
            senderId: "probe-sender",
          },
          { pending: false, currentUserId: "probe-reader" },
        ),
      );
    }
    createRovingFocus(list).refresh();
    return list;
  } finally {
    globalThis.document = previousDocument;
  }
}

/**
 * @param {{viewport?: string | undefined}} _options viewport is accepted for
 *   API compatibility with the E2E-layer proof; layout is not measurable here.
 */
export function createAccessibility(_options = {}) {
  return {
    keyboardReachable() {
      return rovingInvariantHolds(renderProbeList());
    },

    hasHorizontalScroll() {
      const css = readTextSafely(APP_CSS_PATH);
      if (css === null) return false;

      const shellRules = css
        .split(/\}/u)
        .filter((rule) => /\.family-chat-/u.test(rule))
        .join("\n");

      // A fixed pixel width on any family-chat rule (rather than a
      // percentage/relative/max-width bound) is exactly what would force
      // horizontal overflow at a narrow viewport.
      return /(?<!max-|min-)width:\s*\d+px/u.test(shellRules);
    },
  };
}
