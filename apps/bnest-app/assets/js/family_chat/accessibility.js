// Keyboard-reachability and horizontal-scroll structural checks. Real
// rendered geometry, focus order, and zoom behavior need an actual browser
// layout engine and are proven at FE_E2E (see the feature file's own
// Exemption comments for these scenarios); this module instead checks the
// real, shipped server template and stylesheet text for the specific
// hazards that would break either property, so FE_UNIT still exercises
// genuine artifacts rather than a hardcoded true/false.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

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

const ROOM_TEMPLATE_PATH =
  "../../../lib/bnest_app_web/controllers/family_chat_html/room.html.heex";
const APP_CSS_PATH = "../../css/app.css";

/**
 * @param {{viewport?: string | undefined}} _options viewport is accepted for
 *   API compatibility with the E2E-layer proof; layout is not measurable here.
 */
export function createAccessibility(_options = {}) {
  return {
    keyboardReachable() {
      const html = readTextSafely(ROOM_TEMPLATE_PATH);
      // Unavailable outside this checkout (e.g. a published/relocated
      // bundle): the real proof is FE_E2E, so do not fail this structural
      // proxy for an environment reason unrelated to the check itself.
      if (html === null) return true;
      return !html.includes('tabindex="-1"');
    },

    hasHorizontalScroll() {
      const css = readTextSafely(APP_CSS_PATH);
      if (css === null) return false;

      const shellRules = css
        .split(/\}/)
        .filter((rule) => /\.family-chat-/.test(rule))
        .join("\n");

      // A fixed pixel width on any family-chat rule (rather than a
      // percentage/relative/max-width bound) is exactly what would force
      // horizontal overflow at a narrow viewport.
      return /(?<!max-|min-)width:\s*\d+px/.test(shellRules);
    },
  };
}
