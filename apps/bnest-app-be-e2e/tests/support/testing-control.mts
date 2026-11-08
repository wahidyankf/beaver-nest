// Typed client for the test-only routes under /__bnest_testing/v1 (ADR 001, section 2).
//
// It uses Node fetch, never Playwright's request context, so Playwright traces do not capture the
// secret header. It reads BNEST_TEST_CONTROL_SECRET on every call, sends it only in the
// x-bnest-testing header, and never logs it or puts it into an error. The client talks to the
// backend loopback port directly, never through Caddy.
//
// The ADR gives no body for POST /instances/:id/seed. This client sends { seedKey, seed }, where seed
// has the same shape as the seed object of POST /instances.

import {
  errorFromReply,
  TestingControlError,
} from "./testing-control-error.mts";
import {
  parseSeedResult,
  parseSpawned,
  parseState,
  type SeedRequest,
  type SeedResult,
  type SpawnedInstance,
  type SpawnRequest,
  type TestingState,
} from "./testing-control-records.mts";

export {
  TestingControlError,
  testingErrorCodes,
} from "./testing-control-error.mts";
export type { TestingErrorCode } from "./testing-control-error.mts";
export type * from "./testing-control-records.mts";

const routePrefix = "/__bnest_testing/v1";
const secretHeader = "x-bnest-testing";
const secretEnvironmentName = "BNEST_TEST_CONTROL_SECRET";
const minimumSecretBytes = 32;
const requestTimeoutMs = 60_000;
const loopbackHostnames: ReadonlySet<string> = new Set([
  "127.0.0.1",
  "localhost",
  "[::1]",
]);

export type TestingControlOptions = {
  origin: string;
  env?: Readonly<Record<string, string | undefined>>;
};

export type TestingControlClient = {
  state(): Promise<TestingState>;
  spawnInstance(request: SpawnRequest): Promise<SpawnedInstance>;
  seedInstance(instanceId: string, request: SeedRequest): Promise<SeedResult>;
  deleteInstance(instanceId: string): Promise<void>;
};

type HttpMethod = "GET" | "POST" | "DELETE";
type HttpReply = { status: number; text: string };
type Env = Readonly<Record<string, string | undefined>>;

// The origin must be a loopback http origin. The client never reaches a public host.
export function createTestingControlClient(
  options: TestingControlOptions,
): TestingControlClient {
  const origin = loopbackOrigin(options.origin);
  const env = options.env ?? process.env;
  const call = (method: HttpMethod, route: string, body?: unknown) =>
    sendRequest({ origin, env, method, route, body });

  return {
    async state() {
      return success(await call("GET", "/state"), 200, parseState);
    },

    async spawnInstance(request) {
      const body = {
        runId: request.runId,
        label: request.label,
        ...(request.instanceId === undefined
          ? {}
          : { instanceId: checkedInstanceId(request.instanceId) }),
        phase: request.phase,
        storage: request.storage,
        seed: request.seed,
      };
      return success(await call("POST", "/instances", body), 201, parseSpawned);
    },

    async seedInstance(instanceId, request) {
      const body = { seedKey: request.seedKey, seed: request.seed };
      const route = `/instances/${encodeURIComponent(instanceId)}/seed`;
      return success(await call("POST", route, body), 200, parseSeedResult);
    },

    async deleteInstance(instanceId) {
      const route = `/instances/${encodeURIComponent(instanceId)}`;
      expectNoContent(await call("DELETE", route));
    },
  };
}

// The backend port in every E2E project is a loopback port on 127.0.0.1.
export function backendOrigin(port: string | number): string {
  const value =
    typeof port === "number"
      ? port
      : /^[0-9]+$/u.test(port)
        ? Number(port)
        : Number.NaN;

  if (!Number.isInteger(value) || value < 1 || value > 65_535) {
    throw invalidOrigin("the backend port must be a TCP port number");
  }
  return `http://127.0.0.1:${value}`;
}

function loopbackOrigin(origin: string): string {
  let url: URL;
  try {
    url = new URL(origin);
  } catch {
    throw invalidOrigin("the origin is not a URL");
  }

  if (
    url.protocol !== "http:" ||
    !loopbackHostnames.has(url.hostname) ||
    url.pathname !== "/" ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw invalidOrigin("the origin must be a plain http loopback origin");
  }
  return url.origin;
}

function invalidOrigin(detail: string): TestingControlError {
  return new TestingControlError("invalid_origin", null, detail, null);
}

// Matches the server's instance id rule (ADR 001, section 2), so a malformed id never leaves the client.
const instanceIdPattern = /^[a-z0-9]{16}$/u;

function checkedInstanceId(instanceId: string): string {
  if (!instanceIdPattern.test(instanceId)) {
    throw new TestingControlError(
      "invalid_request",
      null,
      "the instance id must be 16 lowercase letters or digits",
      null,
    );
  }
  return instanceId;
}

// Reads the secret at call time, so a rotated value applies to the next request.
function readSecret(env: Env): string {
  const secret = env[secretEnvironmentName];
  if (
    secret === undefined ||
    Buffer.byteLength(secret, "utf8") < minimumSecretBytes
  ) {
    throw new TestingControlError(
      "missing_secret",
      null,
      `${secretEnvironmentName} is unset or shorter than ${minimumSecretBytes} bytes`,
      null,
    );
  }
  return secret;
}

async function sendRequest(request: {
  origin: string;
  env: Env;
  method: HttpMethod;
  route: string;
  body: unknown;
}): Promise<HttpReply> {
  const secret = readSecret(request.env);
  const url = `${request.origin}${routePrefix}${request.route}`;
  const response = await fetchOrThrow(
    url,
    requestInit(secret, request.method, request.body),
  );
  const text = await readText(response);

  if (!response.ok) throw errorFromReply(response.status, text, secret);
  return { status: response.status, text };
}

function requestInit(
  secret: string,
  method: HttpMethod,
  body: unknown,
): RequestInit {
  const headers: Record<string, string> = {
    accept: "application/json",
    [secretHeader]: secret,
  };
  const init: RequestInit = {
    method,
    headers,
    redirect: "error",
    signal: AbortSignal.timeout(requestTimeoutMs),
  };

  if (body !== undefined) {
    headers["content-type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  return init;
}

async function fetchOrThrow(url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, init);
  } catch {
    // The cause is dropped on purpose: a network error message could echo request details.
    throw new TestingControlError(
      "unreachable",
      null,
      "the testing control endpoint did not answer",
      null,
    );
  }
}

async function readText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    throw new TestingControlError(
      "unexpected_response",
      response.status,
      "the response body could not be read",
      null,
    );
  }
}

function success<T>(
  reply: HttpReply,
  status: number,
  parse: (value: unknown) => T | undefined,
): T {
  if (reply.status !== status) {
    throw new TestingControlError(
      "unexpected_response",
      reply.status,
      `expected HTTP ${status}`,
      null,
    );
  }

  const parsed = parse(parseJson(reply.text, reply.status));
  if (parsed === undefined) {
    throw new TestingControlError(
      "unexpected_response",
      reply.status,
      "the response does not match the testing record",
      null,
    );
  }
  return parsed;
}

function expectNoContent(reply: HttpReply): void {
  if (reply.status !== 204) {
    throw new TestingControlError(
      "unexpected_response",
      reply.status,
      "the delete route answers 204 with no body",
      null,
    );
  }
}

function parseJson(text: string, status: number): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new TestingControlError(
      "unexpected_response",
      status,
      "the response body is not JSON",
      null,
    );
  }
}
