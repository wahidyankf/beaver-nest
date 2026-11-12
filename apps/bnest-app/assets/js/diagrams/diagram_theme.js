// ADR 004, Decision 5: Mermaid's colour code cannot read `var()` or `color-mix()`, so each site token is
// resolved to a plain colour (rgb()) before a draw. The resolved values form the theme signature, which
// is part of the cache key: a token change draws a new picture rather than reusing an old one.

/**
 * The Mermaid theme variable each diagram colour takes, and the site token it comes from. A key whose
 * token is not a colour (`fontFamily`) is resolved as a font.
 *
 * @type {Readonly<Record<string, string>>}
 */
export const THEME_TOKENS = Object.freeze({
  background: "--bnest-paper",
  edgeLabelBackground: "--bnest-paper",
  tertiaryColor: "--bnest-paper",
  primaryColor: "--bnest-canvas",
  mainBkg: "--bnest-canvas",
  clusterBkg: "--bnest-canvas",
  actorBkg: "--bnest-canvas",
  secondaryColor: "--bnest-sun-light",
  noteBkgColor: "--bnest-sun-light",
  primaryTextColor: "--bnest-ink",
  secondaryTextColor: "--bnest-ink",
  tertiaryTextColor: "--bnest-ink",
  textColor: "--bnest-ink",
  noteTextColor: "--bnest-ink",
  actorTextColor: "--bnest-ink",
  titleColor: "--bnest-ink",
  primaryBorderColor: "--bnest-ink-soft",
  lineColor: "--bnest-ink-soft",
  nodeBorder: "--bnest-ink-soft",
  clusterBorder: "--bnest-ink-soft",
  actorBorder: "--bnest-ink-soft",
  actorLineColor: "--bnest-ink-soft",
  signalColor: "--bnest-ink-soft",
  pie1: "--bnest-lagoon",
  pie2: "--bnest-sun-light",
  pie3: "--sifat-mustahil",
  pie4: "--sifat-wajib",
  pie5: "--bnest-canvas",
  pie6: "--bnest-paper",
  fontFamily: "--bnest-body",
});

/**
 * Resolves a token for one CSS property, to the value a browser reports (rgb() for a colour).
 *
 * @typedef {(token: string, property: "color" | "font-family") => string} TokenResolver
 */

/**
 * Reads a token through a hidden probe element, so the browser does the `var()` resolution. The probe
 * is removed before the value is returned.
 *
 * @param {Document} doc
 * @param {Window} win
 * @returns {TokenResolver}
 */
export function pageResolver(doc, win) {
  return (token, property) => {
    const probe = doc.createElement("span");
    probe.style.setProperty("position", "absolute");
    probe.style.setProperty("visibility", "hidden");
    probe.style.setProperty(property, `var(${token})`);
    doc.body.append(probe);
    try {
      return win.getComputedStyle(probe).getPropertyValue(property);
    } finally {
      probe.remove();
    }
  };
}

/**
 * The Mermaid theme for one draw. A token that resolves to nothing is left out (Mermaid then uses its
 * own default for that key) rather than sent as an empty colour.
 *
 * @param {TokenResolver} [resolve] reads a token; the default reads the live page
 * @returns {{ themeVariables: Record<string, string>, themeSignature: string }}
 */
export function readThemeVariables(resolve = pageResolver(document, window)) {
  /** @type {Record<string, string>} */
  const themeVariables = {};
  for (const [key, token] of Object.entries(THEME_TOKENS)) {
    const property = key === "fontFamily" ? "font-family" : "color";
    const value = resolve(token, property).trim();
    if (value !== "") themeVariables[key] = value;
  }

  const themeSignature = Object.entries(themeVariables)
    .map(([key, value]) => `${key}=${value}`)
    .join(";");

  return { themeVariables, themeSignature };
}
