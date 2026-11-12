// Swapping or removing a rendered row without losing keyboard focus. Split out of `real_store.js` to stay under that
// file's max-lines lint budget.

/**
 * Swaps a rendered row for its replacement, keeping keyboard focus on it when the old row held focus.
 * @param {Element} oldNode
 * @param {Element} newNode
 */
export function replaceKeepingFocus(oldNode, newNode) {
  const focused = oldNode.contains(oldNode.ownerDocument.activeElement);
  oldNode.replaceWith(newNode);
  if (focused && newNode instanceof HTMLElement)
    newNode.focus({ preventScroll: true });
}

/**
 * Removes a rendered row that a row already on screen replaces, moving focus to that row when the removed one held it.
 * @param {Element} oldNode
 * @param {Element} successor
 */
export function removeKeepingFocus(oldNode, successor) {
  const focused = oldNode.contains(oldNode.ownerDocument.activeElement);
  oldNode.remove();
  if (focused && successor instanceof HTMLElement)
    successor.focus({ preventScroll: true });
}
