// Plain Vitest unit coverage for `js/family_chat/reconnect.js` (tech-doc 007's
// File Impact list): the ordered promotion sequence (tech-doc 003), observed
// through the collaborators `mount_browser.js` binds in the browser -- the
// socket client it closes and the callbacks it pauses, resubscribes, fetches,
// merges and resumes through.

import { describe, expect, it } from "vitest";
import {
  createReconnect,
  promoteSlot,
  resumeFromBackground,
} from "../../../js/family_chat/reconnect.js";

describe("createReconnect / promoteSlot", () => {
  it("closes the bound socket client once per promotion", async () => {
    let closeCalls = 0;
    const reconnect = createReconnect({
      socketClient: { close: () => (closeCalls += 1) },
    });

    await promoteSlot(reconnect);

    expect(closeCalls).toBe(1);
  });

  it("runs every bound browser callback, in order, during one promotion", async () => {
    const calls: string[] = [];
    const reconnect = createReconnect({
      socketClient: { close: () => calls.push("close") },
    });

    reconnect.bindBrowserCallbacks({
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
      "close",
      "resubscribe",
      "fetchMissed:server-0",
      "mergeMessages:2",
      "onResume",
    ]);
  });

  it("runs a promotion with no socket client and no bound callbacks", async () => {
    const reconnect = createReconnect();

    await promoteSlot(reconnect);

    expect(reconnect.generation()).toBe(1);
  });

  it("never calls mergeMessages when the catch-up query found nothing to merge", async () => {
    const reconnect = createReconnect();
    let mergeCalls = 0;

    reconnect.bindBrowserCallbacks({
      fetchMissed: async () => [],
      mergeMessages: async () => {
        mergeCalls += 1;
      },
    });

    await promoteSlot(reconnect);
    expect(mergeCalls).toBe(0);
  });

  it("keeps the most recently reported committed ID across multiple updates", async () => {
    const reconnect = createReconnect();
    let fetchMissedArg: unknown;

    reconnect.bindBrowserCallbacks({
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

  it("discards a stale catch-up result once a newer generation has started", async () => {
    // Drives the internal steps directly rather than racing two
    // `promoteSlot()` calls on hand-counted microtask ticks: a second socket
    // reconnect starts while the first catch-up query is still in flight.
    const merged: unknown[][] = [];
    const pending: { resolve: ((messages: unknown[]) => void) | null } = {
      resolve: null,
    };
    const reconnect = createReconnect();
    reconnect.bindBrowserCallbacks({
      fetchMissed: () =>
        new Promise<unknown[]>((resolve) => {
          pending.resolve = resolve;
        }),
      mergeMessages: async (messages: unknown[]) => {
        merged.push(messages);
      },
    });

    await reconnect.recreateSocketStep(); // generation 0 -> 1
    const staleGeneration = reconnect.generation();
    const catchUpPromise = reconnect.catchUpQueryStep(staleGeneration);

    await reconnect.recreateSocketStep(); // generation 1 -> 2
    pending.resolve?.([{ id: "late" }]);
    await catchUpPromise;
    await reconnect.mergeByServerIdStep();

    expect(merged).toEqual([]);
  });

  it("advances the generation counter once per promotion", async () => {
    const reconnect = createReconnect();

    expect(reconnect.generation()).toBe(0);
    await promoteSlot(reconnect);
    expect(reconnect.generation()).toBe(1);
    await promoteSlot(reconnect);
    expect(reconnect.generation()).toBe(2);
  });
});

describe("a promotion that cannot finish", () => {
  it("still resumes the outbox drain when the catch-up fails, so queued sends are not held for good", async () => {
    const calls: string[] = [];
    const reconnect = createReconnect();
    reconnect.bindBrowserCallbacks({
      onPause: () => calls.push("pause"),
      fetchMissed: () => Promise.reject(new Error("Internal Server Error")),
      onResume: () => calls.push("resume"),
    });

    await expect(promoteSlot(reconnect)).rejects.toThrow("Internal Server");

    expect(calls).toEqual(["pause", "resume"]);
  });
});

describe("resumeFromBackground", () => {
  it("forces a reconnect on the socket client every time", () => {
    let reconnects = 0;
    const socketClient = { reconnectNow: () => (reconnects += 1) };

    resumeFromBackground(socketClient);
    resumeFromBackground(socketClient);

    expect(reconnects).toBe(2);
  });
});
