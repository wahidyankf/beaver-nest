import { currentInstance } from "./active-instance.mts";
import { countFlatImports } from "./flat-import-count.mts";
import { runLiveMix } from "./live-sqlite";
import {
  instanceReadPrelude,
  instanceReadMarker,
  markedPayload,
  parseRecordState,
  quotedUserId,
  recordReadExpression,
  type RecordKind,
  type RecordState,
} from "./instance-record-read.mts";

// Reads one of the current instance's records through production code, in a secondary `mix run -e` process
// (ADR 001, section 2: reads that tests still make through Elixir stay on `mix run -e`, now instance-aware). The
// expression and its parser live in instance-record-read.mts, which the FE project keeps identical.

export type { RecordKind, RecordState } from "./instance-record-read.mts";

// The record the server holds for one user, or the reason it holds none.
export function instanceRecordState(kind: RecordKind, userId: string): RecordState {
  const result = runLiveMix(recordReadExpression(kind, userId));
  if (result.status !== 0) {
    throw new Error(`instance record read failed: ${result.stderr}`);
  }
  return parseRecordState(result.stdout);
}

// The record of a user that must exist. A missing record fails the caller, so a step never compares against nothing.
export function instanceRecord(
  kind: RecordKind,
  userId: string,
): Record<string, unknown> {
  const state = instanceRecordState(kind, userId);
  if (!state.present) {
    throw new Error(`the ${kind} record is absent: ${state.reason}`);
  }
  return state.record;
}

// How many browser import envelopes the server has preserved for one user. A flat-primary instance keeps them in
// its flat root, so they are counted there; a SQLite-primary instance reads the record table the server owns,
// through a bound parameter for the record type and the owner.
export function importCount(userId: string): number {
  const instance = currentInstance();
  if (instance.phase === "flat_primary") {
    return countFlatImports(instance.environment.BNEST_RUNTIME_ROOT, userId);
  }
  const lines = [
    ...instanceReadPrelude,
    `count = SqliteRepo.query!("SELECT COUNT(*) FROM bnest_records WHERE record_type = ? AND owner_id = ?", ["browser-import", ${quotedUserId(userId)}]).rows |> hd() |> hd()`,
    `IO.puts("${instanceReadMarker}" <> Integer.to_string(count))`,
  ];
  return Number(runMarked(lines.join("\n")));
}

// Row counts of the tables that hold a user's records, chat messages, and push subscriptions. Browser sessions are
// signed cookies and have no table, so a fresh instance has no session row to count. The table names are fixed here,
// so no test value reaches the code text.
const countedTables = [
  "bnest_records",
  "family_chat_messages",
  "web_push_subscriptions",
] as const;

export type CountedTable = (typeof countedTables)[number];

export function instanceRowCounts(): Record<CountedTable, number> {
  const entries = countedTables.map(
    (table) =>
      `"${table}" => SqliteRepo.query!("SELECT COUNT(*) FROM ${table}", []).rows |> hd() |> hd()`,
  );
  const lines = [
    ...instanceReadPrelude,
    `counts = %{${entries.join(", ")}}`,
    `IO.puts("${instanceReadMarker}" <> Jason.encode!(counts))`,
  ];
  const parsed: unknown = JSON.parse(runMarked(lines.join("\n")));
  const counts = Object.fromEntries(
    countedTables.map((table) => [table, numberOf(parsed, table)]),
  );
  return counts as Record<CountedTable, number>;
}

function numberOf(parsed: unknown, table: CountedTable): number {
  const value =
    typeof parsed === "object" && parsed !== null
      ? (parsed as Record<string, unknown>)[table]
      : undefined;
  if (typeof value !== "number") {
    throw new TypeError(`the ${table} count was not a number`);
  }
  return value;
}

function runMarked(expression: string): string {
  const result = runLiveMix(expression);
  if (result.status !== 0) {
    throw new Error(`instance record read failed: ${result.stderr}`);
  }
  return markedPayload(result.stdout);
}
