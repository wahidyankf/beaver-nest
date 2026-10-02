// The composer's reply strip half of `mount_browser.js`, split from
// `mount_browser_actions.js` purely to stay under this project's max-lines
// lint budget. `mount_browser.js` is the only importer.

/** @typedef {import("./mount_browser.js").MountableRoom} MountableRoom */
/** @typedef {import("./elements.js").FamilyChatElements} FamilyChatElements */

/**
 * The strip is driven entirely by the reply target's own change
 * notifications, so there is no second place that decides whether it is
 * showing -- selecting, cancelling, sending, and a refused send all reach it
 * through the same one channel.
 * @param {MountableRoom} room
 * @param {FamilyChatElements} elements
 */
export function wireReplyStrip(room, elements) {
  const replyTarget = room.replyTarget;
  if (!replyTarget) return;

  replyTarget.onChange((selection) => {
    elements.replyStrip.hidden = selection === null;
    elements.replyStripName.textContent = selection
      ? `Replying to ${selection.senderDisplayName}`
      : "";
    elements.replyStripPreview.textContent = selection?.bodyPreview ?? "";
  });

  elements.replyStripCancel.addEventListener("click", () => {
    replyTarget.clear();
    elements.input.focus({ preventScroll: true });
  });

  elements.input.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || !replyTarget.isSet()) return;
    // Only when there is a target to cancel: Escape in a textarea otherwise
    // belongs to whatever the browser or the member expects it to do.
    event.preventDefault();
    replyTarget.clear();
  });
}
