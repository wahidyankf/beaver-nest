// The name a scrollable table or code block is given while it overflows its box, so a screen reader announces what it
// is. Both chat rooms use it: the Family Chat stop logic (ADR 003, Decision 6) and the Codex conversation (ADR 004).
//
// Only the name and role this module adds are removed again, so a name the author or a drawing gave is never lost.

/** What this module added to a region, so removing it never removes a name or role someone else gave. */
const added = new WeakMap();

/**
 * The name and role a scroll region is given. A diagram picture is named by its drawing, so it gets none here.
 * @param {Element} region
 * @returns {{ label: string, role?: string } | null}
 */
function nameOf(region) {
  if (region.localName === "table") return { label: "Table, scrollable" };
  if (region.localName === "pre")
    return { label: "Code, scrollable", role: "group" };
  return null;
}

/** @param {Element} region */
export function nameScrollRegion(region) {
  const wanted = nameOf(region);
  if (wanted === null) return;
  /** @type {{ label?: string, role?: string }} */
  const given = {};
  if (!region.hasAttribute("aria-label")) {
    region.setAttribute("aria-label", wanted.label);
    given.label = wanted.label;
  }
  if (wanted.role !== undefined && !region.hasAttribute("role")) {
    region.setAttribute("role", wanted.role);
    given.role = wanted.role;
  }
  if (given.label !== undefined || given.role !== undefined)
    added.set(region, given);
}

/** @param {Element} region */
export function unnameScrollRegion(region) {
  const given = added.get(region);
  if (given === undefined) return;
  if (
    given.label !== undefined &&
    region.getAttribute("aria-label") === given.label
  ) {
    region.removeAttribute("aria-label");
  }
  if (given.role !== undefined && region.getAttribute("role") === given.role) {
    region.removeAttribute("role");
  }
  added.delete(region);
}

/**
 * Whether a region is wider or taller than its box, so a reader has something to scroll to.
 * @param {Element} region
 */
export function overflows(region) {
  return region.scrollWidth > region.clientWidth;
}

/**
 * Names one region if it overflows its box, and removes a name this module added if it fits.
 * @param {Element} region
 */
export function syncScrollRegion(region) {
  if (overflows(region)) nameScrollRegion(region);
  else unnameScrollRegion(region);
}

/**
 * Names each overflowing table and code block under `root`, and removes a name this module added to one that fits.
 * @param {Element} root
 * @param {string} [selector] the regions to check
 */
export function syncScrollRegionNames(root, selector = "table, pre") {
  for (const region of root.querySelectorAll(selector))
    syncScrollRegion(region);
}
