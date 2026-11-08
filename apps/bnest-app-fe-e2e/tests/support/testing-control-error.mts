// Typed errors for the testing control client. Every error body is `{error: {code, detail, path}}`
// (ADR 001, section 2). A reply that does not match becomes `not_found` for the stock 404 or
// `unexpected_response` otherwise. The secret never reaches an error: any copy in the server's text is
// replaced before the error is built.

import { isRecord } from "./testing-control-records.mts";

export const testingErrorCodes = [
  "invalid_request",
  "run_mismatch",
  "instance_active",
  "not_current",
  "instance_busy",
  "seed_conflict",
  "seed_invalid",
  "spawn_failed",
  "cleanup_failed",
  "not_found",
  "missing_secret",
  "invalid_origin",
  "unreachable",
  "unexpected_response",
] as const;

export type TestingErrorCode = (typeof testingErrorCodes)[number];

// `detail` and `path` come from the server body with any copy of the secret removed.
export class TestingControlError extends Error {
  readonly code: TestingErrorCode;
  readonly status: number | null;
  readonly detail: string;
  readonly path: string | null;

  constructor(
    code: TestingErrorCode,
    status: number | null,
    detail: string,
    path: string | null,
  ) {
    super(`${code}${status === null ? "" : ` (HTTP ${status})`}: ${detail}`);
    this.name = "TestingControlError";
    this.code = code;
    this.status = status;
    this.detail = detail;
    this.path = path;
  }
}

export function errorFromReply(
  status: number,
  text: string,
  secret: string,
): TestingControlError {
  const parsed = tryParseJson(text);
  const body = isRecord(parsed) ? parsed["error"] : undefined;
  const mapped = isRecord(body)
    ? mapErrorBody(body, status, secret)
    : undefined;
  if (mapped !== undefined) return mapped;

  // The stock Phoenix 404 is the same answer a missing route gets, and it carries no testing body.
  if (status === 404) {
    return new TestingControlError("not_found", status, "Not Found", null);
  }
  return new TestingControlError(
    "unexpected_response",
    status,
    "the response is not a testing error body",
    null,
  );
}

function mapErrorBody(
  body: Record<string, unknown>,
  status: number,
  secret: string,
): TestingControlError | undefined {
  const code = body["code"];
  const detail = body["detail"];
  const path = body["path"];

  if (
    typeof code !== "string" ||
    typeof detail !== "string" ||
    !(typeof path === "string" || path === null)
  ) {
    return undefined;
  }

  return new TestingControlError(
    isTestingErrorCode(code) ? code : "unexpected_response",
    status,
    redact(detail, secret),
    path === null ? null : redact(path, secret),
  );
}

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function redact(text: string, secret: string): string {
  return text.split(secret).join("[redacted]");
}

function isTestingErrorCode(value: string): value is TestingErrorCode {
  return (testingErrorCodes as readonly string[]).includes(value);
}
