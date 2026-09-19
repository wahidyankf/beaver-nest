import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  boundedReleaseEnvironment,
  executeRelease,
  gateManifest,
  ReleaseError,
  verifyMigrationManifest,
} from "./release.mjs";
import { normalizeProductionOrigin } from "./production-origin.mjs";

const revision = "0123456789abcdef0123456789abcdef01234567";

test("installs both lock-bound dependency sets before compiling an artifact", () => {
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  const npmInstall = source.indexOf('run("npm", ["ci"]');
  const mixInstall = source.indexOf(
    'run("mix", ["deps.get", "--only", "prod", "--check-locked"]',
  );
  const compile = source.indexOf('run("mix", ["compile"]');

  assert.ok(npmInstall >= 0);
  assert.ok(mixInstall > npmInstall);
  assert.ok(compile > mixInstall);
});

test("owns one fixed uncached gate manifest without duplicate application quick work", () => {
  assert.deepEqual(
    gateManifest.map(({ id }) => id),
    [
      "bnest-quick",
      "bnest-integration",
      "be-e2e-quick",
      "fe-e2e-quick",
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
  // Each gate's `-p` project must be a real Nx project. `bnest-app-e2e` was
  // split into `bnest-app-be-e2e`/`bnest-app-fe-e2e`, and a prior version of
  // this manifest kept pointing at the deleted merged project name -- this
  // test's own assertions did not previously check the `-p` argument at
  // all, so that regression passed silently until a documentation audit
  // caught it. Assert every gate's project explicitly now.
  assert.deepEqual(
    gateManifest.map(({ arguments: arguments_ }) => arguments_[2]),
    [
      "bnest-app",
      "bnest-app",
      "bnest-app-be-e2e",
      "bnest-app-fe-e2e",
      "bnest-app-fe-e2e",
      "bnest-app-fe-e2e",
      "rhino-consumer",
    ],
  );
  assert.equal(
    gateManifest.find(({ id }) => id === "be-e2e-quick").arguments.at(-2),
    "test:release-quick",
  );
  assert.equal(
    gateManifest.find(({ id }) => id === "fe-e2e-quick").arguments.at(-2),
    "test:release-quick",
  );
  assert.deepEqual(
    gateManifest
      .find(({ id }) => id === "release-recovery-e2e")
      .arguments.slice(-2),
    ["--grep", "An automatic LiveView reconnect"],
  );
});

test("isolates release gates from production runtime configuration", () => {
  const environment = boundedReleaseEnvironment({
    BNEST_DEPLOY_ROOT: "/synthetic/deployment",
    BNEST_RUNTIME_ROOT: "/synthetic/production-data",
    BNEST_DEPLOY_COOKIE_FILE: "/synthetic/cookie",
    BNEST_DEPLOY_SECRET_KEY_BASE_FILE: "/synthetic/key-base",
    BNEST_DEPLOY_WORKTREE: "/synthetic/worktree",
    BNEST_PRODUCTION_ORIGIN: "https://service.example",
    RELEASE_COOKIE: "synthetic-cookie",
    SECRET_KEY_BASE: "synthetic-key-base",
    PHX_HOST: "service.example",
    PORT: "4001",
    PATH: "/synthetic/bin",
  });

  assert.equal(environment.ERL_FLAGS, "+S 4:4");
  assert.equal(environment.PATH, "/synthetic/bin");
  for (const name of [
    "BNEST_DEPLOY_ROOT",
    "BNEST_RUNTIME_ROOT",
    "BNEST_DEPLOY_COOKIE_FILE",
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
    "BNEST_DEPLOY_WORKTREE",
    "BNEST_PRODUCTION_ORIGIN",
    "RELEASE_COOKIE",
    "SECRET_KEY_BASE",
    "PHX_HOST",
    "PORT",
  ])
    assert.equal(environment[name], undefined);
});

test("passes explicit health inputs to the release monitor", () => {
  const source = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  assert.match(source, /"release",\s*"monitor"/u);
  assert.match(
    source,
    /"--health-url",\s*"http:\/\/127\.0\.0\.1:4100\/health\/ready"/u,
  );
  assert.match(source, /"--routed-origin",\s*this\.productionOrigin/u);
  for (const port of ["4000", "4001", "4100"])
    assert.match(source, new RegExp(`"--service-port",\\s*"${port}"`, "u"));
  assert.match(
    source,
    /assessment\.status === 75 \? "capacity" : "continuity"/u,
  );
});

test("enables account identity cutover in every managed slot", () => {
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  assert.match(source, /BNEST_IDENTITY_CUTOVER: "true"/u);
});

test("passes the existing runtime VAPID values to every managed slot", () => {
  // Tech-doc 007: deployment passes the existing runtime VAPID values to both
  // slots, unconditionally (not gated on `BNEST_FAMILY_CHAT_ENABLED`), since
  // `config/runtime.exs` raises in `:prod` on every boot when these are
  // absent -- a candidate that launchd starts without them never becomes
  // ready, regardless of which feature flags are set. `launchAgent`'s
  // `variables` object is a hard-coded allowlist (unlike a plain
  // `...process.env` spread), so a key missing from it here is a key the
  // launchd-managed process never receives.
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  assert.match(
    source,
    /requiredEnvironment\(\s*"BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE"/u,
  );
  assert.match(
    source,
    /requiredEnvironment\(\s*"BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE"/u,
  );
  assert.match(source, /requiredWebPushSubject\(\)/u);
  assert.match(
    source,
    /BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE: webPushPublicKeyFile/u,
  );
  assert.match(
    source,
    /BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE: webPushPrivateKeyFile/u,
  );
  assert.match(source, /BNEST_WEB_PUSH_SUBJECT: webPushSubject/u);
});

test("never configures a nonzero Caddy stream-close delay while keeping the shutdown grace period", () => {
  // Family Chat plan requirement (tech-doc 007/009): a nonzero
  // `stream_close_delay` would keep a browser's WebSocket bound to the
  // unloaded prior proxy config for the whole delay, defeating the
  // "old socket closes; reconnect <=10s" release invariant, since Blue/Green
  // slots are independent `RELEASE_DISTRIBUTION=none` processes that never
  // share PubSub. `grace_period` is a different, required directive (HTTP
  // server shutdown during Caddy config changes/process stop) and must stay.
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(source, /stream_close_delay/u);
  assert.match(source, /grace_period 5m/u);
});

test("launches every deployment slot through one shared RELEASE_DISTRIBUTION=none path", () => {
  // Both Blue and Green are started through the same `launchAgent` function
  // (a single call site parameterized by `slot`), so this one assertion
  // structurally covers both slots at once -- there is no second,
  // independently-written launch path that could omit it and silently
  // reintroduce a cross-slot PubSub/Distributed-Erlang assumption.
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  const definitions = source.match(/function launchAgent\(/gu) ?? [];
  const allOccurrences = source.match(/launchAgent\(/gu) ?? [];
  assert.equal(
    definitions.length,
    1,
    "expected exactly one launchAgent implementation",
  );
  assert.equal(
    allOccurrences.length - definitions.length,
    1,
    "expected exactly one call site sharing that one implementation across both slots",
  );
  assert.match(source, /RELEASE_DISTRIBUTION: "none"/u);
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

test("accepts only checksum-verified approved migration sets", () => {
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
  const approvedMigrations = [
    { id: "flat-files-v1-to-sqlite-v1" },
    {
      id: "bnest-persistent-schedules-v1",
      version: 20260830000000,
      checksum: createHash("sha256")
        .update(
          readFileSync(
            new URL(
              "../priv/sqlite_repo/migrations/20260830000000_add_persistent_schedules.exs",
              import.meta.url,
            ),
          ),
        )
        .digest("hex"),
    },
  ];
  const approvedChecksum = createHash("sha256")
    .update(JSON.stringify(approvedMigrations))
    .digest("hex");
  assert.equal(
    verifyMigrationManifest({
      migrations: approvedMigrations,
      migrationSetChecksum: approvedChecksum,
    }),
    "declared",
  );
  const mismatchedMigrations = [
    {
      id: "bnest-persistent-schedules-v1",
      version: 20260830000000,
      checksum: "stale",
    },
  ];
  assert.throws(
    () =>
      verifyMigrationManifest({
        migrations: mismatchedMigrations,
        migrationSetChecksum: createHash("sha256")
          .update(JSON.stringify(mismatchedMigrations))
          .digest("hex"),
      }),
    /immutable adapter/u,
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

test("runs the persistent schedules adapter from the immutable release", () => {
  const source = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );

  assert.match(source, /case "release:migrate"/u);
  assert.match(
    source,
    /PersistentSchedules\.apply_and_verify!\(DateTime\.utc_now\(\)\)/u,
  );
  assert.match(source, /BNEST_REPOSITORY_ROOT: repositoryRoot/u);
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
