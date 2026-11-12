// The one place server-rendered message HTML reaches the Family Chat page (ADR 003, Decision 2, browser rules 2-4).
//
// `bodyHtml` is parsed inside a `<template>`, whose content is inert: no script runs and no image loads while the
// markup is only parsed. The parsed root is adopted into the page only when it is exactly one `div.markdown-body`
// and holds no active element or event-handler attribute. Anything else falls back to the body as text, built with
// `textContent`, so a server bug cannot put markup on the page.

const RAW_BODY = new WeakMap();

const BODY_CLASS = "family-chat-message-body";
const BODY_ROLE = "family-chat-message-body";
const MARKDOWN_ROOT_CLASS = "markdown-body";

// Elements that run code, load a document, or restyle the whole page. The server's sanitizer already removes them;
// this is the browser's own refusal, not a second sanitizer.
const ACTIVE_ELEMENTS =
  "script, style, iframe, frame, frameset, object, embed, link, meta, base, form";

/**
 * The text paragraph for a body: the fallback, and the only form a pending or failed outbox row takes.
 * @param {string} body
 */
export function textBodyNode(body) {
  const paragraph = document.createElement("p");
  paragraph.className = BODY_CLASS;
  paragraph.dataset["role"] = BODY_ROLE;
  paragraph.dataset["bodyFormat"] = "text";
  paragraph.textContent = body;
  RAW_BODY.set(paragraph, body);
  return paragraph;
}

/**
 * The one root element of the parsed body. Whitespace text and comments are not content: in dev the server's
 * template engine wraps the markup in comments that name the component, so a comment must not count as a root.
 *
 * @param {DocumentFragment} fragment the parsed template content
 * @returns {Element | null} the one root element, or null for any other shape
 */
function singleMarkdownRoot(fragment) {
  const roots = [...fragment.childNodes].filter(
    (node) =>
      node.nodeType !== Node.COMMENT_NODE &&
      !(
        node.nodeType === Node.TEXT_NODE &&
        (node.textContent ?? "").trim() === ""
      ),
  );
  if (roots.length !== 1) return null;
  const [root] = roots;
  if (!(root instanceof Element)) return null;
  if (root.localName !== "div") return null;
  if (!root.classList.contains(MARKDOWN_ROOT_CLASS)) return null;
  return root;
}

/** @param {Element} root */
function isInert(root) {
  if (root.querySelector(ACTIVE_ELEMENTS)) return false;
  for (const element of [root, ...root.querySelectorAll("*")]) {
    for (const attribute of element.attributes) {
      if (attribute.name.startsWith("on")) return false;
      if (/^\s*javascript:/iu.test(attribute.value)) return false;
    }
  }
  return true;
}

/**
 * The body of a committed message: the server's Markdown element when it is well-formed, the text otherwise.
 * @param {{body: string, bodyHtml?: string | null | undefined}} message
 */
export function committedBodyNode(message) {
  const html = message.bodyHtml;
  if (typeof html !== "string" || html === "") {
    return textBodyNode(message.body);
  }
  const template = document.createElement("template");
  template.innerHTML = html;
  const root = singleMarkdownRoot(template.content);
  if (root === null || !isInert(root)) {
    return textBodyNode(message.body);
  }
  // Only now does the markup leave the inert template: the copy is the first point an image can load.
  const adopted = document.importNode(root, true);
  if (!(adopted instanceof HTMLElement)) return textBodyNode(message.body);
  adopted.classList.add(BODY_CLASS);
  adopted.dataset["role"] = BODY_ROLE;
  adopted.dataset["bodyFormat"] = "markdown";
  // Links, checkboxes, tables and code blocks inside a message would each be a Tab stop. The history keeps one tab
  // group (roving_focus.js): only the stop message raises its links, and a table or code block only while it overflows.
  for (const control of adopted.querySelectorAll(
    "a[href], input, table, pre",
  )) {
    if (control instanceof HTMLElement) control.tabIndex = -1;
  }
  RAW_BODY.set(adopted, message.body);
  return adopted;
}

/**
 * The typed source of a body element this module built, which copy and Reply use instead of the rendered text.
 * @param {Element} element
 * @returns {string | undefined}
 */
export function rawBodyOf(element) {
  return RAW_BODY.get(element);
}
