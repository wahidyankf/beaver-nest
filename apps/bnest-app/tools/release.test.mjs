import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  executeRelease,
  gateManifest,
  ReleaseError,
  verifyMigrationManifest,
} from "./release.mjs";
import { acquirePortLease, releasePortLease } from "./port-lease.mjs";
import { normalizeProductionOrigin } from "./production-origin.mjs";

const revision = "0123456789abcdef0123456789abcdef01234567";

test("owns one fixed uncached gate manifest without duplicate application quick work", () => {
  assert.deepEqual(
    gateManifest.map(({ id }) => id),
    [
      "bnest-quick",
      "bnest-integration",
      "e2e-quick",
      "release-recovery-e2e",
      "release-load-e2e",
      "repository",
    ],
  );
  assert.ok(
    gateManifest.every(({ arguments: arguments_ }) =>
      arguments_.includes("--skip-nx-cache"),
    ),
  );
  assert.equal(
    gateManifest.find(({ id }) => id === "e2e-quick").arguments.at(-2),
    "test:release-quick",
  );
});

function fakeHost(overrides = {}) {
  const calls = [];
  const host = {
    calls,
    preflight: async () => {
      calls.push("preflight");
      return { revision, activeSlot: "blue" };
    },
    runGates: async () => calls.push("gates"),
    build: async () => calls.push("build"),
    proveMigration: async () => {
      calls.push("migration");
      return "not-required";
    },
    prepareCandidate: async (slot) => calls.push(`candidate:${slot}`),
    discardCandidate: async (slot) => calls.push(`discard:${slot}`),
    discardArtifact: async () => calls.push("discard-artifact"),
    recoverActivation: async () => {
      calls.push("recover-activation");
      return "candidate-cleanup";
    },
    activate: async (slot) => calls.push(`activate:${slot}`),
    proveRouted: async () => calls.push("routed"),
    drainAndCleanup: async (slot) => calls.push(`cleanup:${slot}`),
    rollback: async () => calls.push("rollback"),
    releaseLock: async () => calls.push("unlock"),
    ...overrides,
  };
  return host;
}

test("runs one ordered transaction and releases the lock", async () => {
  const host = fakeHost();
  const result = await executeRelease(host, { drainMs: 0 });
  assert.equal(result.outcome, "passed");
  assert.equal(result.releaseRevision, revision);
  assert.equal(result.migrationState, "not-required");
  assert.deepEqual(Object.keys(result).toSorted(), [
    "durationMs",
    "errorCategory",
    "evidenceIds",
    "fromState",
    "migrationState",
    "nextTransition",
    "outcome",
    "releaseRevision",
    "schemaVersion",
    "toState",
  ]);
  assert.deepEqual(host.calls, [
    "preflight",
    "gates",
    "build",
    "migration",
    "candidate:green",
    "activate:green",
    "routed",
    "cleanup:blue",
    "unlock",
  ]);
});

test("coalesces a revision that is already active", async () => {
  const host = fakeHost({
    preflight: async () => {
      host.calls.push("preflight");
      return { revision, activeSlot: "blue", alreadyActive: true };
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "passed");
  assert.ok(result.evidenceIds.includes("coalesced-active"));
  assert.deepEqual(host.calls, ["preflight", "routed", "unlock"]);
});

test("stops before build when a gate fails", async () => {
  const host = fakeHost({
    runGates: async () => {
      host.calls.push("gates");
      throw new ReleaseError("gate", "gate failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "failed");
  assert.equal(result.errorCategory, "gate");
  assert.deepEqual(host.calls, ["preflight", "gates", "unlock"]);
});

test("removes a partial artifact when stage capacity is lost before candidate work", async () => {
  const host = fakeHost({
    build: async () => {
      host.calls.push("build");
      throw new ReleaseError("capacity", "swap-in occurred", "deferred");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "deferred");
  assert.equal(result.nextTransition, "preflight");
  assert.deepEqual(host.calls, [
    "preflight",
    "gates",
    "build",
    "discard-artifact",
    "unlock",
  ]);
  assert.ok(!host.calls.some((call) => call.startsWith("candidate")));
});

test("rolls back routed proof failure before cleanup", async () => {
  const host = fakeHost({
    proveRouted: async () => {
      host.calls.push("routed");
      throw new ReleaseError("routed-proof", "routed proof failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "rolled-back");
  assert.equal(result.errorCategory, "routed-proof");
  assert.deepEqual(host.calls.slice(-5), [
    "routed",
    "rollback",
    "discard:green",
    "discard-artifact",
    "unlock",
  ]);
  assert.ok(!host.calls.some((call) => call.startsWith("cleanup")));
});

test("retires a failed candidate without changing the active route", async () => {
  const host = fakeHost({
    prepareCandidate: async (slot) => {
      host.calls.push(`candidate:${slot}`);
      throw new ReleaseError("candidate", "candidate failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "failed");
  assert.equal(result.errorCategory, "candidate");
  assert.deepEqual(host.calls.slice(-4), [
    "candidate:green",
    "discard:green",
    "discard-artifact",
    "unlock",
  ]);
  assert.ok(!host.calls.some((call) => call.startsWith("activate")));
});

test("inspects and recovers a failed promotion", async () => {
  const host = fakeHost({
    activate: async (slot) => {
      host.calls.push(`activate:${slot}`);
      throw new ReleaseError("promotion", "promotion failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "failed");
  assert.equal(result.errorCategory, "promotion");
  assert.deepEqual(host.calls.slice(-4), [
    "activate:green",
    "recover-activation",
    "discard-artifact",
    "unlock",
  ]);
});

test("keeps the proven route when only final cleanup fails", async () => {
  const host = fakeHost({
    drainAndCleanup: async (slot) => {
      host.calls.push(`cleanup:${slot}`);
      throw new ReleaseError("cleanup", "cleanup failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "failed");
  assert.equal(result.nextTransition, "cleanup");
  assert.ok(!host.calls.includes("rollback"));
  assert.deepEqual(host.calls.slice(-2), ["cleanup:blue", "unlock"]);
});

test("rolls back when resource evidence finds a continuity failure", async () => {
  const host = fakeHost({
    drainAndCleanup: async (slot) => {
      host.calls.push(`cleanup:${slot}`);
      throw new ReleaseError("continuity", "health failed");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "rolled-back");
  assert.equal(result.nextTransition, "preflight");
  assert.deepEqual(host.calls.slice(-5), [
    "cleanup:blue",
    "rollback",
    "discard:green",
    "discard-artifact",
    "unlock",
  ]);
});

test("runs three serialized release transactions without residual state", async () => {
  for (let cycle = 0; cycle < 3; cycle += 1) {
    const host = fakeHost();
    const result = await executeRelease(host, { drainMs: 0 });
    assert.equal(result.outcome, "passed");
    assert.equal(host.calls.at(-1), "unlock");
    assert.equal(host.calls.filter((call) => call === "unlock").length, 1);
  }
});

test("returns a non-mutating capacity deferral", async () => {
  const host = fakeHost({
    preflight: async () => {
      host.calls.push("preflight");
      throw new ReleaseError("capacity", "capacity unavailable", "deferred");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "deferred");
  assert.equal(result.nextTransition, "preflight");
  assert.deepEqual(host.calls, ["preflight", "unlock"]);
});

test("returns a non-mutating queued result for lock contention", async () => {
  const host = fakeHost({
    preflight: async () => {
      host.calls.push("preflight");
      throw new ReleaseError("concurrency", "lock busy", "queued");
    },
  });
  const result = await executeRelease(host);
  assert.equal(result.outcome, "queued");
  assert.equal(result.errorCategory, "concurrency");
  assert.deepEqual(host.calls, ["preflight", "unlock"]);
});

test("accepts only an empty checksum-verified migration set", () => {
  const emptyChecksum = createHash("sha256").update("[]").digest("hex");
  assert.equal(
    verifyMigrationManifest({
      migrations: [],
      migrationSetChecksum: emptyChecksum,
    }),
    "not-required",
  );
  assert.throws(
    () =>
      verifyMigrationManifest({
        migrations: [],
        migrationSetChecksum: "invalid",
      }),
    /checksum does not match/u,
  );
  const declaredMigrations = [{ id: "expand-1" }];
  const declaredChecksum = createHash("sha256")
    .update(JSON.stringify(declaredMigrations))
    .digest("hex");
  assert.throws(
    () =>
      verifyMigrationManifest({
        migrations: declaredMigrations,
        migrationSetChecksum: declaredChecksum,
      }),
    /approved migration adapter/u,
  );
});

test("accepts only a bare HTTPS production origin", () => {
  assert.deepEqual(normalizeProductionOrigin("https://service.example"), {
    host: "service.example",
    origin: "https://service.example",
  });
  for (const value of [
    "http://service.example",
    "https://user@service.example",
    "https://service.example/path",
    "https://service.example?query=1",
    "https://service.example/#fragment",
    "not-an-origin",
  ])
    assert.throws(() => normalizeProductionOrigin(value), /HTTPS origin/u);
});

test("port leases exclude a second owner and release exactly", () => {
  const lease = acquirePortLease(45_321, "release-test", 45_000, 46_000);
  assert.throws(
    () => acquirePortLease(45_321, "second-test", 45_000, 46_000),
    /already leased/u,
  );
  releasePortLease(lease);
  const replacement = acquirePortLease(45_321, "second-test", 45_000, 46_000);
  releasePortLease(replacement);
});

test("port leases recover an exact stale process marker", () => {
  const port = 45_322;
  const leasePath = join(tmpdir(), "bnest-port-leases", `${port}.lock`);
  mkdirSync(leasePath, { recursive: true, mode: 0o700 });
  writeFileSync(
    join(leasePath, "owner.json"),
    `${JSON.stringify({
      schemaVersion: 1,
      port,
      owner: "stale-test",
      pid: 2_147_483_647,
    })}\n`,
    { encoding: "utf8", mode: 0o600 },
  );
  const lease = acquirePortLease(port, "replacement-test", 45_000, 46_000);
  releasePortLease(lease);
});
