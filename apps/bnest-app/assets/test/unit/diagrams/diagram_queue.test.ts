// Plain Vitest unit coverage for `js/diagrams/diagram_queue.js`'s failure
// path: a job whose draw rejects drops only itself and the queue drains on.

import { describe, expect, it } from "vitest";
import { createQueue, enqueue } from "../../../js/diagrams/diagram_queue.js";

function failingQueue() {
  return createQueue({
    drawer: {
      draw: async () => {
        throw new Error("engine unavailable");
      },
    },
    yieldTurn: async () => {},
  });
}

describe("a failing draw job", () => {
  it("drops only itself and lets the queue drain", async () => {
    const queue = failingQueue();
    enqueue(queue, {
      key: "bad-source",
      source: "not a diagram",
      themeVariables: {},
      waiters: [],
    });

    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(queue.jobs.size).toBe(0);
    expect(queue.pending).toEqual([]);
    expect(queue.running).toBe(false);
  });
});
