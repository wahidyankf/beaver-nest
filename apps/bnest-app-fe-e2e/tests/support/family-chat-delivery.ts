import { expect, type Page, type Request } from "@playwright/test";
import { composerInput } from "./family-chat";
import { MESSAGE, messageById } from "./family-chat-gestures";

// Support for family_chat.feature's delivery scenarios -- send status,
// retries, the per-room queue, resume, and the queue's lifetime across a
// session. Everything observed here is the real room talking to the real
// server: what the browser sent (`sendAttempts`), what the room shows, and
// what the browser's own IndexedDB holds. The only thing a scenario changes
// is the network between them (`interfereWithSends`), the way a flaky
// connection would.

export const OUTBOX_STATUS = "[data-role=family-chat-outbox-status]";
const SEND_OPERATION = "SendFamilyChatMessage";

export interface SendAttempt {
  at: number;
  clientMessageId: string;
  body: string;
  replyToMessageId: string | null;
  committedId: string;
  errorCode: string;
  failed: boolean;
}

/**
 * The message the current scenario is following. A module-level object so
 * every step file advances the same one (an imported `let` is read-only).
 */
export const delivery = { body: "", clientMessageId: "" };

const logs = new WeakMap<Page, SendAttempt[]>();

function sendVariables(request: Request): Record<string, unknown> | null {
  const postData = request.postData() ?? "";
  if (!postData.includes(SEND_OPERATION)) return null;
  const payload = JSON.parse(postData) as {
    variables?: Record<string, unknown>;
  };
  return payload.variables ?? {};
}

function recordAttempt(
  attempts: SendAttempt[],
  byRequest: Map<Request, SendAttempt>,
  request: Request,
): void {
  const variables = sendVariables(request);
  if (!variables) return;
  const attempt: SendAttempt = {
    at: Date.now(),
    clientMessageId: String(variables["clientMessageId"] ?? ""),
    body: String(variables["body"] ?? ""),
    replyToMessageId:
      variables["replyToMessageId"] === undefined
        ? null
        : String(variables["replyToMessageId"]),
    committedId: "",
    errorCode: "",
    failed: false,
  };
  attempts.push(attempt);
  byRequest.set(request, attempt);
}

/**
 * Every `SendFamilyChatMessage` request this page makes from now on, with
 * the server's answer to each. Attached once per page; later calls return
 * the same live log.
 */
export function sendAttempts(page: Page): SendAttempt[] {
  const existing = logs.get(page);
  if (existing) return existing;
  const attempts: SendAttempt[] = [];
  const byRequest = new Map<Request, SendAttempt>();
  logs.set(page, attempts);
  page.on("request", (request) =>
    recordAttempt(attempts, byRequest, request),
  );
  page.on("requestfailed", (request) => {
    const attempt = byRequest.get(request);
    if (attempt) attempt.failed = true;
  });
  page.on("response", async (response) => {
    const attempt = byRequest.get(response.request());
    if (!attempt) return;
    const payload = (await response.json().catch(() => ({}))) as {
      data?: { sendFamilyChatMessage?: { id?: string } | null };
      errors?: Array<{ extensions?: { code?: string } }>;
    };
    attempt.committedId = payload.data?.sendFamilyChatMessage?.id ?? "";
    attempt.errorCode = payload.errors?.[0]?.extensions?.code ?? "";
  });
  return attempts;
}

export function attemptsFor(page: Page, body: string): SendAttempt[] {
  return sendAttempts(page).filter((attempt) => attempt.body === body);
}

export type SendInterference = "abort" | "reject" | "hold" | number;

/**
 * Puts the network between this page and the server into one of the states
 * a member meets: a send that never connects (`abort`), one that reaches the
 * server carrying a blank body the server itself refuses (`reject`), one
 * that is still in flight (`hold`, until the page closes), or one that is
 * merely slow (a delay in milliseconds). Every other request passes.
 */
export async function interfereWithSends(
  page: Page,
  mode: SendInterference,
): Promise<void> {
  sendAttempts(page);
  const closed = new Promise<void>((resolve) => {
    page.once("close", () => resolve());
  });
  await page.route("**/api/graphql", async (route) => {
    const variables = sendVariables(route.request());
    if (!variables) {
      await route.fallback();
      return;
    }
    if (mode === "abort") {
      await route.abort("connectionfailed");
      return;
    }
    if (mode === "reject") {
      const payload = JSON.parse(route.request().postData() ?? "{}") as {
        variables: Record<string, unknown>;
      };
      payload.variables["body"] = "   ";
      await route.continue({ postData: JSON.stringify(payload) });
      return;
    }
    if (mode === "hold") {
      await closed;
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(resolve, mode);
    });
    await route.fallback();
  });
}

export async function stopInterfering(page: Page): Promise<void> {
  await page.unroute("**/api/graphql");
}

/** Types `body` and presses Send, the way the member does. */
export async function sendThroughComposer(
  page: Page,
  body: string,
): Promise<void> {
  sendAttempts(page);
  delivery.body = body;
  await composerInput(page).fill(body);
  await page.getByRole("button", { name: "Send" }).click();
}

export function pendingRow(page: Page, body: string) {
  return page
    .locator(`${MESSAGE}:not([data-delivery-state="committed"])`)
    .filter({ hasText: body });
}

/** The pending row's own key, which is its client message ID. */
export async function pendingRowId(page: Page, body: string): Promise<string> {
  const row = pendingRow(page, body);
  await expect(row).toHaveCount(1, { timeout: 10_000 });
  return (await row.getAttribute("data-message-id")) ?? "";
}

/**
 * Sent, judged by the server rather than by the indicator going quiet: the
 * server answered one of this message's sends with a committed ID, and the
 * room shows exactly one committed message under that ID.
 */
export async function expectCommitted(page: Page, body: string): Promise<string> {
  await expect(page.locator(OUTBOX_STATUS)).toHaveText("", { timeout: 20_000 });
  await expect
    .poll(
      () =>
        attemptsFor(page, body).find((attempt) => attempt.committedId !== "")
          ?.committedId ?? "",
      { timeout: 20_000 },
    )
    .not.toBe("");
  const committedId =
    attemptsFor(page, body).find((attempt) => attempt.committedId !== "")
      ?.committedId ?? "";
  const row = messageById(page, committedId);
  await expect(row).toHaveCount(1, { timeout: 10_000 });
  await expect(row).toHaveAttribute("data-delivery-state", "committed");
  await expect(row).toContainText(body);
  await expect(pendingRow(page, body)).toHaveCount(0);
  return committedId;
}

/**
 * The status the message's own row shows. The room-wide indicator only
 * announces transitions after a send's first answer, so the row -- which is
 * rendered with the status the queue gave it -- is where "Sending" and
 * "Waiting for connection" are visible at all.
 */
export async function expectRowStatus(
  page: Page,
  body: string,
  status: string,
): Promise<void> {
  const row = pendingRow(page, body);
  await expect(row).toHaveCount(1, { timeout: 15_000 });
  await expect(row).toHaveAttribute("data-delivery-state", status, {
    timeout: 15_000,
  });
  await expect(
    row.locator("[data-role=family-chat-message-status]"),
  ).toHaveText(status);
}

export async function expectOutboxStatus(
  page: Page,
  status: string,
): Promise<void> {
  if (status === "Sent") {
    await expectCommitted(page, delivery.body);
    return;
  }
  await expectRowStatus(page, delivery.body, status);
}
