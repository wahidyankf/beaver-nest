// The Codex message box's LiveView hook (ADR 005, decision 1). When the visitor sends, the box holds the sent text until
// the server's patch clears it. A visitor who keeps typing in the moments before that patch must not lose that text: the
// hook puts back only the text typed after the send, and only when the patch has cleared the box.

/**
 * What the hook holds while the box is mounted.
 * @typedef {Object} ComposerState
 * @property {string | null} sent the box's text when the visitor sent it, until the server's clear is seen
 * @property {string | null} before the box's text just before a LiveView patch
 * @property {string | null} kept the text typed after the send, to put back if the patch clears the box
 * @property {HTMLFormElement | null} form the form whose submit starts a send
 * @property {(() => void) | null} onSubmit the listener on that form
 */

/**
 * The text typed after a send: what the box holds beyond the sent text. A box that no longer starts with the sent text
 * was edited some other way, so the whole box is kept.
 * @param {string} value
 * @param {string} sent
 * @returns {string}
 */
export function typedAfterSend(value, sent) {
  return value.startsWith(sent) ? value.slice(sent.length) : value;
}

/**
 * The hook is mounted on the Codex message box, which is always a textarea (chat_live.ex).
 * @param {any} el
 * @returns {HTMLTextAreaElement}
 */
function boxOf(el) {
  return el;
}

/** @type {import("phoenix_live_view").Hook<ComposerState>} */
export const ChatComposer = {
  mounted() {
    this.sent = null;
    this.before = null;
    this.kept = null;
    this.form = this.el.closest("form");
    // The submit is seen before LiveView reads the box, so the text recorded here is the text that was sent.
    this.onSubmit = () => {
      this.sent = boxOf(this.el).value;
      this.kept = null;
    };
    this.form?.addEventListener("submit", this.onSubmit);
  },

  beforeUpdate() {
    this.before = boxOf(this.el).value;
    this.kept =
      this.sent === null
        ? null
        : typedAfterSend(boxOf(this.el).value, this.sent);
  },

  updated() {
    // The server's clear empties a box that held text. Put back what was typed after the send, then forget the send,
    // so a later patch never overwrites text the visitor types afterwards.
    const cleared = boxOf(this.el).value === "" && this.before !== "";
    if (this.sent !== null && cleared) {
      boxOf(this.el).value = this.kept ?? "";
      this.sent = null;
    }
  },

  destroyed() {
    if (this.onSubmit) this.form?.removeEventListener("submit", this.onSubmit);
    this.onSubmit = null;
    this.form = null;
  },
};
