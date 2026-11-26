import { buildSchema, Kind, parse, validate } from "graphql";
import type { DocumentNode } from "graphql";

// The judgement behind the earlier-revision wire in family-chat-previous-revision.ts: what the rolled-back schema
// refuses in one document, and what a live answer to a replayed document gets wrong. Each function is pure, so the
// wire only records what they return.

type Root = { kind: string; type: string; args: Record<string, string> };

export interface Schema {
  objects: Record<string, Record<string, string | null>>;
  roots: Record<string, Root>;
}

/** One replayed document that was refused, with its operation and the reason. */
export interface Refusal {
  operation: string;
  reason: string;
}

const pairs = (record: Record<string, string | null>): string[] =>
  Object.entries(record).map(([n, t]) => `${n}: ${t ?? "Scalar"}`);

/**
 * The rolled-back schema as SDL. Untyped scalars are `Scalar`. Object field types are given by name, so their list
 * wrapping is not represented; it does not change the validation of selections. Argument types are passed as written.
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
 * What the rolled-back schema refuses in one document: graphql-js validation, which also judges each variable's type
 * against the argument it binds to, plus one operation with one root field, and each variable sent declared.
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
  const declared = new Set(
    (operation.variableDefinitions ?? []).map((d) => d.variable.name.value),
  );
  const errors: string[] = [];
  for (const [name, value] of Object.entries(variables))
    if (value !== undefined && !declared.has(name))
      errors.push(`$${name} is sent but not declared`);
  // graphql-js judges each variable's type against the argument it binds to (VariablesInAllowedPosition).
  const validation = validate(buildSchema(schemaSdl(schema)), document);
  return [...errors, ...validation.map((error) => error.message)];
}

/** A Phoenix v2 frame is [join_ref, ref, topic, event, payload]. Undefined when the message is not a JSON array. */
export function parseFrame(message: string | Buffer): unknown[] | undefined {
  try {
    const frame: unknown = JSON.parse(String(message));
    return Array.isArray(frame) ? frame : undefined;
  } catch {
    return undefined;
  }
}

/**
 * What a live HTTP answer to a replayed document gets wrong: a non-OK status, an "errors" key, or no data. It is
 * returned, not thrown, so the Then that reads it fails with the list.
 */
export function liveProblems(
  ok: boolean,
  status: number,
  text: string,
): string[] {
  if (!ok) return [`HTTP ${status}`];
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return ["the body is not JSON"];
  }
  if (typeof body !== "object" || body === null)
    return ["the body is not an object"];
  if ("errors" in body) return [`errors ${JSON.stringify(body.errors)}`];
  if (!("data" in body) || typeof body.data !== "object" || body.data === null)
    return ["no data"];
  return [];
}

/**
 * The reply to a replayed document's push, when it did not succeed: a status other than "ok", or an "errors" key in
 * the response. `pushed` maps each replayed push's ref on this socket to its operation, so only those replies count.
 */
export function replyRefusals(
  message: string | Buffer,
  pushed: ReadonlyMap<string, string>,
): Refusal[] {
  const frame = parseFrame(message);
  if (frame?.[3] !== "phx_reply") return [];
  const operation = pushed.get(String(frame[1]));
  if (operation === undefined) return [];
  const { status, response } = (frame[4] ?? {}) as {
    status?: unknown;
    response?: unknown;
  };
  const errored =
    typeof response === "object" && response !== null && "errors" in response;
  if (status === "ok" && !errored) return [];
  return [
    {
      operation,
      reason: `socket reply ${String(status)} ${JSON.stringify(response)}`,
    },
  ];
}

/**
 * The push of a subscription's result, when the result carries an "errors" key. A message that is not a Phoenix frame,
 * or a frame that is not a subscription push, returns nothing.
 */
export function subscriptionRefusals(message: string | Buffer): string[] {
  const frame = parseFrame(message);
  if (frame?.[3] !== "subscription:data") return [];
  const { result } = (frame[4] ?? {}) as { result?: unknown };
  if (typeof result === "object" && result !== null && "errors" in result)
    return [`subscription:data errors ${JSON.stringify(result.errors)}`];
  return [];
}
