import type { APIRequestContext, Page } from "@playwright/test";

// Minimal GraphQL HTTP client over Playwright's APIRequestContext, which
// carries the browser context's session cookies (and therefore identity)
// automatically. Kept intentionally small: family-chat.steps.ts's two
// non-exempt scenarios only need to issue one mutation over HTTP before
// driving the real Absinthe subscription socket (subscriptions.ts).
//
// The mutation/query shapes here match the real, implemented
// `BnestAppWeb.Schema` exactly (tech-doc 008): `sendFamilyChatMessage` takes
// three top-level arguments (`roomSlug`, `clientMessageId`, `body`), never a
// wrapped `input` object, and `family_chat_message`'s only fields are `id`,
// `roomSlug`, `senderKind`, `senderId`, `senderDisplayName`, `body`, and
// `committedAt` -- the idempotency/client-message key is deliberately never
// exposed over GraphQL (an internal dedup mechanism only), so correlating
// "the message I just sent" against a later query must use the
// server-assigned `id`, not a client-supplied key.

export interface GraphQlResponse<T = Record<string, unknown>> {
  data?: T;
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
  const response = await request.post("/api/graphql", {
    headers: { "x-csrf-token": csrfToken },
    data: { query, variables },
  });
  return (await response.json()) as GraphQlResponse<T>;
}

export interface SendFamilyChatMessageResult {
  sendFamilyChatMessage: {
    id: string;
    roomSlug: string;
    senderKind: string;
    senderId: string;
    senderDisplayName: string;
    body: string;
    committedAt: string;
  } | null;
}

export function sendFamilyChatMessage(
  page: Page,
  request: APIRequestContext,
  body: string,
  clientMessageId: string,
): Promise<GraphQlResponse<SendFamilyChatMessageResult>> {
  return postGraphQl<SendFamilyChatMessageResult>(
    page,
    request,
    `mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
      sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) {
        id
        roomSlug
        senderKind
        senderId
        senderDisplayName
        body
        committedAt
      }
    }`,
    { roomSlug: "ruang-keluarga", clientMessageId, body },
  );
}

export interface FamilyChatMessagesResult {
  familyChatMessages: {
    nodes: { id: string; body: string; committedAt: string }[];
    hasNewer: boolean;
  };
}

export function queryFamilyChatMessagesAfter(
  page: Page,
  request: APIRequestContext,
  afterId: string,
): Promise<GraphQlResponse<FamilyChatMessagesResult>> {
  return postGraphQl<FamilyChatMessagesResult>(
    page,
    request,
    `query($roomSlug: String!, $afterId: ID!) {
      familyChatMessages(roomSlug: $roomSlug, afterId: $afterId) {
        nodes { id body committedAt }
        hasNewer
      }
    }`,
    { roomSlug: "ruang-keluarga", afterId },
  );
}
