// Pure helpers for the reads a test makes through a secondary `mix run -e` process (ADR 001, section 2). The Elixir
// code names only a record kind and a user id that this module validates, so no test value reaches the code text
// except those two checked values. Both E2E projects keep a byte-identical copy (shared-support-parity.test.mts), so
// the read and its parser cannot drift apart.

export type RecordKind = "account" | "chat" | "sifat_allah" | "theme";

// A record that may be absent. A missing record carries the server's read error, such as `missing`.
export type RecordState =
  | { present: true; record: Record<string, unknown> }
  | { present: false; reason: string };

export const instanceReadMarker = "BNEST_E2E_INSTANCE_READ=";

export const instanceReadPrelude: readonly string[] = [
  "alias BnestApp.Storage.Adapters.SqliteCoordinator",
  "alias BnestApp.SqliteRepo",
  ":ok = SqliteCoordinator.ensure_started!()",
];

const recordKinds = new Set<RecordKind>([
  "account",
  "chat",
  "sifat_allah",
  "theme",
]);
const userIdPattern = /^[A-Za-z0-9_-]{1,128}$/u;

// The Elixir string literal of a validated user id. The check keeps quotes and escapes out of the code text.
export function quotedUserId(userId: string): string {
  if (!userIdPattern.test(userId)) {
    throw new Error("the user id is not a safe record key");
  }
  return `"${userId}"`;
}

// The Elixir code of one record read through the same validated read the server makes: the routed records repository,
// which reads SQLite for a SQLite-primary instance and the instance's flat root for a flat-primary one. It prints the
// state as JSON on the marked line, with the server's reason when the record is absent.
export function recordReadExpression(kind: RecordKind, userId: string): string {
  if (!recordKinds.has(kind)) {
    throw new Error("the record kind is not readable");
  }
  return [
    ...instanceReadPrelude,
    `result = case BnestApp.Storage.Records.read(:${kind}, ${quotedUserId(userId)}) do`,
    `  {:ok, record} -> %{"present" => true, "record" => record}`,
    `  {:error, reason} -> %{"present" => false, "reason" => Atom.to_string(reason)}`,
    "end",
    `IO.puts("${instanceReadMarker}" <> Jason.encode!(result))`,
  ].join("\n");
}

// The text after the marker on the first marked line of a process's output.
export function markedPayload(stdout: string): string {
  const line = stdout
    .split("\n")
    .find((candidate) => candidate.startsWith(instanceReadMarker));
  if (line === undefined) throw new Error("instance record marker was absent");
  return line.slice(instanceReadMarker.length);
}

// The state the server reported for one record. Any other shape fails, so a step never compares against a guess.
export function parseRecordState(stdout: string): RecordState {
  const parsed: unknown = JSON.parse(markedPayload(stdout));
  if (!isRecord(parsed)) {
    throw new TypeError("the record read did not report a record state");
  }
  const record = parsed["record"];
  if (parsed["present"] === true && isRecord(record)) {
    return { present: true, record };
  }
  const reason = parsed["reason"];
  if (parsed["present"] === false && typeof reason === "string") {
    return { present: false, reason };
  }
  throw new TypeError("the record read did not report a record state");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
