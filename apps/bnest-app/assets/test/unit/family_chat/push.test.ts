// Plain Vitest unit coverage for `js/family_chat/push.js`'s notification
// payload/click-target resolution (tech-doc 004's service-worker `push`/
// `notificationclick` handlers), exercised directly rather than through a
// Gherkin scenario -- no canonical scenario names this behavior; a real
// browser `push` event cannot be dispatched at any automated layer this
// plan's harness has (see the plan's own boundary decision: OS-owned
// installed-PWA notification display is outside plan completion). These
// pure functions are the one part of that boundary this plan can and does
// prove directly; `priv/static/service-worker.js` keeps a literal, comment-
// linked copy of this exact logic because it is a classic (non-module)
// worker script that cannot `import` it.

import { describe, expect, it } from "vitest";
import {
  resolveNotificationClickTarget,
  resolveNotificationPayload,
  urlBase64ToUint8Array,
} from "../../../js/family_chat/push.js";

const ROOM_PATH = "/family-chat/ruang-keluarga";

describe("resolveNotificationPayload", () => {
  it("returns the exact validated fields for a well-formed family-chat-message payload", () => {
    const payload = resolveNotificationPayload({
      type: "family-chat-message",
      messageId: 123,
      title: "Aisha",
      body: "Dinner is ready.",
      tag: "family-chat-message-123",
      url: ROOM_PATH,
    });

    expect(payload).toEqual({
      title: "Aisha",
      body: "Dinner is ready.",
      tag: "family-chat-message-123",
      url: ROOM_PATH,
    });
  });

  it("ignores unknown keys instead of rejecting the payload", () => {
    const payload = resolveNotificationPayload({
      type: "family-chat-message",
      title: "Aisha",
      body: "Dinner is ready.",
      tag: "family-chat-message-1",
      url: ROOM_PATH,
      unexpectedKey: "should be ignored",
    });

    expect(payload.title).toBe("Aisha");
  });

  it.each([
    ["no data at all", null],
    ["a non-object", "not-an-object"],
    [
      "the wrong type discriminator",
      { type: "other", title: "x", body: "y", tag: "z", url: ROOM_PATH },
    ],
    [
      "a missing title",
      { type: "family-chat-message", body: "y", tag: "z", url: ROOM_PATH },
    ],
    [
      "a non-string body",
      {
        type: "family-chat-message",
        title: "x",
        body: 123,
        tag: "z",
        url: ROOM_PATH,
      },
    ],
    [
      "a mismatched url",
      {
        type: "family-chat-message",
        title: "x",
        body: "y",
        tag: "z",
        url: "https://evil.example.com/",
      },
    ],
  ])(
    "falls back to the generic same-room notification for %s",
    (_label, rawData) => {
      const payload = resolveNotificationPayload(rawData);

      expect(payload).toEqual({
        title: "New family message",
        body: "",
        tag: "family-chat-message",
        url: ROOM_PATH,
      });
    },
  );
});

describe("urlBase64ToUint8Array", () => {
  it("decodes a URL-safe base64 VAPID key into the expected raw bytes", () => {
    // "hello" base64-encoded is "aGVsbG8=" -- URL-safe form strips the "="
    // padding this function must restore before decoding.
    const decoded = urlBase64ToUint8Array("aGVsbG8");
    expect(Array.from(decoded)).toEqual([104, 101, 108, 108, 111]);
  });

  it("decodes URL-safe '-' and '_' characters identically to their standard '+' and '/' equivalents", () => {
    const standard = urlBase64ToUint8Array("+/+/");
    const urlSafe = urlBase64ToUint8Array("-_-_");
    expect(Array.from(urlSafe)).toEqual(Array.from(standard));
    expect(Array.from(urlSafe).length).toBeGreaterThan(0);
  });
});

describe("resolveNotificationClickTarget", () => {
  it("accepts the one known same-origin room path", () => {
    expect(resolveNotificationClickTarget({ url: ROOM_PATH })).toBe(ROOM_PATH);
  });

  it.each([
    ["no data at all", null],
    ["a non-object", "not-an-object"],
    ["an arbitrary external URL", { url: "https://evil.example.com/" }],
    ["a different in-app path", { url: "/settings" }],
  ])(
    "never trusts %s as a navigation target, resolving to the fixed room path instead",
    (_label, rawData) => {
      expect(resolveNotificationClickTarget(rawData)).toBe(ROOM_PATH);
    },
  );
});
