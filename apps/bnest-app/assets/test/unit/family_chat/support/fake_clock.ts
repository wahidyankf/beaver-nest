// A deterministic stand-in for `family_chat/clock.js`'s `Clock` shape, used
// only by this directory's plain Vitest specs (the Gherkin-driven
// `test/behaviour/*` harness has its own scenario-scoped clock needs and
// does not use this file). `advance` fires every timer due at or before the
// requested offset, in the order they become due, so a callback that
// schedules a further timer (e.g. `outbox.js`'s retry chain) is itself
// re-evaluated within the same `advance` call -- matching how a real
// `setTimeout` chain would resolve across that much wall-clock time.

export interface FakeClock {
  now: () => number;
  random: () => number;
  setTimer: (fn: () => void, delayMs: number) => number;
  // Kept `unknown`, matching `family_chat/clock.js`'s real `Clock.clearTimer`
  // signature exactly -- callers of the shared `Clock` shape never assume a
  // concrete handle type, even though this fake's own handles are numbers.
  clearTimer: (handle: unknown) => void;
  advance: (ms: number) => void;
}

export function createFakeClock(seed = 42): FakeClock {
  let currentTime = 0;
  let nextHandle = 1;
  let randomState = seed >>> 0 || 1;
  const timers = new Map<number, { fireAt: number; fn: () => void }>();

  // A small deterministic PRNG (mulberry32), not a constant: production code
  // like `generateClientMessageId` calls `random()` many times per value and
  // relies on successive calls differing (a constant `random()` collapses
  // every generated ID to the same string, which silently caps a Map keyed
  // by that ID at one entry -- turning any "add N distinct items" loop into
  // an infinite one). Deterministic-but-varying keeps assertions reproducible
  // without that trap.
  function random(): number {
    randomState = (randomState + 0x6d2b79f5) | 0;
    let t = randomState;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  return {
    now: () => currentTime,
    random,

    setTimer(fn, delayMs) {
      const handle = nextHandle;
      nextHandle += 1;
      timers.set(handle, { fireAt: currentTime + delayMs, fn });
      return handle;
    },

    clearTimer(handle) {
      timers.delete(handle as number);
    },

    advance(ms) {
      const target = currentTime + ms;
      for (;;) {
        let dueHandle: number | null = null;
        let dueAt = Number.POSITIVE_INFINITY;
        for (const [handle, timer] of timers) {
          if (timer.fireAt <= target && timer.fireAt < dueAt) {
            dueAt = timer.fireAt;
            dueHandle = handle;
          }
        }
        if (dueHandle === null) break;
        const timer = timers.get(dueHandle);
        timers.delete(dueHandle);
        currentTime = dueAt;
        timer?.fn();
      }
      currentTime = target;
    },
  };
}
