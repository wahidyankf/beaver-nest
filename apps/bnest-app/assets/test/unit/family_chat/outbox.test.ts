// Plain Vitest unit coverage for `js/family_chat/outbox.js` (tech-doc 007's
// File Impact list), exercising its public API directly rather than through
// a Gherkin scenario -- edge cases (queue-cap callback wiring, the
// reconnect-driven pause/resume seam, multi-listener `onChange`, auth-expiry
// pausing, logout isolation) that `test/behaviour/family_chat.steps.ts`
// either does not reach at all or reaches only incidentally.

import { describe, expect, it } from "vitest";
import {
  createOutbox,
  MAX_QUEUED_PER_ROOM,
  QUEUE_SCHEMA_VERSION,
  STATUS,
} from "../../../js/family_chat/outbox.js";
import { createFakeClock, type FakeClock } from "./support/fake_clock.ts";

let namespaceCounter = 0;
// Each outbox namespace is module-scoped and persists across calls (by
// design, so a real reopen resumes draining); a fresh userId per test keeps
// this file's specs from leaking state into each other.
function uniqueIdentity() {
  namespaceCounter += 1;
  return {
    userId: `test-user-${namespaceCounter}`,
    roomSlug: "ruang-keluarga",
  };
}

/**
 * Settles on the given clock's timer (a real macrotask via
 * `createSystemClock`, or an explicit `clock.advance()` here) rather than a
 * bare microtask -- otherwise `attemptSend`'s own internal `await` would
 * always resolve before a caller's `await outbox.send(...)` did, making the
 * intermediate "Sending" status unobservable (see `family_chat.js`'s
 * matching comment on `createTestTransport`, which hit this exact issue).
 */
function okTransport(clock: FakeClock) {
  return ({
    clientMessageId,
    body,
  }: {
    clientMessageId: string;
    body: string;
  }) =>
    new Promise((resolve) => {
      clock.setTimer(
        () =>
          resolve({
            ok: true,
            message: { id: `server-${clientMessageId}`, body },
          }),
        0,
      );
    });
}

describe("createOutbox", () => {
  it("requires a transport function", () => {
    const { userId, roomSlug } = uniqueIdentity();
    expect(() =>
      // @ts-expect-error -- deliberately omitting the required transport
      createOutbox({ userId, roomSlug }),
    ).toThrow(TypeError);
  });

  it("rejects a fourth queued message once 100 are already active", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    let queueFullCalls = 0;
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: () => new Promise(() => {}), // never resolves: keeps every message "active"
      onQueueFull: () => {
        queueFullCalls += 1;
      },
    });

    await outbox.fillWithQueuedMessages(MAX_QUEUED_PER_ROOM);
    const clientMessageId = await outbox.send("one too many");

    expect(clientMessageId).toBeNull();
    expect(queueFullCalls).toBe(1);
  });

  it("keeps FIFO status transitions and reconciles the real committed message", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: okTransport(clock),
    });

    const id = await outbox.send("hello family");
    expect(outbox.status(id)).toBe(STATUS.SENDING);

    clock.advance(0);
    const sent = await outbox.waitForStatus(id, STATUS.SENT);
    expect(sent).toBe(STATUS.SENT);
    expect(outbox.committedMessage(id)).toEqual({
      id: `server-${id}`,
      body: "hello family",
    });
  });

  it("reports every transition to a persistent onChange listener until unsubscribed", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: okTransport(clock),
    });

    const seen: string[] = [];
    const id = await outbox.send("watch me");
    const unsubscribe = outbox.onChange(id, (status) => seen.push(status));
    clock.advance(0);
    await outbox.waitForStatus(id, STATUS.SENT);
    unsubscribe();

    // Sending was already the status before `onChange` attached (it fires on
    // transitions, not on attach), so the first observed transition is Sent.
    expect(seen).toEqual([STATUS.SENT]);

    // Nothing further reaches the listener once unsubscribed.
    await outbox.send("after unsubscribe");
    expect(seen).toEqual([STATUS.SENT]);
  });

  it("pauses the whole outbox (not just one message) on an authExpired transport result", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    let authExpiredCalls = 0;
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: async () => ({ ok: false, authExpired: true }),
      onAuthExpired: () => {
        authExpiredCalls += 1;
      },
    });

    const id = await outbox.send("will pause");
    await outbox.waitForStatus(id, STATUS.RETRYING);

    expect(authExpiredCalls).toBe(1);
    expect(outbox.isDraining()).toBe(false);

    // A second send is queued but never attempted while paused.
    const secondId = await outbox.send("also queued");
    expect(outbox.status(secondId)).toBe(STATUS.WAITING);
  });

  it("supports an external pause/resume seam for reconnect.js's ordered promotion", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: okTransport(clock),
    });

    outbox.pauseDrain();
    expect(outbox.isDraining()).toBe(false);

    const id = await outbox.send("queued while paused");
    // Gives every pending microtask a chance to run; nothing should have
    // reached "Sent" while paused.
    await Promise.resolve();
    await Promise.resolve();
    expect(outbox.status(id)).toBe(STATUS.WAITING);

    outbox.resumeDrain();
    expect(outbox.isDraining()).toBe(true);
    clock.advance(0);
    await outbox.waitForStatus(id, STATUS.SENT);
  });

  it("clears and isolates a namespace on logout, independent of another user's queue", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: () => new Promise(() => {}),
    });

    const id = await outbox.send("never delivered before logout");
    outbox.logout();

    expect(outbox.isCleared()).toBe(true);
    expect(outbox.status(id)).toBe("not-found");

    // A different user's namespace for the same room is unaffected.
    const other = createOutbox({
      userId: `${userId}-other`,
      roomSlug,
      clock,
      transport: okTransport(clock),
    });
    expect(other.isCleared()).toBe(false);
  });

  it("makes a retrying message immediately eligible on an online hint", async () => {
    const { userId, roomSlug } = uniqueIdentity();
    const clock = createFakeClock();
    let attempts = 0;
    const outbox = createOutbox({
      userId,
      roomSlug,
      clock,
      transport: async () => {
        attempts += 1;
        return attempts === 1
          ? { ok: false, retryable: true }
          : { ok: true, message: { id: "server-1" } };
      },
    });

    const id = await outbox.send("flaky");
    await outbox.waitForStatus(id, STATUS.RETRYING);
    expect(outbox.nextRetryEtaMs(id)).toBeGreaterThan(0);

    outbox.reportBrowserEvent("online");
    expect(outbox.nextRetryEtaMs(id)).toBeLessThanOrEqual(0);
    await outbox.waitForStatus(id, STATUS.SENT);
  });

  it("exports a schema version for the persisted queue format", () => {
    expect(QUEUE_SCHEMA_VERSION).toBe(1);
  });
});
