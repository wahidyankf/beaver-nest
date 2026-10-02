import { expect, type Page } from "@playwright/test";
import { runLiveMix } from "./routed-rollout";

// Server-side state the family chat scenarios stage or read back through the
// application's own facades: a `mix run` over this run's marked runtime and
// storage pointer, the ones the routed server uses (as
// `test-user-records.ts` does for user records). Used only where the browser
// cannot reach the state itself -- a system message has no public producer,
// and a logged-out session can no longer ask about its own push binding.

const IDENTITY_COOKIE = "_bnest_identity";
// `BnestApp.Test.RecordingPushSender` (config/test.exs) answers this host and
// never dials out, so a binding to it can never reach a real push service.
const SYNTHETIC_PUSH_HOST = "push.allowed.example.com";

function requireTestUserId(userId: string): void {
  if (!/^user-test-[a-z0-9-]+$/u.test(userId)) {
    throw new Error("server state may be read only for a test user");
  }
}

function mixOutput(expression: string, marker: string): string {
  const result = runLiveMix(expression);
  if (result.status !== 0) {
    throw new Error(`mix run failed: ${result.stderr}`);
  }
  const line = result.stdout
    .split("\n")
    .find((candidate) => candidate.startsWith(`${marker}=`));
  if (line === undefined) {
    throw new Error(`mix run printed no ${marker}: ${result.stdout}`);
  }
  return line.slice(marker.length + 1);
}

function graphql(
  page: Page,
  query: string,
  variables: Record<string, string>,
): Promise<unknown> {
  return page.evaluate(
    async (input) => {
      const response = await fetch("/api/graphql", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-csrf-token":
            document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
              ?.content ?? "",
        },
        body: JSON.stringify(input),
      });
      return response.json() as Promise<unknown>;
    },
    { query, variables },
  );
}

function randomKey(bytes: number): string {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(bytes))).toString(
    "base64url",
  );
}

/**
 * Binds this session to a Web Push subscription through the same mutation
 * the room's own "Enable notifications" sends once the browser has
 * subscribed. The browser half cannot happen here -- headless Chromium has no
 * push service and reports the notification permission as denied -- so the
 * subscription the server receives is a synthetic one.
 */
export async function bindPushSubscription(page: Page): Promise<void> {
  const bound = (await graphql(
    page,
    `mutation UpsertWebPushSubscription($endpoint: String!, $p256dh: String!, $auth: String!) {
      upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled }
    }`,
    {
      endpoint: `https://${SYNTHETIC_PUSH_HOST}/${crypto.randomUUID()}`,
      p256dh: randomKey(65),
      auth: randomKey(16),
    },
  )) as { data?: { upsertWebPushSubscription?: { enabled?: boolean } } };
  expect(bound.data?.upsertWebPushSubscription?.enabled).toBe(true);
}

/** The raw session token the identity cookie carries (httpOnly). */
export async function identityToken(page: Page): Promise<string> {
  const cookie = (await page.context().cookies()).find(
    (candidate) => candidate.name === IDENTITY_COOKIE,
  );
  if (!cookie) throw new Error("the visitor has no identity session");
  return cookie.value;
}

/** Whether the server still holds an active push binding for that session. */
export function serverPushEnabled(userId: string, token: string): boolean {
  requireTestUserId(userId);
  const expression = [
    `{:ok, binding} = BnestApp.PushNotifications.current_subscription(${JSON.stringify(userId)}, BnestApp.Identity.session_digest(${JSON.stringify(token)}))`,
    `IO.puts("push-enabled=#{binding.enabled}")`,
  ].join("; ");
  return mixOutput(expression, "push-enabled") === "true";
}

/**
 * Commits a system message the way the server's internal producers do
 * (`FamilyChat.post_system_message/3`, which no request can reach) and
 * returns its server ID.
 */
export function postSystemMessage(body: string): string {
  const producerKey = `test-e2e-system-${crypto.randomUUID()}`;
  const expression = [
    "BnestApp.FamilyChat.ensure_ready!()",
    `{:ok, message} = BnestApp.FamilyChat.post_system_message("ruang-keluarga", ${JSON.stringify(producerKey)}, ${JSON.stringify(body)})`,
    `IO.puts("system-message-id=#{message.id}")`,
  ].join("; ");
  return mixOutput(expression, "system-message-id");
}
