// Plain Vitest unit coverage for the catch-up query of
// `js/family_chat/mount_browser_sync.js`: the gap a reconnect fills is asked
// for in pages the server accepts, for as long as the server says there is
// more.

import { describe, expect, it } from "vitest";
import { bindReconnectCallbacks } from "../../../js/family_chat/mount_browser_sync.js";
import { createFakeClock } from "../../support/fake_clock";
import { MESSAGE_PAGE_SIZE } from "../../../js/family_chat/page_source.js";

interface Variables {
  roomSlug: string;
  afterId?: string;
  limit: number;
}

type FetchMissed = (afterId: string | null) => Promise<{ id: string }[]>;

/** The server's own cursor contract (`BnestApp.FamilyChat.Domain.Cursor`). */
function serverWith(committedIds: number[]) {
  const asked: Variables[] = [];
  async function request(_document: string, variables: Variables) {
    await Promise.resolve();
    asked.push(variables);
    if (variables.limit < 1 || variables.limit > 50) {
      return {
        data: null,
        errors: [{ extensions: { code: "VALIDATION_FAILED" } }],
      };
    }
    const after = Number(variables.afterId ?? 0);
    const newer = committedIds.filter((id) => id > after);
    const nodes = newer
      .slice(0, variables.limit)
      .map((id) => ({ id: String(id) }));
    return {
      data: {
        familyChatMessages: {
          nodes,
          hasOlder: true,
          hasNewer: newer.length > nodes.length,
        },
      },
    };
  }
  return { request, asked };
}

function catchUp(request: unknown): FetchMissed {
  let fetchMissed: FetchMissed | null = null;
  const room = {
    request,
    roomSlug: "ruang-keluarga",
    replies: true,
    reconnect: {
      bindBrowserCallbacks(callbacks: { fetchMissed: FetchMissed }) {
        fetchMissed = callbacks.fetchMissed;
      },
    },
  };
  bindReconnectCallbacks(room as never, {} as never);
  if (!fetchMissed) throw new Error("no catch-up query was bound");
  return fetchMissed;
}

describe("the reconnect catch-up query", () => {
  it("asks for no more than the server's page size", async () => {
    const { request, asked } = serverWith([11, 12]);

    const missed = await catchUp(request)("10");

    expect(missed.map((message) => message.id)).toEqual(["11", "12"]);
    expect(asked).toEqual([
      { roomSlug: "ruang-keluarga", afterId: "10", limit: MESSAGE_PAGE_SIZE },
    ]);
  });

  it("keeps paging after the last message it got while the server has newer", async () => {
    const committed = Array.from({ length: 120 }, (_, index) => index + 1);
    const { request, asked } = serverWith(committed);

    const missed = await catchUp(request)(null);

    expect(missed.map((message) => message.id)).toEqual(committed.map(String));
    expect(asked.map((variables) => variables.afterId)).toEqual([
      undefined,
      "50",
      "100",
    ]);
  });

  it("returns nothing when nothing was missed", async () => {
    const { request, asked } = serverWith([5]);

    expect(await catchUp(request)("5")).toEqual([]);
    expect(asked).toHaveLength(1);
  });
});

describe("the reconnect catch-up query meeting a failing server", () => {
  it("asks again after a backoff, on the room's clock, and returns what the retry got", async () => {
    const clock = createFakeClock();
    const { request, asked } = serverWith([11]);
    let failures = 2;
    function flaky(document: string, variables: Variables) {
      if (failures > 0) {
        failures -= 1;
        return Promise.reject(new SyntaxError("Unexpected token 'I'"));
      }
      return request(document, variables);
    }
    let fetchMissed: FetchMissed | null = null;
    bindReconnectCallbacks(
      {
        request: flaky,
        clock,
        roomSlug: "ruang-keluarga",
        reconnect: {
          bindBrowserCallbacks(callbacks: { fetchMissed: FetchMissed }) {
            fetchMissed = callbacks.fetchMissed;
          },
        },
      } as never,
      {} as never,
    );
    if (!fetchMissed) throw new Error("no catch-up query was bound");

    const missing = (fetchMissed as FetchMissed)("10");
    let done = false;
    void missing.then(() => {
      done = true;
    });
    for (let turn = 0; turn < 50 && !done; turn += 1) {
      // eslint-disable-next-line no-await-in-loop -- one macrotask lets the query's own awaits settle before time moves.
      await new Promise((resolve) => setTimeout(resolve, 0));
      const due = clock.nextDueAt();
      if (due !== null) clock.advance(due - clock.now());
    }

    expect((await missing).map((message) => message.id)).toEqual(["11"]);
    expect(asked).toHaveLength(1);
    expect(failures).toBe(0);
  });
});
