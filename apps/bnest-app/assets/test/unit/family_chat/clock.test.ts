// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/clock.js`: the system clock
// hands out the real wall-clock time, randomness, and timers.

import { describe, expect, it, vi } from "vitest";
import { createSystemClock } from "../../../js/family_chat/clock.js";

describe("createSystemClock", () => {
  it("reads the wall clock and randomness from the runtime", () => {
    const clock = createSystemClock();
    const before = Date.now();
    const now = clock.now();
    expect(now).toBeGreaterThanOrEqual(before);
    expect(now).toBeLessThanOrEqual(Date.now());
    const r = clock.random();
    expect(r).toBeGreaterThanOrEqual(0);
    expect(r).toBeLessThan(1);
  });

  it("schedules and cancels timers", () => {
    vi.useFakeTimers();
    try {
      const clock = createSystemClock();
      let calls = 0;
      const handle = clock.setTimer(() => {
        calls += 1;
      }, 50);
      vi.advanceTimersByTime(49);
      expect(calls).toBe(0);
      vi.advanceTimersByTime(1);
      expect(calls).toBe(1);
      clock.clearTimer(handle);
    } finally {
      vi.useRealTimers();
    }
  });

  it("clearing a timer stops it from firing", () => {
    vi.useFakeTimers();
    try {
      const clock = createSystemClock();
      let calls = 0;
      const handle = clock.setTimer(() => {
        calls += 1;
      }, 10);
      clock.clearTimer(handle);
      vi.advanceTimersByTime(100);
      expect(calls).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });
});
