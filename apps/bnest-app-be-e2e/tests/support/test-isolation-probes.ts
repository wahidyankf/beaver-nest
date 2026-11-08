import { backendOriginFromEnv, runId } from "./active-instance.mts";
import { liveRuntimeRoot } from "./sqlite-storage";
import { sqliteRunRoot } from "./live-sqlite";
import { isRecord } from "./testing-control-records.mts";
import type { TestRuntime } from "./test-runtime.mts";

// Probes of the testing routes and of the readiness route (ADR 001, section 2 guards). Every request uses Node fetch,
// never Playwright's request context, so traces never capture the secret header. A reply is compared, never printed,
// and no error here echoes the secret.

const spawnRoute = "/__bnest_testing/v1/instances";
// A path no route serves. Its stock 404 is the answer a guarded testing route must give.
const missingRoute = "/__bnest_missing_route_probe";
const secretHeader = "x-bnest-testing";
// Not the run secret, and too short to be one, so the guard must refuse it.
const wrongSecret = "not-the-run-secret";
const probeTimeoutMs = 30_000;

export type ProbeReply = { status: number; contentType: string; body: string };

export function probeWithoutTestingHeader(): Promise<ProbeReply> {
  return sendSpawnProbe({});
}

export function probeWithWrongTestingHeader(): Promise<ProbeReply> {
  if (runSecret() === wrongSecret) throw new Error("the run secret is the probe value");
  return sendSpawnProbe({ [secretHeader]: wrongSecret });
}

export function probeWithForwardedHeader(): Promise<ProbeReply> {
  return sendSpawnProbe({
    [secretHeader]: runSecret(),
    "x-forwarded-for": "203.0.113.7",
  });
}

// The stock answer to a request for a route that does not exist, sent with the same method and body shape.
export function stockNotFoundReply(): Promise<ProbeReply> {
  return send(missingRoute, {});
}

// The generation the readiness route reports for the instance the server serves now.
export async function readyStorageGeneration(): Promise<string> {
  const response = await fetch(`${backendOriginFromEnv()}/health/ready`, {
    headers: { accept: "application/json" },
    redirect: "error",
    signal: AbortSignal.timeout(probeTimeoutMs),
  });
  const body: unknown = await response.json().catch(() => null);
  const generation = isRecord(body) ? body["storageGeneration"] : undefined;
  if (response.status !== 200 || typeof generation !== "string") {
    throw new Error(
      `the readiness route did not report a storage generation (HTTP ${response.status})`,
    );
  }
  return generation;
}

// The run roots as the leak helper reads them: every instance directory under either root is a leak after teardown.
export function runtimeRoots(): TestRuntime {
  return { path: liveRuntimeRoot(), sqlitePath: sqliteRunRoot(), runId: runId() };
}

function sendSpawnProbe(headers: Record<string, string>): Promise<ProbeReply> {
  return send(spawnRoute, headers);
}

function runSecret(): string {
  const secret = process.env["BNEST_TEST_CONTROL_SECRET"];
  if (secret === undefined || secret === "") {
    throw new Error("BNEST_TEST_CONTROL_SECRET is not set");
  }
  return secret;
}

// A spawn-shaped body with the run id, so a request that passed the guards would reach the spawn itself.
async function send(
  route: string,
  headers: Record<string, string>,
): Promise<ProbeReply> {
  const response = await fetch(`${backendOriginFromEnv()}${route}`, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify({ runId: runId(), label: "probe", phase: "sqlite_primary" }),
    redirect: "error",
    signal: AbortSignal.timeout(probeTimeoutMs),
  });
  return {
    status: response.status,
    contentType: response.headers.get("content-type") ?? "",
    body: await response.text(),
  };
}
