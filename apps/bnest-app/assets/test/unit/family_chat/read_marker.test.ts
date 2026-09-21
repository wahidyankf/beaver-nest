// Plain Vitest unit coverage for `js/family_chat/read_marker.js`: the
// per-member, per-room record of how far this device has read. The Gherkin
// scenarios drive it through `history.js`; this file covers the branches
// those journeys never reach -- a hostile or absent Web Storage, a
// non-numeric id, and the monotonicity rule that keeps a late catch-up page
// from dragging the position backwards.

import { describe, expect, it } from "vitest";
import {
  createMemoryReadStorage,
  createReadMarker,
  resolveReadStorage,
} from "../../../js/family_chat/read_marker.js";

function markerWithMemory() {
  const storage = createMemoryReadStorage();
  return {
    storage,
    marker: createReadMarker({
      userId: "test-user-family-chat",
      roomSlug: "ruang-keluarga",
      storage,
    }),
  };
}

describe("createReadMarker", () => {
  it("has no position until one is remembered", () => {
    const { marker } = markerWithMemory();
    expect(marker.lastReadId()).toBeNull();
    marker.remember("12");
    expect(marker.lastReadId()).toBe("12");
  });

  it("never moves the position backwards", () => {
    const { marker } = markerWithMemory();
    marker.remember("40");
    marker.remember("9");
    expect(marker.lastReadId()).toBe("40");
  });

  it("compares ids numerically rather than lexicographically", () => {
    const { marker } = markerWithMemory();
    marker.remember("9");
    marker.remember("10");
    expect(marker.lastReadId()).toBe("10");
  });

  it("ignores an absent id and forgets on request", () => {
    const { marker } = markerWithMemory();
    marker.remember("7");
    marker.remember(null);
    marker.remember("");
    expect(marker.lastReadId()).toBe("7");
    marker.forget();
    expect(marker.lastReadId()).toBeNull();
  });

  it("takes the newer id when either side is not a number", () => {
    const { marker, storage } = markerWithMemory();
    storage.setItem("bnest.family-chat.last-read.test-user-family-chat.ruang-keluarga", "not-a-number");
    marker.remember("3");
    expect(marker.lastReadId()).toBe("3");
  });

  it("keeps separate positions per member and per room", () => {
    const storage = createMemoryReadStorage();
    const mine = createReadMarker({
      userId: "test-user-a",
      roomSlug: "ruang-keluarga",
      storage,
    });
    const theirs = createReadMarker({
      userId: "test-user-b",
      roomSlug: "ruang-keluarga",
      storage,
    });
    mine.remember("31");
    expect(theirs.lastReadId()).toBeNull();
  });

  it("degrades to an in-memory store when Web Storage refuses", () => {
    const hostile = {
      getItem() {
        throw new Error("blocked");
      },
      setItem() {
        throw new Error("blocked");
      },
      removeItem() {
        throw new Error("blocked");
      },
    };
    const marker = createReadMarker({
      userId: "test-user-family-chat",
      roomSlug: "ruang-keluarga",
      storage: hostile,
    });
    // Nothing throws out to the room, and the room simply behaves as if it
    // had never been opened on this device.
    marker.remember("5");
    expect(marker.lastReadId()).toBeNull();
    marker.forget();
  });

  it("falls back to memory when the environment has no localStorage", () => {
    // Node has none, which is exactly the "no Web Storage here" branch.
    const resolved = resolveReadStorage();
    resolved.setItem("probe", "value");
    expect(resolved.getItem("probe")).toBe("value");
    resolved.removeItem("probe");
    expect(resolved.getItem("probe")).toBeNull();
  });

  it("prefers a storage the caller supplied", () => {
    const supplied = createMemoryReadStorage();
    expect(resolveReadStorage(supplied)).toBe(supplied);
  });
});
