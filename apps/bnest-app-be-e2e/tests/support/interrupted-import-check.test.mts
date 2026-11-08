import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  envelopeDigest,
  interruptedImportId,
  overwriteViolations,
  type OverwriteEvidence,
} from "./interrupted-import-check.mts";

// The evidence of a retry that changed nothing that was accepted. Each test changes one field of it.
const kept: OverwriteEvidence = {
  expectedImportId: "import-abc",
  envelopeDigestBefore: "a".repeat(64),
  envelopeDigestAfter: "a".repeat(64),
  importCountBefore: 1,
  importCountAfter: 1,
  chatRecord: { revision: 0, sourceImportId: "import-abc" },
};

test("accepts a retry that keeps the envelope, the count, the revision, and the import", () => {
  assert.deepEqual(overwriteViolations(kept), []);
});

test("refuses a retry that changed the preserved envelope", () => {
  assert.deepEqual(
    overwriteViolations({ ...kept, envelopeDigestAfter: "b".repeat(64) }),
    ["the preserved envelope changed"],
  );
});

test("refuses a retry that added an envelope", () => {
  assert.deepEqual(overwriteViolations({ ...kept, importCountAfter: 2 }), [
    "the retry changed the number of envelopes",
  ]);
});

test("refuses a chat record that is not at its first revision", () => {
  assert.deepEqual(
    overwriteViolations({
      ...kept,
      chatRecord: { revision: 1, sourceImportId: "import-abc" },
    }),
    ["the chat record is not at its first revision"],
  );
});

test("refuses a chat record that names another import", () => {
  assert.deepEqual(
    overwriteViolations({
      ...kept,
      chatRecord: { revision: 0, sourceImportId: "import-other" },
    }),
    ["the chat record names another import"],
  );
});

test("refuses a retry that wrote no chat record", () => {
  assert.deepEqual(overwriteViolations({ ...kept, chatRecord: null }), [
    "the retry wrote no chat record",
  ]);
});

test("refuses a seed whose envelope was never written", () => {
  assert.deepEqual(
    overwriteViolations({
      ...kept,
      envelopeDigestBefore: "missing",
      envelopeDigestAfter: "missing",
    }),
    ["the seeded envelope was never written"],
  );
});

test("derives a stable import identity that depends on every input", () => {
  const base = interruptedImportId("user-a", "sessionStorage", "k", "{}");
  assert.match(base, /^import-[A-Za-z0-9_-]{24}$/u);
  assert.equal(
    base,
    interruptedImportId("user-a", "sessionStorage", "k", "{}"),
  );
  assert.notEqual(
    base,
    interruptedImportId("user-b", "sessionStorage", "k", "{}"),
  );
  assert.notEqual(
    base,
    interruptedImportId("user-a", "localStorage", "k", "{}"),
  );
  assert.notEqual(
    base,
    interruptedImportId("user-a", "sessionStorage", "k", "{ }"),
  );
});

test("digests a preserved envelope and reports a missing one", () => {
  const base = mkdtempSync(path.join(os.tmpdir(), "bnest-envelope-digest-"));
  try {
    const imports = path.join(base, "users", "user-a", "imports");
    mkdirSync(imports, { recursive: true });
    writeFileSync(path.join(imports, "import-abc.json"), "first");
    const first = envelopeDigest(base, "user-a", "import-abc");
    assert.match(first, /^[0-9a-f]{64}$/u);
    writeFileSync(path.join(imports, "import-abc.json"), "second");
    assert.notEqual(envelopeDigest(base, "user-a", "import-abc"), first);
    assert.equal(envelopeDigest(base, "user-a", "import-none"), "missing");
    assert.throws(() => envelopeDigest(base, "../user-a", "import-abc"));
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});
