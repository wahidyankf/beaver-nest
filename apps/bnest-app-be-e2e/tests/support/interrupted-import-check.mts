import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

// Evidence for "Bnest does not duplicate or overwrite accepted data" after an interrupted browser import (ADR 001,
// section 2). The import identity is derived the way BnestApp.Storage.Domain.Manifest.identity/4 derives it, so the
// test can name the import an interruption left and check the retry against it. The check is a pure function of
// the evidence, so the node test can prove that it refuses each kind of overwrite.

const userIdPattern = /^[A-Za-z0-9_-]{1,128}$/u;
const importIdPattern = /^import-[A-Za-z0-9_-]{1,64}$/u;

// The import identity of one browser source: the owner, area, key, and payload checksum, NUL-joined, hashed.
export function interruptedImportId(
  ownerId: string,
  storageArea: string,
  storageKey: string,
  payload: string,
): string {
  const checksum = createHash("sha256").update(payload).digest("hex");
  const material = [ownerId, storageArea, storageKey, checksum].join("\0");
  const suffix = createHash("sha256")
    .update(material)
    .digest()
    .subarray(0, 18)
    .toString("base64url");
  return `import-${suffix}`;
}

// The SHA-256 of one preserved envelope on a flat-primary instance, or "missing" when the file is absent. The owner
// and the import id are checked before they become path segments, so no input can name another file.
export function envelopeDigest(
  runtimeRoot: string,
  ownerId: string,
  importId: string,
): string {
  if (!userIdPattern.test(ownerId) || !importIdPattern.test(importId)) {
    throw new Error("the envelope identity is not a safe record key");
  }
  const file = path.join(
    runtimeRoot,
    "users",
    ownerId,
    "imports",
    `${importId}.json`,
  );
  try {
    return createHash("sha256").update(readFileSync(file)).digest("hex");
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      return "missing";
    }
    throw error;
  }
}

export type OverwriteEvidence = {
  expectedImportId: string;
  envelopeDigestBefore: string;
  envelopeDigestAfter: string;
  importCountBefore: number;
  importCountAfter: number;
  // The chat record the retry left, or null when none reads back.
  chatRecord: { revision?: unknown; sourceImportId?: unknown } | null;
};

// Each violation names one way the retry duplicated or overwrote accepted data. No violation means the accepted data
// kept its bytes, its count, its first revision, and its import identity.
export function overwriteViolations(evidence: OverwriteEvidence): string[] {
  const violations: string[] = [];
  if (evidence.envelopeDigestBefore === "missing") {
    violations.push("the seeded envelope was never written");
  }
  if (evidence.envelopeDigestAfter !== evidence.envelopeDigestBefore) {
    violations.push("the preserved envelope changed");
  }
  if (evidence.importCountAfter !== evidence.importCountBefore) {
    violations.push("the retry changed the number of envelopes");
  }
  if (evidence.chatRecord === null) {
    violations.push("the retry wrote no chat record");
  } else {
    if (evidence.chatRecord.revision !== 0) {
      violations.push("the chat record is not at its first revision");
    }
    if (evidence.chatRecord.sourceImportId !== evidence.expectedImportId) {
      violations.push("the chat record names another import");
    }
  }
  return violations;
}
