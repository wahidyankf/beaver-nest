// The conversation drawer for phones (chat_live.ex, ADR 005): the rail below the desktop width hides behind the
// header's Chats toggle and opens as a left-side overlay. The open state is client-side, like the options panel: the
// server never reads it, and a LiveView patch must not lose it.
//
// Each control is a delegated listener on the document, so it keeps working after LiveView patches the page.

const OPEN_CLASS = "is-open";

// The desktop width where the rail is a sidebar again, matching the stylesheet's breakpoint.
const DRAWER_QUERY = "(min-width: 42rem)";

// Duck-typed element check: `instanceof Element` fails when the page belongs to another window (happy-dom tests).
/** @param {unknown} node @returns {node is HTMLElement} */
export function isElement(node) {
  if (node === null || typeof node !== "object") return false;
  /** @type {any} */
  const candidate = node;
  return typeof candidate.closest === "function";
}

/** @param {Document} document */
function drawerOf(document) {
  return document.querySelector("[data-role='conversation-rail']");
}

/** @param {Document} document */
function drawerToggleOf(document) {
  return document.querySelector("[data-role='conversations-toggle']");
}

/** @param {Document} document */
function drawerScrimOf(document) {
  return document.querySelector("[data-role='conversation-scrim']");
}

/** @param {Document} document */
function drawerCloseOf(document) {
  return document.querySelector("[data-role='conversation-close']");
}

/** @param {Document} document */
export function drawerIsOpen(document) {
  const drawer = drawerOf(document);
  return isElement(drawer) && drawer.classList.contains(OPEN_CLASS);
}

/**
 * Opens or closes the conversation drawer. Opening moves focus to the drawer's close button, so a keyboard user
 * lands inside the drawer; closing returns focus to the Chats toggle, unless `keepFocus` asks to leave focus alone
 * (the desktop-width auto-close: the rail stays visible as a sidebar there).
 * @param {Document} document
 * @param {boolean} open
 * @param {{ keepFocus?: boolean }} [options]
 */
export function setConversationDrawer(document, open, options = {}) {
  const drawer = drawerOf(document);
  const toggle = drawerToggleOf(document);
  const scrim = drawerScrimOf(document);
  if (!isElement(drawer)) return;
  drawer.classList.toggle(OPEN_CLASS, open);
  if (isElement(toggle)) toggle.setAttribute("aria-expanded", String(open));
  if (isElement(scrim)) scrim.classList.toggle(OPEN_CLASS, open);
  if (options.keepFocus) return;
  if (open) {
    const close = drawerCloseOf(document);
    const first = isElement(close)
      ? close
      : drawer.querySelector("[data-role='new-conversation']");
    if (isElement(first)) first.focus();
  } else if (isElement(toggle)) {
    toggle.focus();
  }
}

/**
 * A tap on the toggle flips the drawer. A tap on the scrim, the drawer's close button, or a conversation entry
 * closes it. Entries that stay in the drawer (rename, delete) are left alone.
 * @param {Document} document
 * @param {HTMLElement} target
 * @returns {boolean} true when the tap targeted the drawer
 */
export function handleDrawerClick(document, target) {
  if (target.closest("[data-role='conversations-toggle']")) {
    setConversationDrawer(document, !drawerIsOpen(document));
    return true;
  }
  if (!drawerIsOpen(document)) return false;
  if (
    target.closest("[data-role='conversation-scrim']") ||
    target.closest("[data-role='conversation-close']") ||
    target.closest("[data-role='select-conversation']") ||
    target.closest("[data-role='new-conversation']")
  ) {
    setConversationDrawer(document, false);
    return true;
  }
  return false;
}

/**
 * Escape closes the open drawer. Focus returns to the Chats toggle only when the visitor worked inside the drawer or
 * on its toggle; from anywhere else (the message box while the drawer stands open) the visitor's place stays where
 * it is.
 * @param {KeyboardEvent} event
 * @param {Document} document
 * @returns {boolean} true when the drawer consumed the key
 */
export function handleDrawerEscape(event, document) {
  if (event.key !== "Escape" || !drawerIsOpen(document)) return false;
  const target = event.target;
  if (!isElement(target)) return false;
  event.preventDefault();
  const drawer = drawerOf(document);
  const toggle = drawerToggleOf(document);
  const inDrawer =
    (isElement(drawer) && drawer.contains(target)) || target === toggle;
  setConversationDrawer(document, false, { keepFocus: !inDrawer });
  return true;
}

/**
 * LiveView `dom.onBeforeElUpdated` hook: carries the open drawer and its toggle's aria-expanded from the element
 * LiveView replaces to the new one, so a server patch (a rename, a new message) never closes the drawer. Returns
 * nothing, so the patch continues.
 * @param {Element} from
 * @param {Element} to
 */
export function keepConversationDrawerState(from, to) {
  if (!isElement(from) || !isElement(to)) return;
  const role = from.dataset["role"];
  if (role === "conversation-rail") {
    to.classList.toggle(OPEN_CLASS, from.classList.contains(OPEN_CLASS));
  } else if (role === "conversations-toggle") {
    const expanded = from.getAttribute("aria-expanded");
    if (expanded !== null) to.setAttribute("aria-expanded", expanded);
  } else if (role === "conversation-scrim") {
    to.classList.toggle(OPEN_CLASS, from.classList.contains(OPEN_CLASS));
  }
}

/**
 * Closes the drawer when the viewport reaches the desktop width, where the rail is a sidebar again. A document
 * without media queries (a test without one) installs nothing.
 * @param {Document} document
 */
export function installDrawerDesktopClose(document) {
  const view = document.defaultView;
  if (!view || typeof view.matchMedia !== "function") return;
  const query = view.matchMedia(DRAWER_QUERY);
  const closeOnDesktop = () => {
    if (query.matches)
      setConversationDrawer(document, false, { keepFocus: true });
  };
  if (typeof query.addEventListener === "function") {
    query.addEventListener("change", closeOnDesktop);
  } else if (typeof query.addListener === "function") {
    query.addListener(closeOnDesktop);
  }
}
