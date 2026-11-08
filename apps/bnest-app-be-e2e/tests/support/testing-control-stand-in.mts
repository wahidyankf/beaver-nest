import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";

// A synthetic 64-character secret. The real value is 32 random bytes per run.
export const secret = "0123456789abcdef".repeat(4);
export const rotated = "fedcba9876543210".repeat(4);
export const instanceId = "a1b2c3d4e5f6g7h8";
export const stateBody = {
  schemaVersion: 1,
  runId: "unit-run-1",
  instance: null,
};

export type Recorded = {
  method: string;
  url: string;
  secretHeader: string | undefined;
  contentType: string | undefined;
  body: string;
};

export type Reply = { status: number; body?: unknown; destroy?: boolean };

// A real loopback HTTP server stands in for the backend. It records each request
// and answers with a scripted reply, so the client's wire behaviour is observed.
export async function withStandIn(
  reply: (request: Recorded) => Reply,
  run: (origin: string, requests: Recorded[]) => Promise<void>,
): Promise<void> {
  const requests: Recorded[] = [];
  const server: Server = createServer((request, response) => {
    handle(request, response, requests, reply);
  });

  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address() as AddressInfo;

  try {
    await run(`http://127.0.0.1:${port}`, requests);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => {
      server.close(() => resolve());
    });
  }
}

// Resolves to the rejection reason, or to undefined when the promise resolves.
export async function errorOf(promise: Promise<unknown>): Promise<unknown> {
  try {
    await promise;
    return undefined;
  } catch (error) {
    return error;
  }
}

function handle(
  request: IncomingMessage,
  response: ServerResponse,
  requests: Recorded[],
  reply: (request: Recorded) => Reply,
): void {
  const chunks: Buffer[] = [];
  request.on("data", (chunk: Buffer) => chunks.push(chunk));
  request.on("end", () => {
    const recorded: Recorded = {
      method: request.method ?? "",
      url: request.url ?? "",
      secretHeader: headerValue(request.headers["x-bnest-testing"]),
      contentType: headerValue(request.headers["content-type"]),
      body: Buffer.concat(chunks).toString("utf8"),
    };
    requests.push(recorded);

    const outcome = reply(recorded);
    if (outcome.destroy === true) {
      request.socket.destroy();
      return;
    }
    response.writeHead(outcome.status, { "content-type": "application/json" });
    if (outcome.body === undefined) {
      response.end();
    } else {
      response.end(JSON.stringify(outcome.body));
    }
  });
}

function headerValue(value: string | string[] | undefined): string | undefined {
  return typeof value === "string" ? value : undefined;
}
