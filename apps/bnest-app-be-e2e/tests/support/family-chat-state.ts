// The state the family chat step definitions hand to each other.
//
// playwright-bdd discovers steps across files, but a module-level `let` is
// not shared across them: an importer of `export let` gets a readable live
// binding it cannot assign. So the scenario's working values live on one
// mutable object instead, which both step files hold by reference. This is
// the same shape `bnest-app-fe-e2e`'s reply support already uses.

import type { queryFamilyChatMessagesAfter } from "./graphql";
import type { TestIdentity } from "./test-identity";

export interface FamilyChatScenarioState {
  afterId: string;
  catchUp: Awaited<ReturnType<typeof queryFamilyChatMessagesAfter>> | null;
  clientMessageId: string;
  identity: TestIdentity | null;
  replyId: string;
  replyTargetId: string;
  serverMessageId: string;
}

export const scenario: FamilyChatScenarioState = {
  afterId: "",
  catchUp: null,
  clientMessageId: "",
  identity: null,
  replyId: "",
  replyTargetId: "",
  serverMessageId: "",
};

/**
 * The identity a Given established. Reading it before that Given ran is a
 * step-ordering bug, so it says so rather than handing back a null that
 * surfaces later as an unrelated failure.
 */
export function requireIdentity(): TestIdentity {
  if (!scenario.identity) {
    throw new Error("no family chat identity: a Given must establish one");
  }
  return scenario.identity;
}

/** The catch-up page a When fetched, with the same contract. */
export function requireCatchUp(): NonNullable<
  FamilyChatScenarioState["catchUp"]
> {
  if (!scenario.catchUp) {
    throw new Error("no catch-up response: a When must fetch one");
  }
  return scenario.catchUp;
}
