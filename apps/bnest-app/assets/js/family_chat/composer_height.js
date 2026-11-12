// The Family Chat composer grows with its draft and stops at six lines, then scrolls (FC-04). The stylesheet
// (`.family-chat-message-input` in app.css) declares the same six-line cap, so this module only
// writes the height the content needs, up to that cap. Without a cap the textarea grows with every line.

/**
 * The height a composer needs for its content, and whether the content scrolls past the cap.
 * @param {{scrollHeight: number, borderPx: number, capPx: number}} measure
 *   `scrollHeight` is the content and padding; `borderPx` is the textarea's own border; `capPx` is the most it may be.
 * @returns {{heightPx: number, scrolls: boolean}}
 */
export function composerHeightFor({ scrollHeight, borderPx, capPx }) {
  const wanted = scrollHeight + borderPx;
  return { heightPx: Math.min(wanted, capPx), scrolls: wanted > capPx };
}

/**
 * A CSS length in pixels, for the units the composer's cap is written in: `px`, `rem`, `min()` and `max()` of those,
 * and the window-height units `vh`, `svh` and `dvh` (resolved against `viewportHeightPx`). Any other value is NaN, so
 * the caller applies no cap rather than a wrong one.
 * @param {string} value
 * @param {number} [viewportHeightPx] the window's height in CSS pixels, for the viewport-height units
 * @returns {number}
 */
export function lengthToPx(value, viewportHeightPx = Number.NaN) {
  const trimmed = value.trim();
  const fn = /^(min|max)\((.*)\)$/u.exec(trimmed);
  if (fn) {
    const parts = (fn[2] ?? "")
      .split(",")
      .map((part) => lengthToPx(part, viewportHeightPx));
    if (parts.some((part) => Number.isNaN(part))) return Number.NaN;
    return fn[1] === "min" ? Math.min(...parts) : Math.max(...parts);
  }
  const match = /^(-?\d*\.?\d+)(px|rem|vh|svh|dvh)$/u.exec(trimmed);
  if (!match) return Number.NaN;
  const amount = Number(match[1]);
  if (match[2] === "rem") return amount * 16;
  if (match[2] === "px") return amount;
  return (amount / 100) * viewportHeightPx;
}

/**
 * Sets a real composer textarea to the height its draft needs. The height is reset to `auto` first, so the
 * textarea can shrink again after a send clears the draft.
 * @param {HTMLElement} textarea
 */
export function fitComposerInput(textarea) {
  textarea.style.height = "auto";
  const borderPx = textarea.offsetHeight - textarea.clientHeight;
  const cap = lengthToPx(
    getComputedStyle(textarea).maxHeight,
    window.innerHeight,
  );
  const { heightPx, scrolls } = composerHeightFor({
    scrollHeight: textarea.scrollHeight,
    borderPx,
    capPx: Number.isNaN(cap) ? Number.POSITIVE_INFINITY : cap,
  });
  textarea.style.height = `${heightPx}px`;
  textarea.style.overflowY = scrolls ? "auto" : "hidden";
}
