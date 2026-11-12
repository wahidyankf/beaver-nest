// Keeps a message that keyboard focus moved to inside the history's window. The roving move focuses the message with
// `preventScroll`, so the browser does not scroll it into view; this scrolls the history the least it can instead.
// A message above or below the window is brought to its near edge. A message taller than the window is aligned to
// its top edge, so its first lines show. Only the history's own scroll position changes, so a reader who is reading
// older messages is not moved to the newest one.

/**
 * @param {HTMLElement} item the message that now holds keyboard focus
 * @param {HTMLElement} scroller the element that scrolls the message list
 */
export function revealInHistory(item, scroller) {
  const frame = scroller.getBoundingClientRect();
  const row = item.getBoundingClientRect();
  let delta = 0;
  if (row.height > frame.height || row.top < frame.top) {
    delta = row.top - frame.top;
  } else if (row.bottom > frame.bottom) {
    delta = row.bottom - frame.bottom;
  }
  if (delta !== 0) scroller.scrollTop += delta;
}
