// The state the family chat step definitions hand to each other.
//
// playwright-bdd discovers steps across files, but a module-level `let` is
// not shared across them: an importer of `export let` gets a readable live
// binding it cannot assign. So the scenario's working values live on one
// mutable object instead, which every step file holds by reference. This is
// the same shape `bnest-app-fe-e2e`'s reply support already uses.
//
// `resetFamilyChatScenario` runs before every scenario, so a When that fails
// to assign a value can never be masked by one an earlier scenario left.

import type { TestInfo } from "@playwright/test";
import type { GraphQlResponse, queryFamilyChatMessagesAfter } from "./graphql";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

export interface FamilyChatScenarioState {
  afterId: string;
  /** The newest message ID the room held before the scenario's own sends. */
  baselineId: string;
  catchUp: Awaited<ReturnType<typeof queryFamilyChatMessagesAfter>> | null;
  clientMessageId: string;
  /** The IDs the "known ordered history" Given committed, oldest first. */
  historyIds: string[];
  httpStatus: number;
  identity: TestIdentity | null;
  /** The body the scenario's own send carried, to find it again in a page. */
  knownBody: string;
  originalId: string;
  pushEndpoint: string;
  replyId: string;
  replyTargetId: string;
  /** The body of the message a reply names, as its sender wrote it. */
  replyTargetBody: string;
  replyTargetSender: string;
  /** The GraphQL envelope the scenario's last When received. */
  response: GraphQlResponse<object> | null;
  secondTargetId: string;
  serverMessageId: string;
  socketOutcome: "open" | "rejected" | null;
}

function freshState(): FamilyChatScenarioState {
  return {
    afterId: "",
    baselineId: "",
    catchUp: null,
    clientMessageId: "",
    historyIds: [],
    httpStatus: 0,
    identity: null,
    knownBody: "",
    originalId: "",
    pushEndpoint: "",
    replyId: "",
    replyTargetBody: "",
    replyTargetId: "",
    replyTargetSender: "",
    response: null,
    secondTargetId: "",
    serverMessageId: "",
    socketOutcome: null,
  };
}

export const scenario: FamilyChatScenarioState = freshState();

export function resetFamilyChatScenario(): void {
  Object.assign(scenario, freshState());
}

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

/**
 * The scenario's own isolated identities, whose admin the Background "an
 * approved user is logged in" already logged this page in as. Computed once
 * per scenario: the accounts already exist, so this only names them.
 */
export function scenarioIdentity(testInfo: TestInfo): TestIdentity {
  scenario.identity ??= isolatedTestIdentity(testInfo);
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

/** The GraphQL envelope a When received, with the same contract. */
export function requireResponse(): GraphQlResponse<object> {
  if (!scenario.response) {
    throw new Error("no GraphQL response: a When must send one");
  }
  return scenario.response;
}
