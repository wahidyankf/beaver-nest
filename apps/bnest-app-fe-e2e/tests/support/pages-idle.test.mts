import assert from "node:assert/strict";
import test from "node:test";
import { waitForPagesIdle, type IdlePage } from "./pages-idle.mts";

function fakePage(options: { closed?: boolean; fails?: boolean; timesOut?: boolean } = {}) {
  const calls: Array<{ state: string; timeout: number }> = [];
  const page: IdlePage = {
    isClosed: () => options.closed === true,
    waitForLoadState: (state, loadOptions) => {
      calls.push({ state, timeout: loadOptions.timeout });
      if (options.timesOut === true) {
        const timeout = new Error("page.waitForLoadState: Timeout exceeded");
        timeout.name = "TimeoutError";
        return Promise.reject(timeout);
      }
      return options.fails === true ? Promise.reject(new Error("still busy")) : Promise.resolve();
    },
  };
  return { page, calls };
}

test("waits for network idle on every open page with the given timeout", async () => {
  const first = fakePage();
  const second = fakePage();

  await waitForPagesIdle([first.page, second.page], 7000);

  assert.deepEqual(first.calls, [{ state: "networkidle", timeout: 7000 }]);
  assert.deepEqual(second.calls, [{ state: "networkidle", timeout: 7000 }]);
});

test("does not wait on a page that is already closed", async () => {
  const closed = fakePage({ closed: true });

  await waitForPagesIdle([closed.page], 7000);

  assert.deepEqual(closed.calls, []);
});

test("lets the scenario go on when a page holds a request until the timeout", async () => {
  const held = fakePage({ timesOut: true });
  const idle = fakePage();

  await waitForPagesIdle([held.page, idle.page], 7000);

  assert.equal(idle.calls.length, 1);
});

test("rejects on any other failure, after every page was waited on", async () => {
  const busy = fakePage({ fails: true });
  const idle = fakePage();

  await assert.rejects(waitForPagesIdle([busy.page, idle.page], 7000), /still busy/u);

  assert.equal(idle.calls.length, 1);
});
