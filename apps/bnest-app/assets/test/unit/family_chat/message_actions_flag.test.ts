// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/message_render.js`: the `⋯` actions control is drawn
// on a committed message (family_chat.feature, Rule "Message actions").

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

describe("messageNode: the actions control", () => {
  it("draws the actions control on a committed message by default", () => {
    const row = messageNode(message, {
      pending: false,
      currentUserId: "u-me",
    });

    expect(row.querySelector(MORE)).not.toBeNull();
  });
});
