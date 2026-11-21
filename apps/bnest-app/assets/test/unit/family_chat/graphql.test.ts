// Plain Vitest unit coverage for `js/family_chat/graphql.js`'s subscription
// handshake (tech-doc 006's File Impact list). The room joins one topic, the
// control channel. A per-message subscription is only listened to: after
// `subscribe` resolves, and again after a reconnect, no channel other than the
// control channel is joined. Every collaborator is a double, so no socket,
// clock, network, or environment variable is touched.

import { describe, expect, it } from "vitest";
import { createSubscriptionClient } from "../../../js/family_chat/graphql.js";

const CONTROL_TOPIC = "__absinthe__:control";
const QUERY = "subscription { familyMessageAdded { id } }";

interface Receiver {
  receive(status: string, callback: (payload?: unknown) => void): Receiver;
}

/** A push or join reply that answers "ok" with `payload` and ignores every other status. */
function okReply(payload?: unknown): Receiver {
  const reply: Receiver = {
    receive(status, callback) {
      if (status === "ok") callback(payload);
      return reply;
    },
  };
  return reply;
}

class FakeChannel {
  readonly listeners = new Set<string>();

  constructor(
    readonly topic: string,
    private readonly socket: FakeSocket,
  ) {}

  join(): Receiver {
    this.socket.joins.push(this.topic);
    return okReply();
  }

  /** The control channel answers "doc" with a subscription id, one per call. */
  push(event: string): Receiver {
    if (event !== "doc") return okReply();
    this.socket.subscriptions += 1;
    const subscriptionId = `subscription-${this.socket.subscriptions}`;
    return okReply({ subscriptionId });
  }

  on(event: string): void {
    this.listeners.add(event);
  }

  off(event: string): void {
    this.listeners.delete(event);
  }
}

class FakeSocket {
  readonly joins: string[] = [];
  readonly channels: FakeChannel[] = [];
  subscriptions = 0;
  private readonly openListeners: Array<() => void> = [];

  onOpen(callback: () => void): void {
    this.openListeners.push(callback);
  }

  connect(): void {}

  disconnect(): void {}

  channel(topic: string): FakeChannel {
    const channel = new FakeChannel(topic, this);
    this.channels.push(channel);
    return channel;
  }

  /** The transport opens, as phoenix does on the first connect and after every drop. */
  open(): void {
    for (const listener of this.openListeners) listener();
  }
}

function clientOver(socket: FakeSocket) {
  return createSubscriptionClient({
    connectSocket: async () => socket as never,
  });
}

describe("createSubscriptionClient / subscribe", () => {
  it("joins the control channel alone when a subscription opens", async () => {
    const socket = new FakeSocket();
    const client = clientOver(socket);

    await client.subscribe(QUERY, {}, () => {});

    expect(socket.joins).toEqual([CONTROL_TOPIC]);
  });

  it("only listens on the per-message subscription channel it opens", async () => {
    const socket = new FakeSocket();
    const client = clientOver(socket);

    await client.subscribe(QUERY, {}, () => {});

    const dataChannels = socket.channels.filter(
      (channel) => channel.topic !== CONTROL_TOPIC,
    );
    expect(dataChannels.map((channel) => channel.topic)).toEqual([
      "subscription-1",
    ]);
    expect(dataChannels[0]?.listeners.has("subscription:data")).toBe(true);
  });

  it("still joins only the control channel after a reconnect", async () => {
    const socket = new FakeSocket();
    const client = clientOver(socket);
    let reconnects = 0;
    client.onReconnect(() => {
      reconnects += 1;
    });

    await client.subscribe(QUERY, {}, () => {});
    socket.open();
    socket.open();
    await client.subscribe(QUERY, {}, () => {});

    expect(reconnects).toBe(1);
    expect(socket.joins).toEqual([CONTROL_TOPIC]);
  });

  it("listens on the new subscription channel after a reconnect, without joining it", async () => {
    const socket = new FakeSocket();
    const client = clientOver(socket);

    await client.subscribe(QUERY, {}, () => {});
    socket.open();
    socket.open();
    await client.subscribe(QUERY, {}, () => {});

    const listening = socket.channels
      .filter((channel) => channel.listeners.has("subscription:data"))
      .map((channel) => channel.topic);
    expect(listening).toEqual(["subscription-1", "subscription-2"]);
    expect(socket.joins).not.toContain("subscription-2");
  });
});
