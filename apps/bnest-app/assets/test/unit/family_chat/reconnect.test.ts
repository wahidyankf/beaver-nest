// Plain Vitest unit coverage for `js/family_chat/reconnect.js` (tech-doc 007's
// File Impact list): the ordered six-step promotion sequence (tech-doc 003)
// and the real-collaborator seam (`_bindBrowserCallbacks`) that
// `family_chat.js` uses in the browser but `test/behaviour/family_chat.
// steps.ts` never exercises (its `promoteSlot` scenario only ever runs
// against the document-less, no-collaborator `room.reconnect`).

import { describe, expect, it } from "vitest";
import {
  createReconnect,
  promoteSlot,
} from "../../../js/family_chat/reconnect.js";
import { createFakeClock } from "./support/fake_clock.ts";

describe("createReconnect / promoteSlot", () => {
  it("runs the six ordered steps and ends draining again", async () => {
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });

    expect(reconnect.isDraining()).toBe(false);
    await promoteSlot(reconnect);

    expect(reconnect.priorSlotClosed()).toBe(true);
    expect(reconnect.isDraining()).toBe(true);
    expect(reconnect.pageReloaded()).toBe(false);
  });

  it("closes the real socket client during _closePriorSocket when one is bound", async () => {
    const clock = createFakeClock();
    let closeCalls = 0;
    const reconnect = createReconnect({
      clock,
      socketClient: { close: () => (closeCalls += 1) },
    });

    await promoteSlot(reconnect);

    expect(closeCalls).toBe(1);
    expect(reconnect.priorSlotClosed()).toBe(true);
  });

  it("runs every bound browser callback, in order, during one promotion", async () => {
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });
    const calls: string[] = [];

    reconnect._bindBrowserCallbacks({
      resubscribe: async () => {
        calls.push("resubscribe");
      },
      fetchMissed: async (afterId: unknown) => {
        calls.push(`fetchMissed:${afterId}`);
        return [{ id: "server-1" }, { id: "server-2" }];
      },
      mergeMessages: async (messages: unknown[]) => {
        calls.push(`mergeMessages:${messages.length}`);
      },
      onPause: () => calls.push("onPause"),
      onResume: () => calls.push("onResume"),
    });

    reconnect.setHighestCommittedId("server-0");
    await promoteSlot(reconnect);

    expect(calls).toEqual([
      "onPause",
      "resubscribe",
      "fetchMissed:server-0",
      "mergeMessages:2",
      "onResume",
    ]);
  });

  it("never calls mergeMessages when the catch-up query found nothing to merge", async () => {
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });
    let mergeCalls = 0;

    reconnect._bindBrowserCallbacks({
      fetchMissed: async () => [],
      mergeMessages: async () => {
        mergeCalls += 1;
      },
    });

    await promoteSlot(reconnect);
    expect(mergeCalls).toBe(0);
  });

  it("keeps the most recently reported committed ID across multiple updates", async () => {
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });
    let fetchMissedArg: unknown;

    reconnect._bindBrowserCallbacks({
      fetchMissed: async (afterId: unknown) => {
        fetchMissedArg = afterId;
        return [];
      },
    });

    reconnect.setHighestCommittedId("id-1");
    reconnect.setHighestCommittedId("id-2");
    reconnect.setHighestCommittedId(null); // a null/undefined update never clobbers the last real ID
    reconnect.setHighestCommittedId(undefined);

    await promoteSlot(reconnect);
    expect(fetchMissedArg).toBe("id-2");
  });

  it("discards a stale catch-up write once a newer generation has started", async () => {
    // Exercises the same generation guard `promoteSlot` relies on
    // (`_catchUpQuery` bails if `_recreateSocket` ran again while its own
    // `fetchMissed` call was still in flight -- e.g. a second real socket
    // reconnect firing before the first promotion finished) by driving the
    // internal steps directly instead of racing two `promoteSlot()` calls
    // against each other on hand-counted microtask ticks.
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });

    let resolveFetch: ((messages: unknown[]) => void) | null = null;
    reconnect._bindBrowserCallbacks({
      fetchMissed: () =>
        new Promise((resolve) => {
          resolveFetch = resolve;
        }),
    });

    await reconnect._recreateSocket(); // generation 0 -> 1
    const staleGeneration = reconnect._generation();
    const catchUpPromise = reconnect._catchUpQuery(staleGeneration); // blocks on fetchMissed

    await reconnect._recreateSocket(); // generation 1 -> 2: a newer promotion started
    resolveFetch?.([{ id: "late" }]);
    await catchUpPromise;

    // The stale write never lands: `catchUpDurationMs` stays at its initial
    // value instead of being set by a generation that is no longer current.
    expect(reconnect.catchUpDurationMs()).toBe(0);
  });

  it("exposes the underlying generation counter, advanced once per promotion", async () => {
    const clock = createFakeClock();
    const reconnect = createReconnect({ clock });

    expect(reconnect._generation()).toBe(0);
    await promoteSlot(reconnect);
    expect(reconnect._generation()).toBe(1);
    await promoteSlot(reconnect);
    expect(reconnect._generation()).toBe(2);
  });
});
