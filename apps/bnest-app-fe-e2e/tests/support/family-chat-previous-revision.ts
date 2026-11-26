import { readFileSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { buildSchema, Kind, parse, print, validate } from "graphql";
import type { DocumentNode } from "graphql";
import { waitForRoomReady } from "./family-chat-resume";
import { repositoryRoot } from "./routed-rollout-env";

// Support for the earlier-revision scenarios in family-chat-rollback-floor.steps.ts: the held browser's GraphQL wire
// (HTTP and socket), which replays the previous bundle's documents and judges each one against the frozen schema.

type Root = { kind: string; type: string; args: Record<string, string> };

interface Schema {
  objects: Record<string, Record<string, string | null>>;
  roots: Record<string, Root>;
}

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
  floorRefusals: [] as { operation: string; reason: string }[],
};

export function refusals(): string[] {
  return previousRevisionTraffic.floorRefusals.map(
    (r) => `${r.operation}: ${r.reason}`,
  );
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

const pairs = (record: Record<string, string | null>): string[] =>
  Object.entries(record).map(([n, t]) => `${n}: ${t ?? "Scalar"}`);

/**
 * The rolled-back schema as SDL. Untyped scalars are `Scalar`. List wrapping is not represented, and it does not
 * change validation of selections or argument types.
 */
function schemaSdl(schema: Schema): string {
  const rootType = (kind: string, name: string): string[] => {
    const fields = Object.entries(schema.roots)
      .filter(([, root]) => root.kind === kind)
      .map(([field, root]) => {
        const args = pairs(root.args);
        return `${field}${args.length > 0 ? `(${args.join(", ")})` : ""}: ${root.type}`;
      });
    return fields.length > 0 ? [`type ${name} { ${fields.join(", ")} }`] : [];
  };
  const objects = Object.entries(schema.objects).map(
    ([name, fields]) => `type ${name} { ${pairs(fields).join(", ")} }`,
  );
  return [
    "scalar Scalar",
    ...objects,
    ...rootType("query", "Query"),
    ...rootType("mutation", "Mutation"),
    ...rootType("subscription", "Subscription"),
  ].join("\n");
}

/**
 * What the rolled-back schema refuses in one document: graphql-js validation, plus one operation with one root field,
 * each variable sent declared, and each bound variable declaring its argument's type exactly.
 */
export function judgeDocument(
  query: string,
  variables: Record<string, unknown>,
  schema: Schema,
): string[] {
  let document: DocumentNode;
  try {
    document = parse(query);
  } catch (error) {
    return [error instanceof Error ? error.message : String(error)];
  }
  const operation =
    document.definitions.length === 1 ? document.definitions[0] : undefined;
  if (operation?.kind !== Kind.OPERATION_DEFINITION)
    return ["one operation only"];
  const roots = operation.selectionSet.selections;
  const [root] = roots;
  if (roots.length !== 1) return [`${roots.length} root fields, not one`];
  if (root?.kind !== Kind.FIELD) return ["the root selection is not a field"];
  const vars = operation.variableDefinitions ?? [];
  const declared = new Map(
    vars.map((d) => [d.variable.name.value, print(d.type)]),
  );
  const args = schema.roots[root.name.value]?.args ?? {};
  const expected = new Map(Object.entries(args));
  const errors: string[] = [];
  for (const arg of root.arguments ?? []) {
    const want = expected.get(arg.name.value);
    if (arg.value.kind !== Kind.VARIABLE) continue;
    const have = declared.get(arg.value.name.value);
    if (want !== undefined && have !== undefined && have !== want)
      errors.push(
        `${root.name.value}.${arg.name.value} is ${want}, not ${have}`,
      );
  }
  for (const [name, value] of Object.entries(variables))
    if (value !== undefined && !declared.has(name))
      errors.push(`$${name} is sent but not declared`);
  const validation = validate(buildSchema(schemaSdl(schema)), document);
  return [...errors, ...validation.map((error) => error.message)];
}

/** The request as it goes out: the previous bundle's text while the replay is armed, judged while judging is armed. */
function onTheWire(body: Partial<Request>, wire: Wire): Request {
  const request = { query: body.query ?? "", variables: body.variables ?? {} };
  const operation = OPERATION.exec(request.query)?.[1] ?? "";
  const documents = PREVIOUS_REVISION.previousClient.documents;
  const frozen =
    wire.replay && Object.hasOwn(documents, operation)
      ? documents[operation]
      : undefined;
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
  if (frozen) {
    const count = previousRevisionTraffic.rewritten.get(operation) ?? 0;
    previousRevisionTraffic.rewritten.set(operation, count + 1);
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

/** A Phoenix v2 frame is [join_ref, ref, topic, event, payload]; only the control topic's "doc" push carries a document. */
function frameOnWire(message: string | Buffer, wire: Wire): string | Buffer {
  let frame: unknown;
  try {
    frame = JSON.parse(String(message));
  } catch {
    return message;
  }
  if (!Array.isArray(frame) || frame[2] !== CONTROL_TOPIC || frame[3] !== "doc")
    return message;
  const payload = (frame[4] ?? {}) as Partial<Request>;
  const sent = onTheWire(payload, wire);
  return JSON.stringify([...frame.slice(0, 4), { ...payload, ...sent }]);
}

/** Routes one page's GraphQL traffic, HTTP and socket, once. */
async function wirePage(page: Page): Promise<Wire> {
  const known = wires.get(page);
  if (known !== undefined) return known;
  const wire: Wire = { replay: false, judge: false };
  wires.set(page, wire);
  await page.route(GRAPHQL_ROUTE, (route) => {
    if (!wire.replay && !wire.judge) return route.continue();
    const posted = route.request().postData() ?? "{}";
    const body = JSON.parse(posted) as Partial<Request>;
    const sent = onTheWire(body, wire);
    return route.continue({ postData: JSON.stringify({ ...body, ...sent }) });
  });
  await page.routeWebSocket(SOCKET_ROUTE, (socket) => {
    const server = socket.connectToServer();
    socket.onMessage((message) => server.send(frameOnWire(message, wire)));
  });
  return wire;
}

/**
 * The page's GraphQL requests go out as the frozen previous bundle sends them, HTTP and socket alike. Install it before
 * the navigation that loads the page's history and subscription: a request already sent is not rewritten.
 */
export async function sendPreviousBundleDocuments(page: Page): Promise<void> {
  const wire = await wirePage(page);
  previousRevisionTraffic.rewritten.clear();
  wire.replay = true;
}

/** Judges each document the page sends from now on against the frozen rolled-back schema, as it goes out. */
export async function judgeAgainstRolledBackSlot(page: Page): Promise<void> {
  const wire = await wirePage(page);
  previousRevisionTraffic.floorRefusals = [];
  wire.judge = true;
}

export function navigationCount(page: Page): Promise<number> {
  return page.evaluate(() => performance.getEntriesByType("navigation").length);
}

/**
 * Also the gate before any reload that follows a promotion: the room loads its
 * history once and never retries, so a reload into the churn window sits at
 * "booting" for good -- the held page, still open, can ask first.
 *
 * A promotion swaps the process behind the routed port, and `/health/ready`
 * answering with the new revision does not mean that process can reach SQLite
 * yet: the repo's pool can still be tearing down, and a request that lands in
 * that window comes back `Internal Server Error` with
 * `DBConnection.Holder.checkout ... (EXIT) shutdown` in the slot's log. It is
 * the harness's slot churn, not the room -- a plain send fails there just as a
 * reply does. So wait until the routed slot will actually answer a
 * database-backed read before asking it to commit anything.
 */
export async function waitForRoutedReads(
  page: Page,
  revision: string,
): Promise<void> {
  await expect
    .poll(
      () =>
        page.evaluate(async (expected) => {
          const probe = async (): Promise<boolean> => {
            const response = await fetch("/api/graphql", {
              method: "POST",
              credentials: "same-origin",
              headers: {
                "content-type": "application/json",
                "x-csrf-token":
                  document.querySelector<HTMLMetaElement>(
                    "meta[name='csrf-token']",
                  )?.content ?? "",
              },
              body: JSON.stringify({
                query:
                  "query Probe($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug, limit: 1) { nodes { id } } }",
                variables: { roomSlug: "ruang-keluarga" },
              }),
            });
            if (!response.ok) return false;
            // Answered by the revision just routed, not one still draining.
            if (response.headers.get("x-bnest-revision") !== expected)
              return false;
            const payload = (await response.json()) as { errors?: unknown };
            return payload.errors === undefined;
          };
          // Side by side, so the browser's other pooled connections to the
          // origin are asked too: the next real request may not reuse this one.
          const answers = await Promise.all(
            Array.from({ length: 6 }, () => probe().catch(() => false)),
          );
          return answers.every(Boolean);
        }, revision),
      { timeout: 20_000 },
    )
    .toBe(true);
}

/**
 * Reloads into the routed room. The page itself comes from the slot just
 * routed, and a slot still settling can answer that one request with an error
 * page that has no room in it; reloading again is what a person would do.
 */
export async function reloadRoutedRoom(page: Page): Promise<void> {
  const room = page.locator('[data-role="family-chat-room"]');
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop -- each reload is judged on its own result.
    await page.reload();
    // eslint-disable-next-line no-await-in-loop -- see above.
    const loaded = await room
      .waitFor({ state: "attached", timeout: 5_000 })
      .then(() => true)
      .catch(() => false);
    if (loaded) break;
  }
  await waitForRoomReady(page);
}
