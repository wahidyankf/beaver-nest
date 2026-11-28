import { readFileSync } from "node:fs";
import path from "node:path";
import { expect, type Page, type Route } from "@playwright/test";
import {
  judgeDocument,
  liveProblems,
  parseFrame,
  type Refusal,
  replyRefusals,
  subscriptionRefusals,
  type Schema,
} from "./family-chat-previous-revision-judge";
import { repositoryRoot } from "./routed-rollout-env";

// Support for the earlier-revision scenarios in family-chat-rollback-floor.steps.ts: the held browser's GraphQL wire
// (HTTP and socket) replays the previous bundle's documents, judges each against the frozen schema, and logs answers.

const FIXTURE =
  "apps/bnest-app/assets/test/support/family_chat_previous_revision.json";
const PREVIOUS_REVISION = JSON.parse(
  readFileSync(path.join(repositoryRoot, FIXTURE), "utf8"),
) as {
  previousClient: {
    documents: Record<string, { document: string; variables: string[] }>;
  };
  rolledBackSlot: { schema: Schema };
};

/** What the held page put on the wire, and what the rolled-back schema refused. */
export const previousRevisionTraffic = {
  /** Documents sent as the previous bundle's text, counted by operation name. */
  rewritten: new Map<string, number>(),
  /** Each refused document, with its operation and the reason. */
  floorRefusals: [] as Refusal[],
  /** Each document, or subscription push, the live server answered wrongly, over HTTP or the socket. */
  liveErrors: [] as Refusal[],
  /** Each replayed or judged operation the live server has answered, over HTTP or the socket. */
  answered: new Set<string>(),
};

export function refusals(): string[] {
  return previousRevisionTraffic.floorRefusals.map(
    (r) => `${r.operation}: ${r.reason}`,
  );
}

/** The live server's wrong answers to replayed documents, in the form the steps print. */
export function liveRefusals(): string[] {
  return previousRevisionTraffic.liveErrors.map(
    (r) => `${r.operation}: ${r.reason}`,
  );
}

/** Waits for the live server's answer to the page's subscription, which can land after a step starts, then expects no live refusal. */
export async function expectLiveServerAnswered(wording: string): Promise<void> {
  await expect
    .poll(
      () => previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
      {
        message: `the live server never answered the ${wording} FamilyChatMessageCommitted subscription`,
        timeout: 15_000,
      },
    )
    .toBe(true);
  const live = liveRefusals();
  expect(
    live,
    `the live server refused a replayed previous-bundle document: ${live.join("; ")}`,
  ).toEqual([]);
}

const GRAPHQL_ROUTE = "**/api/graphql";
const SOCKET_ROUTE = /\/api\/graphql\/socket\/websocket/u;
// Absinthe's control topic: its "doc" push carries a subscription document.
const CONTROL_TOPIC = "__absinthe__:control";
const OPERATION = /^\s*(?:query|mutation|subscription)\s+(\w+)/u;

type Request = { query: string; variables: Record<string, unknown> };
/** Armed per page: `replay` sends the previous bundle's text, `judge` records each refusal. */
type Wire = { replay: boolean; judge: boolean };
const wires = new WeakMap<Page, Wire>();

/** The operation whose document the previous bundle's text replaces, when replay is armed and the bundle has it. */
function replayedOperation(query: string, wire: Wire): string | undefined {
  const operation = OPERATION.exec(query)?.[1];
  if (!wire.replay || operation === undefined) return undefined;
  return Object.hasOwn(PREVIOUS_REVISION.previousClient.documents, operation)
    ? operation
    : undefined;
}

/** The name a document is recorded under when it is judged or replayed; undefined for a document nothing watches. */
function watchedOperation(query: string, wire: Wire): string | undefined {
  const replayed = replayedOperation(query, wire);
  if (replayed !== undefined || !wire.judge) return replayed;
  return OPERATION.exec(query)?.[1] ?? "(unnamed)";
}

/** The request as it goes out: the previous bundle's text while the replay is armed, judged while judging is armed. */
function onTheWire(body: Partial<Request>, wire: Wire): Request {
  const request = { query: body.query ?? "", variables: body.variables ?? {} };
  const operation = OPERATION.exec(request.query)?.[1] ?? "";
  const replayed = replayedOperation(request.query, wire);
  const frozen =
    replayed === undefined
      ? undefined
      : PREVIOUS_REVISION.previousClient.documents[replayed];
  const sent = frozen
    ? {
        query: frozen.document,
        variables: Object.fromEntries(
          Object.entries(request.variables).filter(([name]) =>
            frozen.variables.includes(name),
          ),
        ),
      }
    : request;
  if (replayed !== undefined) {
    const count = previousRevisionTraffic.rewritten.get(replayed) ?? 0;
    previousRevisionTraffic.rewritten.set(replayed, count + 1);
  }
  if (wire.judge) {
    const reasons = judgeDocument(
      sent.query,
      sent.variables,
      PREVIOUS_REVISION.rolledBackSlot.schema,
    );
    if (reasons.length > 0)
      previousRevisionTraffic.floorRefusals.push({
        operation,
        reason: reasons.join("; "),
      });
  }
  return sent;
}

// A Phoenix v2 frame is [join_ref, ref, topic, event, payload]; only the control topic's "doc" push carries a document.
// A judged or replayed push's ref is kept against its operation, so the reply that answers it can be checked.
function frameOnWire(
  message: string | Buffer,
  wire: Wire,
  pushed: Map<string, string>,
): string | Buffer {
  const frame = parseFrame(message);
  if (frame === undefined || frame[2] !== CONTROL_TOPIC || frame[3] !== "doc")
    return message;
  const payload = (frame[4] ?? {}) as Partial<Request>;
  const watched = watchedOperation(payload.query ?? "", wire);
  if (watched !== undefined) pushed.set(String(frame[1]), watched);
  const sent = onTheWire(payload, wire);
  return JSON.stringify([...frame.slice(0, 4), { ...payload, ...sent }]);
}

/** Sends a judged or replayed document to the live server, and answers the page with its answer. */
async function answerLive(route: Route, postData: string, watched: string) {
  // The live server answers judged and replayed documents unchanged; a fault is recorded for the Then, never thrown.
  // The readiness probe is judged and answered but not recorded: waitForRoutedReads already requires its six answers.
  const recorded = watched !== "Probe";
  const live = await route.fetch({ postData }).catch((error: unknown) => {
    if (recorded)
      previousRevisionTraffic.liveErrors.push({
        operation: watched,
        reason: `no answer: ${String(error)}`,
      });
    if (recorded) previousRevisionTraffic.answered.add(watched);
    return null;
  });
  if (live === null) return route.abort();
  const text = await live.text().catch(() => "");
  if (recorded)
    previousRevisionTraffic.liveErrors.push(
      ...liveProblems(live.ok(), live.status(), text).map((reason) => ({
        operation: watched,
        reason,
      })),
    );
  if (recorded) previousRevisionTraffic.answered.add(watched);
  return route.fulfill({ response: live });
}

/** Routes one page's GraphQL traffic, HTTP and socket, once. */
async function wirePage(page: Page): Promise<Wire> {
  const known = wires.get(page);
  if (known !== undefined) return known;
  const wire: Wire = { replay: false, judge: false };
  wires.set(page, wire);
  await page.route(GRAPHQL_ROUTE, (route) => {
    if (!wire.replay && !wire.judge) return route.continue();
    const body = JSON.parse(
      route.request().postData() ?? "{}",
    ) as Partial<Request>;
    const postData = JSON.stringify({ ...body, ...onTheWire(body, wire) });
    const watched = watchedOperation(body.query ?? "", wire);
    if (watched === undefined) return route.continue({ postData });
    return answerLive(route, postData, watched);
  });
  await page.routeWebSocket(SOCKET_ROUTE, (socket) => {
    const server = socket.connectToServer();
    // This connection's judged or replayed pushes, by ref, so each reply is matched to the operation it answers.
    const pushed = new Map<string, string>();
    socket.onMessage((message) =>
      server.send(frameOnWire(message, wire, pushed)),
    );
    // Taking over the server's messages stops Playwright passing them on, so each is judged and then sent on.
    server.onMessage((message) => {
      const frame = parseFrame(message);
      const replied =
        frame?.[3] === "phx_reply" ? pushed.get(String(frame[1])) : undefined;
      if (replied !== undefined) previousRevisionTraffic.answered.add(replied);
      previousRevisionTraffic.liveErrors.push(
        ...replyRefusals(message, pushed),
        ...subscriptionRefusals(message).map((reason) => ({
          operation: "subscription",
          reason,
        })),
      );
      socket.send(message);
    });
  });
  return wire;
}

/**
 * Routes the page's GraphQL traffic without changing or judging any of it yet. Playwright routes a socket through the
 * patch it injects into each new document, so a page already loaded keeps opening its sockets unrouted: install this
 * before the navigation whose document is to be judged, and a held page's later reconnects are then seen.
 */
export async function routeGraphqlWire(page: Page): Promise<void> {
  await wirePage(page);
}

/**
 * The page's GraphQL requests go out as the frozen previous bundle sends them, HTTP and socket alike. Install it before
 * the navigation that loads the page's history and subscription: a request already sent is not rewritten.
 */
export async function sendPreviousBundleDocuments(page: Page): Promise<void> {
  const wire = await wirePage(page);
  previousRevisionTraffic.rewritten.clear();
  previousRevisionTraffic.liveErrors = [];
  previousRevisionTraffic.answered.clear();
  wire.replay = true;
}

/** Judges each document the page sends from now on against the frozen rolled-back schema, and checks its live answer. */
export function judgeAgainstRolledBackSlot(page: Page): void {
  const wire = wires.get(page);
  if (wire === undefined)
    throw new Error(
      "install the wire before the page loads (routeGraphqlWire): a route added to a loaded page never sees its sockets, so nothing would be judged",
    );
  previousRevisionTraffic.floorRefusals = [];
  previousRevisionTraffic.liveErrors = [];
  previousRevisionTraffic.answered.clear();
  wire.judge = true;
}
