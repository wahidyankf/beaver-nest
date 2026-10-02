// Sends and read-backs the family chat GraphQL step files share. Every send
// is the member's own mutation from the page's session; every read-back is a
// fresh `familyChatMessages` query, never a value a step kept.

import { randomUUID } from "node:crypto";
import { expect, type Page } from "@playwright/test";
import { requireResponse, scenario } from "./family-chat-state";
import {
  pageNodes,
  queryFamilyChatMessages,
  sendFamilyChatMessage,
  type FamilyChatMessage,
  type GraphQlResponse,
  type SendFamilyChatMessageResult,
} from "./graphql";

/** Sends from the page's session; the envelope becomes the scenario's response. */
export async function sendFromPage(
  page: Page,
  body: string,
  clientMessageId: string,
  replyToMessageId: string | null = null,
): Promise<FamilyChatMessage | null> {
  const response = await sendFamilyChatMessage(
    page,
    page.context().request,
    body,
    clientMessageId,
    replyToMessageId,
  );
  scenario.response = response;
  return response.data?.sendFamilyChatMessage ?? null;
}

/** Sends a message a Given needs committed, and returns its server ID. */
export async function commitFromPage(
  page: Page,
  body: string,
  replyToMessageId: string | null = null,
): Promise<string> {
  const message = await sendFromPage(
    page,
    body,
    randomUUID(),
    replyToMessageId,
  );
  expect(message, JSON.stringify(requireResponse().errors)).not.toBeNull();
  return message?.id ?? "";
}

/** The message the scenario's last send answered, or null for a refusal. */
export function sentMessage(): FamilyChatMessage | null {
  const response =
    requireResponse() as GraphQlResponse<SendFamilyChatMessageResult>;
  return response.data?.sendFamilyChatMessage ?? null;
}

/** Every message the room committed after the scenario's recorded baseline. */
export async function sinceBaseline(page: Page): Promise<FamilyChatMessage[]> {
  expect(scenario.baselineId, "a step recorded the baseline").not.toBe("");
  return pageNodes(
    await queryFamilyChatMessages(page, page.context().request, {
      afterId: scenario.baselineId,
    }),
  );
}
