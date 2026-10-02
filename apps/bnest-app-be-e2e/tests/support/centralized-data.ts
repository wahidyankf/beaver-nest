import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";

export const chatPayload = JSON.stringify({
  version: 2,
  thread_id: null,
  model: "fixture-model",
  reasoning_effort: "medium",
  messages: [],
});

export const learningPayload = JSON.stringify({
  version: 2,
  learned_ids: [],
  review_ids: [],
  mastered_key_ids: [],
  review_key_ids: [],
  correct_answers: 0,
  incorrect_answers: 0,
  session: { mode: "dashboard" },
});

function runtimeRoot(): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E runtime root");
  return root;
}

function ownerId(username: string): string {
  const indexPath = path.join(
    runtimeRoot(),
    "system/usernames",
    `${username}.json`,
  );
  return JSON.parse(readFileSync(indexPath, "utf8"))["userId"] as string;
}

export function userPath(relative: string, username: string): string {
  return path.join(runtimeRoot(), "users", ownerId(username), relative);
}

type ChatState = {
  thread_id: string | null;
  messages: Array<{ content: string }>;
};

export function readChatState(username: string): ChatState {
  const record = JSON.parse(
    readFileSync(userPath("chat/current.json", username), "utf8"),
  ) as { state: ChatState };
  return record.state;
}

type InterruptedImport = {
  envelopePath: string;
  envelopeDigest: string;
  importId: string;
};

// The import `seedInterruptedChatImport` last preserved, as it seeded it.
let lastInterruptedImport: InterruptedImport | undefined;

// The preserved envelope keeps its bytes, and the chat record the retry completed is the
// first revision written from that same import.
export function expectInterruptedImportCompleted(username: string): void {
  const seeded = lastInterruptedImport;
  if (seeded === undefined) throw new Error("no interrupted import was seeded");
  expect(digestFile(seeded.envelopePath)).toBe(seeded.envelopeDigest);
  const record = JSON.parse(
    readFileSync(userPath("chat/current.json", username), "utf8"),
  ) as { revision: number; sourceImportId: string };
  expect({
    revision: record.revision,
    sourceImportId: record.sourceImportId,
  }).toEqual({ revision: 0, sourceImportId: seeded.importId });
}

export function digestFile(file: string): string {
  return existsSync(file)
    ? createHash("sha256").update(readFileSync(file)).digest("hex")
    : "missing";
}

export function importCount(username: string): number {
  const directory = userPath("imports", username);
  return existsSync(directory)
    ? readdirSync(directory).filter((name) => name.endsWith(".json")).length
    : 0;
}

// Records the preserved envelope's path, digest and import id for
// `expectInterruptedImportCompleted`.
export function seedInterruptedChatImport(username: string): void {
  const owner = ownerId(username);
  const checksum = createHash("sha256").update(chatPayload).digest("hex");
  const material = [owner, "sessionStorage", "bnest.chat.v1", checksum].join(
    "\0",
  );
  const suffix = createHash("sha256")
    .update(material)
    .digest()
    .subarray(0, 18)
    .toString("base64url");
  const importId = `import-${suffix}`;
  const timestamp = new Date().toISOString();
  const envelopePath = path.join(
    runtimeRoot(),
    "users",
    owner,
    "imports",
    `${importId}.json`,
  );
  writeJsonNew(
    envelopePath,
    browserEnvelope(owner, importId, checksum, timestamp),
  );
  writeJsonNew(
    runtimeRoot(),
    retryableManifest(owner, importId, checksum, timestamp),
    `system/manifests/${importId}.json`,
  );
  lastInterruptedImport = {
    envelopePath,
    envelopeDigest: digestFile(envelopePath),
    importId,
  };
}

function browserEnvelope(
  owner: string,
  importId: string,
  checksum: string,
  timestamp: string,
) {
  return {
    schemaVersion: 1,
    recordType: "browser-import",
    importId,
    ownerId: owner,
    source: {
      kind: "browser-storage",
      storageArea: "sessionStorage",
      storageKey: "bnest.chat.v1",
      sourceSchemaVersion: 2,
    },
    payloadEncoding: "utf8-string",
    payload: chatPayload,
    integrity: { sha256: checksum, capturedAt: timestamp },
  };
}

function retryableManifest(
  owner: string,
  importId: string,
  checksum: string,
  timestamp: string,
) {
  return {
    schemaVersion: 1,
    recordType: "import-manifest",
    importId,
    ownerId: owner,
    source: {
      kind: "browser-storage",
      reference: "bnest.chat.v1",
      sha256: checksum,
    },
    destination: {
      recordType: "chat",
      relativePathTemplate: "users/<owner-id>/chat/current.json",
    },
    recoverySource: {
      kind: "import-envelope",
      relativePathTemplate: "users/<owner-id>/imports/<import-id>.json#payload",
      sha256: checksum,
    },
    status: "retryable",
    attempt: 1,
    startedAt: timestamp,
    completedAt: timestamp,
    failureCategory: "read-back-failed",
  };
}

function writeJsonNew(
  rootOrFile: string,
  record: Record<string, unknown>,
  relative?: string,
): void {
  const file = relative ? path.join(rootOrFile, relative) : rootOrFile;
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(record), { encoding: "utf8", flag: "wx" });
}

export async function setSources(
  page: Page,
  sources: {
    chat?: string | null;
    learning?: string | null;
    theme?: string | null;
  },
) {
  await page.goto("/");
  await page.evaluate((values) => {
    if (values.chat === null) sessionStorage.removeItem("bnest.chat.v1");
    else if (values.chat !== undefined)
      sessionStorage.setItem("bnest.chat.v1", values.chat);

    if (values.learning === null)
      localStorage.removeItem("bnest.sifat-allah.v1");
    else if (values.learning !== undefined) {
      localStorage.setItem("bnest.sifat-allah.v1", values.learning);
    }

    if (values.theme === null) localStorage.removeItem("phx:theme");
    else if (values.theme !== undefined)
      localStorage.setItem("phx:theme", values.theme);
  }, sources);
  await page.goto("/data-migration");
  await expect(
    page.getByRole("heading", { name: "Save this browser's Bnest data" }),
  ).toBeVisible();
}

export async function confirmImports(page: Page) {
  await page
    .getByRole("button", { name: "Preserve and verify recognized data" })
    .click();
  await expect(
    page
      .getByText(
        /accepted and verified|rejected safely|newer server data exists/u,
      )
      .first(),
  ).toBeVisible();
}
