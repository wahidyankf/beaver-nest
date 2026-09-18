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
    clearTimer: (handle) => clearTimeout(handle),
  };
}
