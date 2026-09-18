// Pure retry/backoff formula (tech-doc 003): base delays double each attempt
// through 32s, then hold at a 60s ceiling; every delay is jittered by a
// uniform factor in [0.8, 1.2] and never exceeds 60s. Kept as one pure
// function (no clock/timer access) so the outbox's real scheduling and the
// FE_UNIT test hooks (`failRepeatedly`, `queueWithPendingBackoff`) share the
// exact same formula instead of two copies drifting apart.

const BASE_DELAYS_MS = [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000];
const MAX_DELAY_MS = 60_000;
const JITTER_MIN = 0.8;
const JITTER_RANGE = 0.4;

/**
 * @param {number} attemptNumber 1-based attempt count (1 = first retry).
 * @param {() => number} random uniform [0, 1) source, defaults to `Math.random`.
 * @returns {number} delay in milliseconds, always <= 60000.
 */
export function computeBackoffDelayMs(attemptNumber, random = Math.random) {
  const index = Math.min(
    Math.max(attemptNumber, 1) - 1,
    BASE_DELAYS_MS.length - 1,
  );
  const base = BASE_DELAYS_MS[index];
  const jitterFactor = JITTER_MIN + random() * JITTER_RANGE;
  return Math.min(base * jitterFactor, MAX_DELAY_MS);
}
