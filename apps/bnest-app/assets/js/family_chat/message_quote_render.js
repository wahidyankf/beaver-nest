// The quote card a reply carries, as one function.
//
// It lives in its own module, and every rendering path reaches it through
// `messageNode`, so a new window path cannot forget the quote: there is no
// second place that decides whether to render one.

/**
 * @typedef {object} MessageQuote
 * @property {string} id
 * @property {string} [senderKind]
 * @property {string} [senderDisplayName]
 * @property {string} bodyPreview already bounded by the server; the renderer
 *   never truncates, so the card and the composer strip cannot disagree.
 */

/**
 * The quote card a reply carries.
 *
 * A `button`, because activating it acts in place (scroll, highlight, move
 * the roving stop) rather than navigating. The accessible name carries the
 * relationship first, the content second, and the affordance last, so a
 * screen reader announces what this is before reading it -- no WAI-ARIA
 * pattern covers a quoted reply, so the wording is tech-doc 003's decision
 * rather than a citation.
 *
 * It never contains a quote of its own: this function takes no nesting
 * parameter, so flatness is structural rather than a rule to remember.
 * @param {MessageQuote} quote
 * @returns {HTMLButtonElement}
 */
export function quoteNode(quote) {
  const senderLabel =
    (quote.senderKind === "system" ? "System" : quote.senderDisplayName) ?? "";

  const button = document.createElement("button");
  button.type = "button";
  button.className = "family-chat-message-quote";
  button.dataset["role"] = "family-chat-message-quote";
  button.dataset["targetMessageId"] = quote.id;
  // Not a tab stop. The history's contract is that Tab enters it once and
  // leaves it once (tech-doc 004), and a quote card inside a bubble would
  // add one stop per reply -- which is how a real browser found this: Tab
  // from the roving stop landed inside a later reply's quote instead of
  // leaving the list. It stays a real `button` with a real accessible name,
  // so a screen reader still reaches and announces it; what it is not is a
  // second way for Tab to walk the conversation.
  button.tabIndex = -1;
  button.setAttribute(
    "aria-label",
    `Reply to ${senderLabel}: ${quote.bodyPreview}. Go to that message.`,
  );

  const sender = document.createElement("span");
  sender.className = "family-chat-message-quote-sender";
  sender.dataset["role"] = "family-chat-message-quote-sender";
  sender.textContent = senderLabel;

  const preview = document.createElement("span");
  preview.className = "family-chat-message-quote-preview";
  preview.dataset["role"] = "family-chat-message-quote-preview";
  // `textContent`, never `innerHTML`: this string is another member's text.
  preview.textContent = quote.bodyPreview;

  button.append(sender, preview);
  return button;
}
