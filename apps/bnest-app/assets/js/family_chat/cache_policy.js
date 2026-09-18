// The caching-decision predicate for this plan's Family Chat test proof
// (`push.inspectCacheStorage`): only true static build assets are safe to
// cache. `priv/static/service-worker.js` is a separately deployed, unbundled
// classic worker script (registered without `{type: "module"}`), so it
// cannot `import` this ES module -- it keeps its own literal copy of this
// same one-line predicate (see its comment) rather than importing it.

/**
 * @param {string} pathname a request URL's pathname (e.g. `/assets/app.css`).
 * @returns {boolean} true only for static build assets safe to cache.
 */
export function shouldCachePathname(pathname) {
  return pathname.startsWith("/assets/") || pathname.startsWith("/images/");
}
