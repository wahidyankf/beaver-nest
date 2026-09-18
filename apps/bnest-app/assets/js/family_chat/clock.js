// Centralizes every wall-clock/randomness/timer source the Family Chat
// modules use (outbox backoff, reconnect catch-up timing, seeded fixtures),
// so tests can inject a deterministic clock instead of depending on real
// `Date.now`/`Math.random`/`setTimeout` (this plan's REFACTOR requirement).

/**
 * @typedef {object} Clock
 * @property {() => number} now
 * @property {() => number} random
 * @property {(fn: () => void, delayMs: number) => unknown} setTimer
 * @property {(handle: unknown) => void} clearTimer
 */

/** @returns {Clock} */
export function createSystemClock() {
  return {
    now: () => Date.now(),
    random: () => Math.random(),
    setTimer: (fn, delayMs) => setTimeout(fn, delayMs),
    // `setTimer` above returns whatever `setTimeout` returns for this lib
    // target (`number` in the DOM lib this tsconfig selects); `clearTimer`'s
    // own signature keeps that opaque as `unknown` so callers never depend
    // on the underlying handle's shape, so this single cast back to the
    // known real runtime type is the boundary where that opacity ends.
    clearTimer: (handle) => clearTimeout(/** @type {number} */ (handle)),
  };
}
