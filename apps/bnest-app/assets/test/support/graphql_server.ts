// An in-process stand-in for the Bnest server a Family Chat room talks to:
// the `/api/graphql` endpoint (`request`) and the Absinthe subscription
// socket (`connectSocket`), both handed to the production `initRoom` in
// place of `fetch` and `phoenix`'s `Socket`.
//
// It answers with the server's own contracts rather than with whatever a
// scenario wants to see:
//
// - `familyChatMessages` keeps the cursor contract (ascending nodes,
//   exclusive `beforeId`/`afterId`, `hasOlder`/`hasNewer` from what the
//   cursor excluded);
// - `sendFamilyChatMessage` is idempotent per sender and `clientMessageId`,
//   resolves the quote the way `BnestApp.FamilyChat` does, and publishes the
//   commit to every live subscription;
// - every document is checked against a snapshot of the revision's schema
//   (`REVISION_SCHEMA`), so a document the server would refuse is refused
//   here too;
// - the socket speaks Absinthe's control-topic protocol: join
//   `__absinthe__:control`, push `"doc"`, receive `"subscription:data"` on a
//   channel named after the subscription id -- which is never joined.
//
// A scenario changes the network, never the answer: a member's sends can go
// unanswered (`offline`, a rejected fetch), be rejected with a GraphQL error
// code, or be held open. Everything the room asked for is recorded.

export interface Quote {
  id: string;
  senderKind: string;
  senderDisplayName: string;
  bodyPreview: string;
}

export interface ServerMessage {
  id: string;
  roomSlug: string;
  senderKind: string;
  senderId: string;
  senderDisplayName: string;
  body: string;
  committedAt: string;
  replyTo: Quote | null;
}

export interface Member {
  id: string;
  displayName: string;
}

export type SendOutcome = "commit" | "offline" | "hold" | { code: string };

export interface SendAttempt {
  at: number;
  memberId: string;
  clientMessageId: string;
  body: string;
  replyToMessageId: string | undefined;
  outcome: string;
}

export interface QueryRecord {
  memberId: string;
  operation: string;
  variables: Record<string, unknown>;
}

/** One request reaching the server, or its answer leaving it, in order. */
export interface WireEvent extends QueryRecord {
  kind: "request" | "response";
}

export interface PostOptions {
  body: string;
  sender?: Member;
  senderKind?: string;
  replyToMessageId?: string | undefined;
}

// The quote bound, restated rather than imported from the module under
// proof: this double stands in for `BnestApp.FamilyChat`'s server-side
// truncation, and a double that called the browser's own copy of the rule
// could never disagree with it.
const PREVIEW_BUDGET = 160;

/** The cursor contract's page sizes (`BnestApp.FamilyChat.Domain.Cursor`). */
const MIN_LIMIT = 1;
const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 50;

function serverPreview(body: string): string {
  const collapsed = body.replace(/\s+/gu, " ").trim();
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  const graphemes = [...segmenter.segment(collapsed)];
  if (graphemes.length <= PREVIEW_BUDGET) return collapsed;
  const kept = graphemes
    .slice(0, PREVIEW_BUDGET)
    .map((part) => part.segment)
    .join("");
  return `${kept}…`;
}

// --- Schema snapshot ------------------------------------------------------
//
// The revision's GraphQL surface the room's documents touch, copied from
// `lib/bnest_app_web/schema/types/family_chat_types.ex` and
// `web_push_types.ex` (and the root fields in `schema.ex`). Both the
// compatibility revision and the reply-aware one serve this same schema; the
// reply flag gates only what the browser asks for and renders.

type FieldSet = Record<string, string | null>;

const OBJECT_FIELDS: Record<string, FieldSet> = {
  FamilyChatMessage: {
    id: null,
    roomSlug: null,
    senderKind: null,
    senderId: null,
    senderDisplayName: null,
    body: null,
    committedAt: null,
    replyTo: "FamilyChatMessageQuote",
  },
  FamilyChatMessageQuote: {
    id: null,
    senderKind: null,
    senderDisplayName: null,
    bodyPreview: null,
  },
  FamilyChatMessageConnection: {
    nodes: "FamilyChatMessage",
    hasOlder: null,
    hasNewer: null,
  },
  WebPushConfiguration: { available: null, publicKey: null },
  WebPushSubscriptionStatus: { enabled: null, expirationTime: null },
};

interface RootField {
  type: string;
  args: Record<string, string>;
}

export const REVISION_SCHEMA: Record<string, RootField> = {
  familyChatMessages: {
    type: "FamilyChatMessageConnection",
    args: { roomSlug: "String!", beforeId: "ID", afterId: "ID", limit: "Int" },
  },
  sendFamilyChatMessage: {
    type: "FamilyChatMessage",
    args: {
      roomSlug: "String!",
      clientMessageId: "ID!",
      body: "String!",
      replyToMessageId: "ID",
    },
  },
  familyChatMessageCommitted: {
    type: "FamilyChatMessage",
    args: { roomSlug: "String!" },
  },
  webPushConfiguration: { type: "WebPushConfiguration", args: {} },
  currentWebPushSubscription: { type: "WebPushSubscriptionStatus", args: {} },
  upsertWebPushSubscription: {
    type: "WebPushSubscriptionStatus",
    args: { endpoint: "String!", p256dh: "String!", auth: "String!" },
  },
  disableCurrentWebPushSubscription: {
    type: "WebPushSubscriptionStatus",
    args: {},
  },
};

interface ParsedDocument {
  operation: string;
  variables: Record<string, string>;
  root: string;
  rootArgs: string[];
  selection: string;
}

/** Splits `a { b c { d } } e` into its top-level field entries. */
function topLevelFields(selection: string): { name: string; inner: string }[] {
  const fields: { name: string; inner: string }[] = [];
  let index = 0;
  while (index < selection.length) {
    const match = /\s*([A-Za-z_]\w*)\s*/uy;
    match.lastIndex = index;
    const found = match.exec(selection);
    if (!found) break;
    index = match.lastIndex;
    let inner = "";
    if (selection[index] === "{") {
      let depth = 0;
      const start = index;
      for (; index < selection.length; index += 1) {
        if (selection[index] === "{") depth += 1;
        if (selection[index] === "}") depth -= 1;
        if (depth === 0) break;
      }
      inner = selection.slice(start + 1, index);
      index += 1;
    }
    fields.push({ name: found[1] ?? "", inner });
  }
  return fields;
}

function validateSelection(type: string, selection: string): string[] {
  const known = OBJECT_FIELDS[type];
  if (!known) return [`unknown type ${type}`];
  return topLevelFields(selection).flatMap(({ name, inner }) => {
    if (!(name in known)) return [`${type} has no field ${name}`];
    const fieldType = known[name];
    if (fieldType) return validateSelection(fieldType, inner);
    return inner.trim() === "" ? [] : [`${type}.${name} has no subfields`];
  });
}

export function parseDocument(document: string): ParsedDocument {
  const header =
    /^\s*(?:query|mutation|subscription)\s+(\w+)\s*(?:\(([^)]*)\))?\s*\{\s*(\w+)\s*(?:\(([^)]*)\))?\s*\{([\s\S]*)\}\s*\}\s*$/u.exec(
      document,
    );
  if (!header) throw new Error(`unparseable document: ${document}`);
  const [
    ,
    operation = "",
    declared = "",
    root = "",
    args = "",
    selection = "",
  ] = header;
  const variables = Object.fromEntries(
    [...declared.matchAll(/\$(\w+)\s*:\s*([\w!]+)/gu)].map((part) => [
      part[1] ?? "",
      part[2] ?? "",
    ]),
  );
  const rootArgs = [...args.matchAll(/(\w+)\s*:\s*\$\w+/gu)].map(
    (part) => part[1] ?? "",
  );
  return { operation, variables, root, rootArgs, selection };
}

/** What the server's document validation would refuse, if anything. */
export function validateDocument(
  document: string,
  variables: Record<string, unknown>,
): string[] {
  const parsed = parseDocument(document);
  const field = REVISION_SCHEMA[parsed.root];
  if (!field) return [`unknown root field ${parsed.root}`];
  const errors = parsed.rootArgs
    .filter((arg) => !(arg in field.args))
    .map((arg) => `${parsed.root} has no argument ${arg}`);
  for (const [name, value] of Object.entries(variables)) {
    if (value !== undefined && !(name in parsed.variables)) {
      errors.push(`variable $${name} is not declared`);
    }
  }
  return [...errors, ...validateSelection(field.type, parsed.selection)];
}

// --- Socket ----------------------------------------------------------------

type Handler = (payload: Record<string, unknown>) => void;

interface FakePush {
  receive: (status: string, callback: (reply: never) => void) => FakePush;
}

/** One `receive` chain, answered on a later microtask as phoenix does. */
function reply(status: string, payload: unknown): FakePush {
  const callbacks = new Map<string, (reply: never) => void>();
  queueMicrotask(() => callbacks.get(status)?.(payload as never));
  const push: FakePush = {
    receive(expected, callback) {
      callbacks.set(expected, callback);
      return push;
    },
  };
  return push;
}

export interface SocketRecord {
  member: string;
  connects: number;
  disconnects: number;
  joins: string[];
  open: boolean;
}

interface SocketServer {
  records: SocketRecord[];
  deliver: (roomSlug: string, message: ServerMessage) => void;
  connectorFor: (member: Member) => (path: string) => Promise<unknown>;
  /** Severs every live socket the way a dropped network does: no close. */
  severAll: () => void;
}

interface SubscriptionEntry {
  socket: FakeSocket;
  roomSlug: string;
  document: string;
}

export class FakeSocket {
  readonly record: SocketRecord;
  readonly channels: { topic: string; handlers: Map<string, Handler> }[] = [];
  private readonly openCallbacks: (() => void)[] = [];
  private readonly joined = new Set<string>();

  constructor(
    member: Member,
    private readonly server: {
      subscribe: (entry: SubscriptionEntry) => string;
      dropSocket: (socket: FakeSocket) => void;
    },
  ) {
    this.record = {
      member: member.id,
      connects: 0,
      disconnects: 0,
      joins: [],
      open: false,
    };
  }

  onOpen(callback: () => void): void {
    this.openCallbacks.push(callback);
  }

  connect(): void {
    if (this.record.open) return;
    this.record.connects += 1;
    queueMicrotask(() => {
      this.record.open = true;
      // phoenix rejoins every channel it had joined when a socket reopens.
      if (this.record.connects > 1) {
        for (const topic of this.joined) this.record.joins.push(topic);
      }
      for (const callback of this.openCallbacks) callback();
    });
  }

  disconnect(callback?: () => void): void {
    this.record.disconnects += 1;
    this.record.open = false;
    this.server.dropSocket(this);
    callback?.();
  }

  sever(): void {
    this.record.open = false;
    this.server.dropSocket(this);
  }

  channel(topic: string, _params: unknown) {
    const entry = { topic, handlers: new Map<string, Handler>() };
    this.channels.push(entry);
    return {
      join: () => {
        this.record.joins.push(topic);
        this.joined.add(topic);
        return reply("ok", {});
      },
      push: (event: string, payload: Record<string, unknown>) => {
        if (event === "doc") {
          const subscriptionId = this.server.subscribe({
            socket: this,
            roomSlug: String(
              (payload["variables"] as Record<string, unknown>)["roomSlug"],
            ),
            document: String(payload["query"]),
          });
          return reply("ok", { subscriptionId });
        }
        return reply("ok", {});
      },
      on: (event: string, handler: Handler) => {
        entry.handlers.set(event, handler);
      },
      off: (event: string) => {
        entry.handlers.delete(event);
      },
    };
  }
}

function createSocketServer(): SocketServer {
  const records: SocketRecord[] = [];
  const subscriptions = new Map<string, SubscriptionEntry>();
  const sockets = new Set<FakeSocket>();
  let nextSubscription = 0;

  const server = {
    subscribe(entry: SubscriptionEntry): string {
      nextSubscription += 1;
      const id = `__absinthe__:doc:${nextSubscription}`;
      subscriptions.set(id, entry);
      return id;
    },
    dropSocket(socket: FakeSocket): void {
      for (const [id, entry] of subscriptions) {
        if (entry.socket === socket) subscriptions.delete(id);
      }
    },
  };

  return {
    records,
    deliver(roomSlug, message) {
      for (const [id, entry] of subscriptions) {
        if (entry.roomSlug !== roomSlug || !entry.socket.record.open) continue;
        const data = projectMessage(message, entry.document);
        for (const channel of entry.socket.channels) {
          if (channel.topic === id) {
            channel.handlers.get("subscription:data")?.({
              result: { data: { familyChatMessageCommitted: data } },
            });
          }
        }
      }
    },
    connectorFor(member) {
      return async () => {
        const socket = new FakeSocket(member, server);
        sockets.add(socket);
        records.push(socket.record);
        return socket;
      };
    },
    severAll() {
      for (const socket of sockets) socket.sever();
    },
  };
}

/** Only the fields the document selected, as a GraphQL server answers. */
function projectMessage(
  message: ServerMessage,
  document: string,
): Record<string, unknown> {
  const parsed = parseDocument(document);
  const selection =
    parsed.root === "familyChatMessages"
      ? (topLevelFields(parsed.selection).find((f) => f.name === "nodes")
          ?.inner ?? "")
      : parsed.selection;
  const record = message as unknown as Record<string, unknown>;
  return Object.fromEntries(
    topLevelFields(selection).map(({ name }) => [name, record[name] ?? null]),
  );
}

// --- Server ----------------------------------------------------------------

export interface GraphqlServer {
  messages: ServerMessage[];
  sendAttempts: SendAttempt[];
  queries: QueryRecord[];
  /** Every request and every answer, in the order they crossed the wire. */
  wire: WireEvent[];
  rejectedDocuments: string[];
  /** Members whose session logged out, in order. */
  logouts: string[];
  sockets: SocketServer;
  /** Push subscription bindings by member: enabled or not. */
  pushBindings: Map<string, boolean>;
  setSendOutcome: (memberId: string, outcome: SendOutcome) => void;
  /** Answers every held send, in order, with a commit. */
  releaseHeld: () => void;
  /** How many of a member's sends are being held unanswered. */
  heldFor: (memberId: string) => number;
  /**
   * What `DELETE /logout` does on the server: the session ends, and with it
   * the session's push binding (`Identity.logout`'s subscription revoker).
   */
  logout: (memberId: string) => void;
  post: (options: PostOptions) => ServerMessage;
  byId: (id: string) => ServerMessage | undefined;
  /** The message a member's send committed as, if it did. */
  committedFor: (
    memberId: string,
    clientMessageId: string,
  ) => ServerMessage | undefined;
  newest: () => ServerMessage | undefined;
  clientFor: (member: Member) => {
    request: (
      query: string,
      variables: Record<string, unknown>,
    ) => Promise<unknown>;
    connectSocket: (path: string) => Promise<unknown>;
  };
}

export function createGraphqlServer(options: {
  now: () => number;
  roomSlug?: string;
}): GraphqlServer {
  const roomSlug = options.roomSlug ?? "ruang-keluarga";
  const messages: ServerMessage[] = [];
  const committedByClientId = new Map<string, ServerMessage>();
  const outcomes = new Map<string, SendOutcome>();
  const held: { memberId: string; release: () => void }[] = [];
  const sockets = createSocketServer();
  let nextId = 1000;

  const server: GraphqlServer = {
    messages,
    sendAttempts: [],
    queries: [],
    wire: [],
    rejectedDocuments: [],
    logouts: [],
    sockets,
    pushBindings: new Map(),
    setSendOutcome: (memberId, outcome) => void outcomes.set(memberId, outcome),
    releaseHeld() {
      for (const entry of held.splice(0)) entry.release();
    },
    heldFor: (memberId) =>
      held.filter((entry) => entry.memberId === memberId).length,
    logout(memberId) {
      server.logouts.push(memberId);
      server.pushBindings.set(memberId, false);
    },
    post,
    byId: (id) => messages.find((message) => message.id === id),
    committedFor: (memberId, clientMessageId) =>
      committedByClientId.get(`${memberId}:${clientMessageId}`),
    newest: () => messages.at(-1),
    clientFor,
  };

  function post({
    body,
    sender,
    senderKind = "user",
    replyToMessageId,
  }: PostOptions): ServerMessage {
    nextId += 1;
    const quoted =
      replyToMessageId === undefined
        ? undefined
        : messages.find((message) => message.id === replyToMessageId);
    const message: ServerMessage = {
      id: String(nextId),
      roomSlug,
      senderKind,
      senderId: senderKind === "system" ? "system" : (sender?.id ?? "system"),
      senderDisplayName:
        senderKind === "system" ? "System" : (sender?.displayName ?? ""),
      body,
      committedAt: new Date(Date.UTC(2026, 0, 1, 0, 0, nextId)).toISOString(),
      replyTo: quoted
        ? {
            id: quoted.id,
            senderKind: quoted.senderKind,
            senderDisplayName: quoted.senderDisplayName,
            bodyPreview: serverPreview(quoted.body),
          }
        : null,
    };
    messages.push(message);
    sockets.deliver(roomSlug, message);
    return message;
  }

  function page(document: string, variables: Record<string, unknown>) {
    const limit = Number(variables["limit"] ?? DEFAULT_LIMIT);
    const beforeId = variables["beforeId"];
    const afterId = variables["afterId"];
    const bothCursors =
      beforeId !== undefined &&
      beforeId !== null &&
      afterId !== undefined &&
      afterId !== null;
    if (
      bothCursors ||
      !Number.isInteger(limit) ||
      limit < MIN_LIMIT ||
      limit > MAX_LIMIT
    ) {
      return {
        data: { familyChatMessages: null },
        errors: [
          {
            message: "Invalid input.",
            extensions: { code: "VALIDATION_FAILED" },
          },
        ],
      };
    }
    const ordered = [...messages].sort((a, b) => Number(a.id) - Number(b.id));
    let nodes: ServerMessage[];
    let hasOlder: boolean;
    let hasNewer: boolean;
    if (afterId !== undefined && afterId !== null) {
      const cursor = Number(afterId);
      const newer = ordered.filter((message) => Number(message.id) > cursor);
      nodes = newer.slice(0, limit);
      hasOlder = ordered.some((message) => Number(message.id) < cursor);
      hasNewer = newer.length > limit;
    } else {
      const upTo =
        beforeId === undefined || beforeId === null
          ? ordered
          : ordered.filter((message) => Number(message.id) < Number(beforeId));
      nodes = upTo.slice(Math.max(0, upTo.length - limit));
      hasOlder = upTo.length > limit;
      hasNewer = beforeId !== undefined && beforeId !== null;
    }
    return {
      data: {
        familyChatMessages: {
          nodes: nodes.map((message) => projectMessage(message, document)),
          hasOlder,
          hasNewer,
        },
      },
    };
  }

  async function send(
    member: Member,
    document: string,
    variables: Record<string, unknown>,
  ): Promise<unknown> {
    const clientMessageId = String(variables["clientMessageId"]);
    const outcome = outcomes.get(member.id) ?? "commit";
    const attempt: SendAttempt = {
      at: options.now(),
      memberId: member.id,
      clientMessageId,
      body: String(variables["body"]),
      replyToMessageId:
        variables["replyToMessageId"] === undefined
          ? undefined
          : String(variables["replyToMessageId"]),
      outcome: typeof outcome === "string" ? outcome : outcome.code,
    };
    server.sendAttempts.push(attempt);

    if (outcome === "offline") throw new TypeError("Failed to fetch");
    if (typeof outcome === "object") {
      return {
        data: { sendFamilyChatMessage: null },
        errors: [{ message: outcome.code, extensions: { code: outcome.code } }],
      };
    }
    if (outcome === "hold") {
      await new Promise<void>((resolve) =>
        held.push({ memberId: member.id, release: resolve }),
      );
    }

    const key = `${member.id}:${clientMessageId}`;
    const committed =
      committedByClientId.get(key) ??
      post({
        body: attempt.body,
        sender: member,
        replyToMessageId: attempt.replyToMessageId,
      });
    committedByClientId.set(key, committed);
    return {
      data: { sendFamilyChatMessage: projectMessage(committed, document) },
    };
  }

  function clientFor(member: Member) {
    return {
      async request(query: string, variables: Record<string, unknown>) {
        // A real response never arrives within the turn that sent it.
        await new Promise((resolve) => setTimeout(resolve, 0));
        const { operation } = parseDocument(query);
        const record = { memberId: member.id, operation, variables };
        server.queries.push(record);
        server.wire.push({ ...record, kind: "request" });
        try {
          return await answer(member, query, variables, operation);
        } finally {
          server.wire.push({ ...record, kind: "response" });
        }
      },
      connectSocket: sockets.connectorFor(member),
    };
  }

  async function answer(
    member: Member,
    query: string,
    variables: Record<string, unknown>,
    operation: string,
  ): Promise<unknown> {
    const refused = validateDocument(query, variables);
    if (refused.length > 0) {
      server.rejectedDocuments.push(...refused);
      return {
        errors: refused.map((message) => ({
          message,
          extensions: { code: "GRAPHQL_VALIDATION_FAILED" },
        })),
      };
    }
    switch (operation) {
      case "FamilyChatMessages":
        return page(query, variables);
      case "SendFamilyChatMessage":
        return send(member, query, variables);
      case "WebPushConfiguration":
        return {
          data: {
            webPushConfiguration: {
              available: true,
              publicKey: "BPublicKeyForTests",
            },
          },
        };
      case "CurrentWebPushSubscription":
        return {
          data: {
            currentWebPushSubscription: {
              enabled: server.pushBindings.get(member.id) === true,
              expirationTime: null,
            },
          },
        };
      case "UpsertWebPushSubscription":
        server.pushBindings.set(member.id, true);
        return {
          data: {
            upsertWebPushSubscription: {
              enabled: true,
              expirationTime: null,
            },
          },
        };
      case "DisableCurrentWebPushSubscription":
        server.pushBindings.set(member.id, false);
        return {
          data: {
            disableCurrentWebPushSubscription: {
              enabled: false,
              expirationTime: null,
            },
          },
        };
      default:
        throw new Error(`the server double has no ${operation}`);
    }
  }

  return server;
}
