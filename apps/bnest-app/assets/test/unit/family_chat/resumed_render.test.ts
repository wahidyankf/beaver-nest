// Plain Vitest unit coverage for what the room draws, right after its history
// loads, for the sends the outbox resumed on construction. A resumed send can
// reach the server after the history page was read but before the room
// renders: it is then Sent, no longer pending, and in no history page --
// the room must still show its committed message, once.

import { describe, expect, it } from "vitest";
import { createOutbox, STATUS } from "../../../js/family_chat/outbox.js";
import { renderResumedPendingMessages } from "../../../js/family_chat/mount_browser_composer.js";
import { createFakeClock } from "../../support/fake_clock";

function storeDouble() {
  const calls: { kind: string; id: string; message?: { id: string } }[] = [];
  return {
    calls,
    store: {
      renderPending: (message: { clientMessageId: string }) =>
        calls.push({ kind: "pending", id: message.clientMessageId }),
      updatePendingStatus: () => undefined,
      reconcile: (id: string, message: { id: string }) =>
        calls.push({ kind: "reconcile", id, message }),
    },
  };
}

describe("rendering the sends a reopened room resumed", () => {
  it("shows the committed message of a resumed send that reached Sent before the room rendered", async () => {
    const clock = createFakeClock();
    const outbox = createOutbox({
      userId: "test-user-resumed-render",
      roomSlug: "ruang-keluarga",
      clock,
      transport: ({ clientMessageId, body }) =>
        Promise.resolve({
          ok: true as const,
          message: { id: `server-${clientMessageId}`, body },
        }),
    });
    const id = await outbox.send("Sent while the history loaded");
    if (!id) throw new Error("the outbox refused the message");
    await outbox.waitForStatus(id, STATUS.SENT);
    expect(outbox.pendingMessages()).toEqual([]);

    const { calls, store } = storeDouble();
    renderResumedPendingMessages(
      {
        outbox,
        store,
        history: { noteArrival: () => undefined },
      } as never,
      { outboxStatus: { textContent: "" } } as never,
    );

    expect(calls).toEqual([
      {
        kind: "reconcile",
        id,
        message: {
          id: `server-${id}`,
          body: "Sent while the history loaded",
        },
      },
    ]);
  });
});
