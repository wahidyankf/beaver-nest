import { runLiveMix } from "./routed-rollout";
import {
  parseRecordState,
  recordReadExpression,
  type RecordKind,
  type RecordState,
} from "./instance-record-read.mts";

// Reads one of the current instance's records through production code, in a secondary `mix run -e` process that
// takes its environment from the instance (ADR 001, section 2). The record is read from the instance's database, so
// a scenario on a sqlite_primary instance never looks for a flat file. The expression and its parser live in
// instance-record-read.mts, which the BE project keeps identical.

export type { RecordKind, RecordState } from "./instance-record-read.mts";

// The record the server holds for one user, or the reason it holds none.
export function instanceRecordState(
  kind: RecordKind,
  userId: string,
): RecordState {
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
