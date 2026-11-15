// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for the diagram engine hold of `test/support/fake_diagram_engine.ts`. A scenario may hold the
// engine and leave it held (the Codex and Family steps that press keys while a diagram is still its source). The next
// scenario must not inherit that hold: `startWorld` releases it, so the engine starts at once.

import { describe, expect, it } from "vitest";
import { closeWorld, startWorld } from "../behaviour/support/browser_room";
import { holdDiagramEngine, loadEngine } from "../support/fake_diagram_engine";

const NOT_STARTED = Symbol("not started");

describe("a diagram engine hold left open by an earlier scenario", () => {
  it("does not hold the next scenario's engine once that scenario starts", async () => {
    holdDiagramEngine();
    startWorld();
    try {
      const started = await Promise.race([
        loadEngine(),
        new Promise<typeof NOT_STARTED>((resolve) => {
          setTimeout(() => resolve(NOT_STARTED), 200);
        }),
      ]);
      expect(started).not.toBe(NOT_STARTED);
    } finally {
      await closeWorld();
    }
  });
});
