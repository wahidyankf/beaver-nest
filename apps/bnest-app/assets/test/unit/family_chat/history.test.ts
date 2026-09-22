// Plain Vitest unit coverage for `js/family_chat/history.js`: which page of
// a room gets loaded, around which cursor, and when this member's read
// position moves. The Gherkin scenarios cover the journeys; this file pins
// the exact cursors sent to the server (the part a rendered assertion cannot
// see) and the branches those journeys do not reach -- a stale position, a
// window that stops short of the newest message, and jumping back to it.

import { describe, expect, it } from "vitest";
import { createHistory } from "../../../js/family_chat/history.js";
import {
  CONTEXT_PAGE_SIZE,
  MESSAGE_PAGE_SIZE,
  buildTestMessages,
  createTestPageSource,
} from "../../../js/family_chat/page_source.js";
import {
  createMemoryReadStorage,
  createReadMarker,
} from "../../../js/family_chat/read_marker.js";
import { createStore } from "../../../js/family_chat/store.js";

interface Cursor {
  beforeId?: string | null;
  afterId?: string | null;
  limit: number;
}

function roomWith(messageCount: number, lastReadId: string | null) {
  const pageSource = createTestPageSource(
    buildTestMessages({ startId: 1, count: messageCount, body: "Message" }),
  );
  const readMarker = createReadMarker({
    userId: "test-user-family-chat",
    roomSlug: "ruang-keluarga",
    storage: createMemoryReadStorage(),
  });
  if (lastReadId !== null) readMarker.remember(lastReadId);
  const store = createStore();
  const cursors: Cursor[] = [];
  const history = createHistory({
    fetchPage: (cursor: Cursor) => {
      cursors.push(cursor);
      return pageSource.fetchPage(cursor);
    },
    store,
    readMarker,
  });
  return { cursors, history, pageSource, readMarker, store };
}

describe("createHistory", () => {
  it("opens a room this device has never read at the newest page", async () => {
    const { cursors, history, store, readMarker } = roomWith(80, null);
    const result = await history.loadInitial();

    expect(result.mode).toBe("latest");
    expect(cursors).toEqual([{ limit: MESSAGE_PAGE_SIZE }]);
    expect(store.newestId()).toBe("80");
    expect(store.unreadDividerBeforeId()).toBeNull();
    // Landing on the newest message is itself reading it.
    expect(readMarker.lastReadId()).toBe("80");
  });

  it("asks for earlier context before the first unread message, not before the last read one", async () => {
    const { cursors, history, store } = roomWith(60, "50");
    const result = await history.loadInitial();

    expect(result.mode).toBe("resumed");
    expect(cursors).toEqual([
      { afterId: "50", limit: MESSAGE_PAGE_SIZE },
      { beforeId: "51", limit: CONTEXT_PAGE_SIZE },
    ]);
    // `beforeId: "51"` is what keeps message 50 -- the one this member
    // stopped on -- on screen above the marker.
    expect(store.unreadDividerBeforeId()).toBe("51");
    expect(store.firstMessageInViewId()).toBe("51");
    expect(store.contextCount()).toBe(CONTEXT_PAGE_SIZE);
  });

  it("does not treat a resumed window as read", async () => {
    const { history, readMarker } = roomWith(60, "50");
    await history.loadInitial();
    expect(readMarker.lastReadId()).toBe("50");
  });

  it("falls back to the newest page when the stored position is unknown here", async () => {
    const { cursors, history, store, readMarker } = roomWith(30, "9999");
    const result = await history.loadInitial();

    expect(result.mode).toBe("latest");
    expect(cursors).toEqual([
      { afterId: "9999", limit: MESSAGE_PAGE_SIZE },
      { limit: MESSAGE_PAGE_SIZE },
    ]);
    expect(store.newestId()).toBe("30");
    expect(readMarker.lastReadId()).toBe("9999");
  });

  it("stops short of the newest message when more is unread than one page holds", async () => {
    const { history, store } = roomWith(140, "10");
    await history.loadInitial();

    expect(store.hasNewer()).toBe(true);
    expect(store.newestId()).toBe(String(10 + MESSAGE_PAGE_SIZE));
    expect(store.newMessagesIndicatorLabel()).toBe("New messages below");
  });

  it("loads the next page instead of recording a read position at the end of a partial window", async () => {
    const { history, store, readMarker } = roomWith(140, "10");
    await history.loadInitial();

    await history.reportScrolledToBottom();

    expect(store.newestId()).toBe(String(10 + MESSAGE_PAGE_SIZE * 2));
    // Nothing was marked read: the member reached the end of what was
    // loaded, not the end of the conversation.
    expect(readMarker.lastReadId()).toBe("10");
  });

  it("records the read position once the window really does reach the newest message", async () => {
    const { history, readMarker, store } = roomWith(60, "50");
    await history.loadInitial();

    await history.reportScrolledToBottom();

    expect(store.hasNewer()).toBe(false);
    expect(readMarker.lastReadId()).toBe("60");
  });

  it("jumps back to the newest page from a partial window", async () => {
    const { history, readMarker, store } = roomWith(140, "10");
    await history.loadInitial();

    await history.jumpToLatest();

    expect(store.hasNewer()).toBe(false);
    expect(store.unreadDividerBeforeId()).toBeNull();
    expect(store.newestId()).toBe("140");
    expect(readMarker.lastReadId()).toBe("140");
  });

  it("pages earlier history from the oldest message it has", async () => {
    const { cursors, history, store } = roomWith(140, null);
    await history.loadInitial();
    const oldest = store.oldestId();

    await history.loadOlder();

    expect(cursors.at(-1)).toEqual({
      beforeId: oldest,
      limit: MESSAGE_PAGE_SIZE,
    });
    expect(store.hasOlder()).toBe(true);
  });

  it("only counts an arrival as read when the member is at the bottom", async () => {
    const { history, readMarker, store } = roomWith(60, "50");
    await history.loadInitial();

    // Resumed above the newest message: an arrival is not read.
    history.noteArrival();
    expect(readMarker.lastReadId()).toBe("50");

    store.scrolledToBottom();
    history.noteArrival();
    expect(readMarker.lastReadId()).toBe("60");
  });

  it("does nothing when asked for a newer page it knows does not exist", async () => {
    const { cursors, history } = roomWith(30, null);
    await history.loadInitial();
    const before = cursors.length;

    await history.loadNewer();

    expect(cursors.length).toBe(before);
  });
});

describe("jumping to a quoted message", () => {
  it("does not fetch when the target is already in the window", async () => {
    const { cursors, history, store } = roomWith(30, null);
    await history.loadInitial();
    cursors.length = 0;

    const result = await history.jumpToMessage("12");

    expect(result).toEqual({ found: true, pagesLoaded: 0, remediation: null });
    expect(cursors).toEqual([]);
    expect(store.hasRendered("12")).toBe(true);
  });

  it("loads exactly the pages it needs for a target two pages up", async () => {
    const { cursors, history, store } = roomWith(MESSAGE_PAGE_SIZE * 3, null);
    await history.loadInitial();
    cursors.length = 0;
    // Two pages above the loaded window: the oldest rendered message is
    // MESSAGE_PAGE_SIZE * 2 + 1, so anything at or below MESSAGE_PAGE_SIZE
    // is two pages back.
    const target = String(MESSAGE_PAGE_SIZE);

    const result = await history.jumpToMessage(target);

    expect(result.found).toBe(true);
    expect(result.pagesLoaded).toBe(2);
    expect(cursors).toHaveLength(2);
    expect(store.hasRendered(target)).toBe(true);
  });

  it("requests at most five pages, then says so out loud", async () => {
    const { cursors, history, store } = roomWith(MESSAGE_PAGE_SIZE * 12, null);
    await history.loadInitial();
    cursors.length = 0;

    const result = await history.jumpToMessage("1");

    expect(result.found).toBe(false);
    expect(result.pagesLoaded).toBe(5);
    expect(cursors).toHaveLength(5);
    expect(result.remediation).toBe("That message is too far back to jump to.");
    expect(store.hasRendered("1")).toBe(false);
  });

  it("leaves the unread divider and hasNewer alone on every path", async () => {
    for (const [messageCount, target] of [
      [30, "12"],
      [MESSAGE_PAGE_SIZE * 3, String(MESSAGE_PAGE_SIZE)],
      [MESSAGE_PAGE_SIZE * 12, "1"],
    ] as const) {
      const { history, store } = roomWith(messageCount, "5");
      await history.loadInitial();
      const dividerBefore = store.unreadDividerBeforeId();
      const hasNewerBefore = store.hasNewer();

      await history.jumpToMessage(target);

      // A jump is navigation, not reading: moving the divider would tell the
      // member they had read messages they only scrolled past.
      expect(store.unreadDividerBeforeId()).toBe(dividerBefore);
      expect(store.hasNewer()).toBe(hasNewerBefore);
    }
  });

  it("does not move the stored read position", async () => {
    const { history, readMarker } = roomWith(MESSAGE_PAGE_SIZE * 3, "5");
    await history.loadInitial();
    const before = readMarker.lastReadId();

    await history.jumpToMessage(String(MESSAGE_PAGE_SIZE));

    expect(readMarker.lastReadId()).toBe(before);
  });

  it("stops early rather than spending its whole budget once the target arrives", async () => {
    const { cursors, history } = roomWith(MESSAGE_PAGE_SIZE * 6, null);
    await history.loadInitial();
    cursors.length = 0;

    const result = await history.jumpToMessage(String(MESSAGE_PAGE_SIZE * 5));

    expect(result.found).toBe(true);
    expect(cursors).toHaveLength(1);
  });
});
