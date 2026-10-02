import type { APIRequestContext, Page } from "@playwright/test";

// Minimal GraphQL HTTP client over Playwright's APIRequestContext, which
// carries the browser context's session cookies (and therefore identity)
// automatically: every family_chat_graphql.feature scenario bound here posts
// through it, and the subscription scenarios then drive the real Absinthe
// socket (subscriptions.ts).
//
// The mutation/query shapes here match the real, implemented
// `BnestAppWeb.Schema` exactly (tech-doc 008): `sendFamilyChatMessage` takes
// four top-level arguments (`roomSlug`, `clientMessageId`, `body`, and the
// nullable `replyToMessageId`), never a wrapped `input` object, and
// `family_chat_message`'s fields are `id`, `roomSlug`, `senderKind`,
// `senderId`, `senderDisplayName`, `body`, `committedAt`, and the nullable
// `replyTo` quote -- the idempotency/client-message key is deliberately never
// exposed over GraphQL (an internal dedup mechanism only), so correlating
// "the message I just sent" against a later query must use the
// server-assigned `id`, not a client-supplied key.
//
// `replyTo` is a distinct object type, not a recursive message, so it can
// never carry a quote of its own -- which is why the shape below bottoms out.

export interface GraphQlResponse<T = Record<string, unknown>> {
  data?: T | null;
  errors?: { message: string; extensions?: Record<string, unknown> }[];
}

async function readCsrfToken(page: Page): Promise<string> {
  const token = await page.evaluate(
    () =>
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
        ?.content,
  );
  if (!token) throw new Error("missing csrf-token meta tag on the page");
  return token;
}

/** The HTTP status and the decoded envelope of one POST to `/api/graphql`. */
export async function postGraphQlWithStatus<T = Record<string, unknown>>(
  request: APIRequestContext,
  headers: Record<string, string>,
  query: string,
  variables: Record<string, unknown> = {},
): Promise<{ status: number; body: GraphQlResponse<T> }> {
  const response = await request.post("/api/graphql", {
    headers,
    data: { query, variables },
  });
  return {
    status: response.status(),
    body: (await response.json()) as GraphQlResponse<T>,
  };
}

export async function postGraphQl<T = Record<string, unknown>>(
  page: Page,
  request: APIRequestContext,
  query: string,
  variables: Record<string, unknown> = {},
): Promise<GraphQlResponse<T>> {
  // Real GraphQL POSTs require the same `x-csrf-token` header a real browser
  // fetch sends (tech-doc 008); Playwright's APIRequestContext shares the
  // page's cookies automatically but never reads or attaches this header on
  // its own, so it is read from the page's own CSRF meta tag here.
  const csrfToken = await readCsrfToken(page);
  const { body } = await postGraphQlWithStatus<T>(
    request,
    { "x-csrf-token": csrfToken },
    query,
    variables,
  );
  return body;
}

export interface FamilyChatMessageQuote {
  id: string;
  senderKind: string;
  senderDisplayName: string;
  bodyPreview: string;
}

export interface FamilyChatMessage {
  id: string;
  roomSlug: string;
  senderKind: string;
  senderId: string;
  senderDisplayName: string;
  body: string;
  committedAt: string;
  replyTo: FamilyChatMessageQuote | null;
}

export interface SendFamilyChatMessageResult {
  sendFamilyChatMessage: FamilyChatMessage | null;
}

export function sendFamilyChatMessage(
  page: Page,
  request: APIRequestContext,
  body: string,
  clientMessageId: string,
  replyToMessageId: string | null = null,
): Promise<GraphQlResponse<SendFamilyChatMessageResult>> {
  return postGraphQl<SendFamilyChatMessageResult>(
    page,
    request,
    `mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!, $replyToMessageId: ID) {
      sendFamilyChatMessage(
        roomSlug: $roomSlug
        clientMessageId: $clientMessageId
        body: $body
        replyToMessageId: $replyToMessageId
      ) {
        id
        roomSlug
        senderKind
        senderId
        senderDisplayName
        body
        committedAt
        replyTo { id senderKind senderDisplayName bodyPreview }
      }
    }`,
    { roomSlug: "ruang-keluarga", clientMessageId, body, replyToMessageId },
  );
}

export interface FamilyChatMessagesResult {
  familyChatMessages: {
    nodes: FamilyChatMessage[];
    hasOlder: boolean;
    hasNewer: boolean;
  } | null;
}

export interface FamilyChatPageVariables {
  afterId?: string;
  beforeId?: string;
  limit?: number;
}

/** One `familyChatMessages` page of the room, with the cursors given. */
export function queryFamilyChatMessages(
  page: Page,
  request: APIRequestContext,
  variables: FamilyChatPageVariables = {},
): Promise<GraphQlResponse<FamilyChatMessagesResult>> {
  return postGraphQl<FamilyChatMessagesResult>(
    page,
    request,
    `query($roomSlug: String!, $beforeId: ID, $afterId: ID, $limit: Int) {
      familyChatMessages(roomSlug: $roomSlug, beforeId: $beforeId, afterId: $afterId, limit: $limit) {
        nodes {
          id roomSlug senderKind senderId senderDisplayName body committedAt
          replyTo { id senderKind senderDisplayName bodyPreview }
        }
        hasOlder
        hasNewer
      }
    }`,
    { roomSlug: "ruang-keluarga", ...variables },
  );
}

export function queryFamilyChatMessagesAfter(
  page: Page,
  request: APIRequestContext,
  afterId: string,
): Promise<GraphQlResponse<FamilyChatMessagesResult>> {
  return queryFamilyChatMessages(page, request, { afterId });
}

/**
 * The nodes of a page, or a failure naming the errors the server answered
 * instead: a Then that silently read an empty page would pass for the wrong
 * reason.
 */
export function pageNodes(
  response: GraphQlResponse<FamilyChatMessagesResult>,
): FamilyChatMessage[] {
  if (response.errors || !response.data?.familyChatMessages) {
    throw new Error(`no message page: ${JSON.stringify(response.errors)}`);
  }
  return response.data.familyChatMessages.nodes;
}

/** The newest message ID the room holds now, or "0" for an empty room. */
export async function newestFamilyChatMessageId(page: Page): Promise<string> {
  const nodes = pageNodes(
    await queryFamilyChatMessages(page, page.context().request),
  );
  return nodes.at(-1)?.id ?? "0";
}
