// Plain Vitest unit coverage for how the room loads its first history page:
// a load that meets a network error or a non-JSON 5xx (a reload landing in a
// Caddy cutover) is retried with bounded, jittered backoff on the room's
// clock, rather than leaving the room at "booting" for good.

import { describe, expect, it } from "vitest";
import {
  INITIAL_LOAD_ATTEMPTS,
  loadInitialMessages,
} from "../../../js/family_chat/mount_browser_sync.js";
import { createFakeClock, type FakeClock } from "../../support/fake_clock";

function roomDouble(clock: FakeClock, failures: number) {
  const state = { attempts: 0, highest: null as string | null };
  const room = {
    clock,
    history: {
      loadInitial: () => {
        state.attempts += 1;
        if (state.attempts <= failures) {
          return Promise.reject(
            new SyntaxError(`Unexpected token 'I', "Internal S"...`),
          );
        }
        return Promise.resolve({ mode: "latest", newestId: "7" });
      },
    },
    reconnect: {
      setHighestCommittedId: (id: string) => {
        state.highest = id;
      },
    },
  };
  return { room, state };
}

/** Lets each backoff wait elapse, the way real time would, until `done`. */
async function runClockUntil(
  clock: FakeClock,
  settled: Promise<unknown>,
): Promise<number> {
  let finished = false;
  void settled.then(() => {
    finished = true;
  });
  const started = clock.now();
  for (let turn = 0; turn < 200 && !finished; turn += 1) {
    // eslint-disable-next-line no-await-in-loop -- one macrotask lets the load's own awaits settle before time moves.
    await new Promise((resolve) => setTimeout(resolve, 0));
    const due = clock.nextDueAt();
    if (due !== null) clock.advance(due - clock.now());
  }
  return clock.now() - started;
}

describe("the room's first history load", () => {
  it("retries a failed load and goes on with what the retry returned", async () => {
    const clock = createFakeClock();
    const { room, state } = roomDouble(clock, 2);

    const loading = loadInitialMessages(room as never);
    await runClockUntil(clock, loading);

    expect(await loading).toBe(true);
    expect(state.attempts).toBe(3);
    expect(state.highest).toBe("7");
  });

  it("gives up after a bounded number of attempts inside ten seconds, without rejecting", async () => {
    const clock = createFakeClock();
    const { room, state } = roomDouble(clock, Number.POSITIVE_INFINITY);

    const loading = loadInitialMessages(room as never);
    const waited = await runClockUntil(clock, loading);

    expect(await loading).toBe(false);
    expect(state.attempts).toBe(INITIAL_LOAD_ATTEMPTS);
    expect(state.highest).toBeNull();
    expect(waited).toBeGreaterThan(0);
    expect(waited).toBeLessThanOrEqual(10_000);
  });

  it("does not wait at all when the first attempt works", async () => {
    const clock = createFakeClock();
    const { room, state } = roomDouble(clock, 0);

    expect(await loadInitialMessages(room as never)).toBe(true);
    expect(state.attempts).toBe(1);
    expect(clock.nextDueAt()).toBeNull();
  });
});
