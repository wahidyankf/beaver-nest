// Where the one action menu goes when it is a popover rather than a sheet.
//
// Tech-doc 003's Responsive Behaviour table: at and above 600px the menu is
// "a popover anchored to the message"; below that it is "a sheet from the
// bottom edge", which `app.css` already owns and this file leaves alone. The
// arithmetic lives here, apart from the DOM, because "beside the message and
// inside the viewport" is a decision with edges worth stating -- a menu that
// opens at the room's top-left corner is technically open and practically
// lost, which is how the gap was found.

/** The breathing room between the menu and the message, and the viewport. */
export const GAP = 8;

const MESSAGE_SELECTOR = '[data-role="family-chat-message"]';

/**
 * @param {number} value
 * @param {number} low
 * @param {number} high
 */
function clamp(value, low, high) {
  return Math.min(Math.max(value, low), Math.max(low, high));
}

/**
 * @typedef {{height: number, width: number}} Size
 * @typedef {{bottom: number, left: number, right: number, top: number}} Box
 */

/**
 * @param {{gap?: number, menu: Size, message: Box, ownMessage: boolean, viewport: Size}} input
 * @returns {{left: number, top: number}}
 */
export function menuPlacement({
  gap = GAP,
  menu,
  message,
  ownMessage,
  viewport,
}) {
  const below = message.bottom + gap;
  const above = message.top - gap - menu.height;
  // Below by default, above only when below would clip the menu and above
  // actually fits. When neither fits the clamp keeps every item on screen,
  // which matters more than staying beside the message.
  const unclamped =
    below + menu.height <= viewport.height || above < gap ? below : above;
  // An own message hangs off the sending edge, and so does the control that
  // opens this menu; aligning the same edge keeps the two together.
  const preferredLeft = ownMessage ? message.right - menu.width : message.left;

  return {
    left: clamp(preferredLeft, gap, viewport.width - menu.width - gap),
    top: clamp(unclamped, gap, viewport.height - menu.height - gap),
  };
}

/**
 * Publishes `menuPlacement`'s result for the stylesheet to consume.
 *
 * The values go out as custom properties rather than as inline `top`/`left`
 * because the two layouts have to be able to disagree. An inline longhand
 * outranks any stylesheet rule, so a menu opened at desktop width and then
 * carried below 600px -- a tablet rotating to portrait, with the menu still
 * open -- would hold its stale popover coordinates and never become the
 * sheet. As custom properties the base rule and the sheet rule compete
 * normally, and the media query wins whenever it applies.
 * @param {HTMLElement} host
 * @param {HTMLElement} list
 * @param {string} messageKey
 */
export function anchorMenu(host, list, messageKey) {
  const element = list.querySelector(
    `${MESSAGE_SELECTOR}[data-message-id="${CSS.escape(messageKey)}"]`,
  );
  if (!element) return;

  const message = element.getBoundingClientRect();
  const menu = host.getBoundingClientRect();
  const { left, top } = menuPlacement({
    menu: { height: menu.height, width: menu.width },
    message: {
      bottom: message.bottom,
      left: message.left,
      right: message.right,
      top: message.top,
    },
    ownMessage: element.classList.contains("family-chat-message--own"),
    viewport: {
      height: globalThis.innerHeight,
      width: globalThis.innerWidth,
    },
  });
  host.style.setProperty("--fc-menu-top", `${top}px`);
  host.style.setProperty("--fc-menu-left", `${left}px`);
}

/**
 * Re-runs the placement while the menu is open and the viewport changes, so
 * a rotation moves the popover with its message instead of leaving it where
 * the old layout put it. The open message is read back off the host, which
 * already carries it.
 * @param {HTMLElement} host
 * @param {HTMLElement} list
 */
export function bindReanchor(host, list) {
  globalThis.addEventListener?.("resize", () => {
    if (host.hidden) return;
    anchorMenu(host, list, host.dataset["messageId"] ?? "");
  });
}
