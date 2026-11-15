// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/message_render.js`: the `⋯` actions control is drawn only for a room
// served with replies (family_chat.feature, Rule "Message actions"). The control is absent from the row, not hidden, so
// it cannot be focused or read by a screen reader when replies are off.

import { describe, expect, it } from "vitest";
import { messageNode } from "../../../js/family_chat/message_render.js";

const MORE = '[data-role="family-chat-message-more"]';

const message = {
  id: "1",
  body: "Dinner is ready",
  bodyHtml: "<p>Dinner is ready</p>",
  senderId: "u-ayah",
  senderDisplayName: "Ayah",
  replyTo: null,
};

describe("messageNode: the actions control follows the reply flag", () => {
  it("draws no actions control when replies are off", () => {
    const row = messageNode(message, {
      pending: false,
      currentUserId: "u-me",
      replies: false,
    });

    expect(row.querySelector(MORE)).toBeNull();
  });

  it("draws the actions control on a committed message when replies are on", () => {
    const row = messageNode(message, {
      pending: false,
      currentUserId: "u-me",
      replies: true,
    });

    expect(row.querySelector(MORE)).not.toBeNull();
  });

  it("draws no actions control when the room does not name the flag", () => {
    const row = messageNode(message, { pending: false, currentUserId: "u-me" });

    expect(row.querySelector(MORE)).toBeNull();
  });
});
