import { randomBytes, randomUUID } from "node:crypto";
import { expect, type APIRequestContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { requireIdentity, scenario } from "../support/family-chat-state";
import { postGraphQl, type GraphQlResponse } from "../support/graphql";
import {
  INTROSPECTION,
  invocation,
  mutationFields,
  namesSystem,
  type IntrospectionResult,
  type MutationField,
} from "../support/public-schema";
import { isolatedTestIdentity } from "../support/test-identity";

// The one family_chat_operations.feature scenario a client reaches over HTTP: the public
// GraphQL schema's mutation fields, read through introspection and each sent by a
// logged-in member. Every other scenario there carries @e2e-exempt.

const { Then, When } = createBdd();

interface SchemaInspection {
  fields: MutationField[];
  responses: { field: string; response: GraphQlResponse | string }[];
  committedSenderKinds: string[];
}

interface MessagesPage {
  familyChatMessages: { nodes: { id: string; senderKind: string }[] };
}

let inspection: SchemaInspection | null = null;

function base64Url(bytes: number): string {
  return randomBytes(bytes).toString("base64url");
}

// The sender kind of every message after `afterId`, or the newest message ID when
// `afterId` is null.
async function roomMessages(
  page: Page,
  request: APIRequestContext,
  afterId: string | null,
): Promise<{ id: string; senderKind: string }[]> {
  const response = await postGraphQl<MessagesPage>(
    page,
    request,
    `query($roomSlug: String!, $afterId: ID) {
      familyChatMessages(roomSlug: $roomSlug, afterId: $afterId) { nodes { id senderKind } }
    }`,
    { roomSlug: "ruang-keluarga", afterId },
  );
  expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
  return response.data?.familyChatMessages.nodes ?? [];
}

// Sends one field with its arguments filled by name, or names the argument it lacks.
function exercise(
  page: Page,
  request: APIRequestContext,
  field: MutationField,
): Promise<GraphQlResponse | string> {
  const run = invocation(field, {
    roomSlug: "ruang-keluarga",
    clientMessageId: randomUUID(),
    body: "public schema probe",
    endpoint: `https://push.allowed.example.com/test-user-schema-${randomUUID()}`,
    p256dh: base64Url(65),
    auth: base64Url(16),
  });
  return "unexercisable" in run
    ? Promise.resolve(`unexercisable: ${run.unexercisable}`)
    : postGraphQl(page, request, run.document, run.variables);
}

When("the public GraphQL schema is inspected", async ({ page, $testInfo }) => {
  scenario.identity = isolatedTestIdentity($testInfo);
  await page.context().clearCookies();
  await login(page, requireIdentity().admin);
  const request = page.context().request;

  // The newest message before any field runs, so what the fields commit is read back alone.
  const knownIds = (await roomMessages(page, request, null)).map((node) =>
    Number(node.id),
  );
  const afterId = String(knownIds.length > 0 ? Math.max(...knownIds) : 0);

  const introspection = await postGraphQl<IntrospectionResult>(
    page,
    request,
    INTROSPECTION,
  );
  expect(
    introspection.errors,
    JSON.stringify(introspection.errors),
  ).toBeUndefined();
  const fields = mutationFields(introspection.data!);
  const answers = await Promise.all(
    fields.map((field) => exercise(page, request, field)),
  );

  inspection = {
    fields,
    responses: fields.map((field, index) => ({
      field: field.name,
      response: answers[index] ?? "no answer",
    })),
    committedSenderKinds: (await roomMessages(page, request, afterId)).map(
      (node) => node.senderKind,
    ),
  };
});

Then("it declares no field that posts a system message", () => {
  if (!inspection) throw new Error("no schema inspection: a When must run one");
  const names = inspection.fields.map((field) => field.name);
  expect(names.length, "the schema declares mutation fields").toBeGreaterThan(
    0,
  );
  expect(names.filter((name) => namesSystem(name))).toEqual([]);
  for (const { field, response } of inspection.responses) {
    expect(
      typeof response,
      `${field} could be exercised: ${String(response)}`,
    ).toBe("object");
    const answer = response as GraphQlResponse;
    expect(
      answer.errors,
      `${field}: ${JSON.stringify(answer.errors)}`,
    ).toBeUndefined();
    expect(answer.data?.[field], `${field} answered`).toBeTruthy();
  }
  // Only what these requests committed: the member's own probe message, no system one.
  expect(inspection.committedSenderKinds.length).toBeGreaterThan(0);
  expect(
    inspection.committedSenderKinds.filter((kind) => kind === "system"),
  ).toEqual([]);
  inspection = null;
});
