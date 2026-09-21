// What the message composer does, independent of any DOM: validate a draft,
// hand it to the outbox, decide what a key press means, and -- the part this
// module exists for -- decide that keyboard focus never leaves the message
// input. `mount_browser.js` binds a real `<textarea>`, a real Send button,
// and real key events to these decisions; the FE_UNIT harness exercises the
// same decisions without a browser.
//
// Focus is a decision, not a side effect, which is why it lives here.
// `focusFollowsSendControl()` is the single source of truth for it: the
// browser binding reads it to decide whether to let the Send button take
// focus at all (it calls `preventDefault()` on the pointer-down that would
// otherwise blur the input, so a mobile on-screen keyboard is never
// dismissed mid-conversation), and the unit layer reads it to prove the
// decision itself. Refocusing the input *after* a send would already be too
// late on iOS and Android: a keyboard dismissed by a blur does not come back
// without a fresh user gesture.
//
// Split into small method-group factories purely to stay under this
// project's max-lines-per-function lint budget.

const MAX_BODY_LENGTH = 4_000;

export const EMPTY_DRAFT_REMEDIATION = "Write a message first.";
export const TOO_LONG_REMEDIATION = "Keep messages under 4,000 characters.";
export const QUEUE_REFUSED_REMEDIATION = "Couldn't queue this message.";

/** @typedef {"send" | "newline" | "ignore"} KeyIntent */

/**
 * @typedef {object} SubmitResult
 * @property {boolean} queued
 * @property {string | null} clientMessageId
 * @property {string | null} remediation
 */

/** @typedef {{body: string, focused: boolean}} DraftState */

/**
 * What a successful send hands the store so it can put the member's own
 * message on screen. `status` is left to the store, which reads it from the
 * outbox it shares with this composer.
 * @typedef {{
 *   clientMessageId: string,
 *   body: string,
 *   senderKind: string,
 *   senderDisplayName: string,
 * }} QueuedMessage
 */

/**
 * @param {DraftState} draftState
 * @param {{remediationMessage: string | null}} state
 */
function createDraftMethods(draftState, state) {
  return {
    draft() {
      return draftState.body;
    },

    remediation() {
      return state.remediationMessage;
    },

    /** @param {string} body */
    type(body) {
      draftState.body = body;
    },

    /** @param {string} [text] */
    appendLine(text = "") {
      draftState.body = `${draftState.body}\n${text}`;
    },
  };
}

/** @param {DraftState} draftState */
function createFocusMethods(draftState) {
  return {
    focused() {
      return draftState.focused;
    },

    /**
     * Activating the send control must never move focus off the message
     * input. See this module's header for why the answer is a constant the
     * browser binding consumes rather than a behaviour it reimplements.
     */
    focusFollowsSendControl() {
      return false;
    },

    focus() {
      draftState.focused = true;
    },

    blur() {
      draftState.focused = false;
    },

    /**
     * `Enter` sends; `Shift`+`Enter` continues the same message. Anything
     * else is the browser's own business.
     * @param {{key: string, shiftKey?: boolean}} event
     * @returns {KeyIntent}
     */
    keyIntent({ key, shiftKey = false }) {
      if (key !== "Enter") return "ignore";
      return shiftKey ? "newline" : "send";
    },
  };
}

/**
 * @param {DraftState} draftState
 * @param {{remediationMessage: string | null}} state
 * @param {{send: (body: string) => Promise<string | null>}} outbox
 * @param {(message: QueuedMessage) => void} onQueued
 */
function createSubmitMethod(draftState, state, outbox, onQueued) {
  /**
   * @param {string | null} message
   * @returns {SubmitResult}
   */
  function refuse(message) {
    state.remediationMessage = message;
    return { queued: false, clientMessageId: null, remediation: message };
  }

  return {
    /** @returns {Promise<SubmitResult>} */
    async submit() {
      state.remediationMessage = null;
      const body = draftState.body.trim();
      if (!body) return refuse(EMPTY_DRAFT_REMEDIATION);
      if (body.length > MAX_BODY_LENGTH) return refuse(TOO_LONG_REMEDIATION);

      // Cleared before the queue is awaited so the input is usable again
      // immediately; a refusal below puts the text back rather than losing
      // what the member wrote.
      draftState.body = "";
      draftState.focused = true;

      const clientMessageId = await outbox.send(body);
      if (clientMessageId === null) {
        draftState.body = body;
        // `onQueueFull` (see `family_chat.js`) may already have written a
        // more specific remediation into the shared state by now.
        return refuse(state.remediationMessage ?? QUEUE_REFUSED_REMEDIATION);
      }

      // The member's own message goes on screen from here rather than from
      // the browser mount, so every caller -- real DOM or not -- shows it in
      // the same place: at the end of the window, where sending scrolls to.
      onQueued({
        clientMessageId,
        body,
        senderKind: "user",
        senderDisplayName: "You",
      });

      return { queued: true, clientMessageId, remediation: null };
    },
  };
}

/**
 * @param {{
 *   outbox: {send: (body: string) => Promise<string | null>},
 *   state: {remediationMessage: string | null},
 *   focused?: boolean,
 *   onQueued?: (message: QueuedMessage) => void,
 * }} options
 */
export function createComposer({
  outbox,
  state,
  focused = false,
  onQueued = () => {},
}) {
  /** @type {DraftState} */
  const draftState = { body: "", focused };
  return {
    ...createDraftMethods(draftState, state),
    ...createFocusMethods(draftState),
    ...createSubmitMethod(draftState, state, outbox, onQueued),
  };
}
