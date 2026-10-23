import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, beforeEach } from "node:test";

import {
  boundedReleaseEnvironment,
  executeExperienceRelease,
  executeRelease,
  experienceGateManifest,
  gateManifest,
  ReleaseError,
  verifyMigrationManifest,
} from "./release.mjs";
import { normalizeProductionOrigin } from "./production-origin.mjs";

const revision = "0123456789abcdef0123456789abcdef01234567";

// The launchd slot and Caddy code moved to launchd.mjs (D-11); the orchestrator
// assertions that follow the code read both files together.
function toolSource(...names) {
  return names
    .map((name) => readFileSync(new URL(`./${name}`, import.meta.url), "utf8"))
    .join("\n");
}

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
  const source = toolSource("deployment.mjs", "launchd.mjs");
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
  const source = toolSource("deployment.mjs", "launchd.mjs");
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

test("converges the backup schedule and push retention once after old-slot drain", () => {
  // Tech-doc 009 ("Backup Schedule Migration"): "After the compatibility
  // revision is routed and every runnable slot supports the new Backup
  // service, managed release calls a public Scheduler operation that
  // force-converges this key once"; and push retention "becomes enabled
  // only after old-slot drain." `release.mjs` must call this once
  // `drainAndCleanup` (which retires the prior slot) has actually returned,
  // and `deployment.mjs` must route it to the real `FamilyChat` migration
  // function rather than raw SQL (tech-doc 009's Service Boundaries: release
  // tooling never constructs raw retention SQL).
  const releaseSource = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  const drainIndex = releaseSource.indexOf("await host.drainAndCleanup(");
  const convergeIndex = releaseSource.indexOf("await host.convergeAfterDrain(");
  assert.ok(drainIndex >= 0);
  assert.ok(convergeIndex > drainIndex);
  assert.match(
    releaseSource,
    /this\.deployment\(\s*"release:converge",\s*\["--revision", revision\]\)/u,
  );

  const deploymentSource = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  assert.match(deploymentSource, /case "release:converge":/u);
  assert.match(
    deploymentSource,
    /BnestApp\.Release\.Migrations\.FamilyChat\.converge_after_drain!\(\)/u,
  );
});

test("never configures a nonzero Caddy stream-close delay while keeping the shutdown grace period", () => {
  // Family Chat plan requirement (tech-doc 007/009): a nonzero
  // `stream_close_delay` would keep a browser's WebSocket bound to the
  // unloaded prior proxy config for the whole delay, defeating the
  // "old socket closes; reconnect <=10s" release invariant, since Blue/Green
  // slots are independent `RELEASE_DISTRIBUTION=none` processes that never
  // share PubSub. `grace_period` is a different, required directive (HTTP
  // server shutdown during Caddy config changes/process stop) and must stay.
  // The deployment tool writes the configuration `caddy-config.mjs` builds.
  const source = readFileSync(
    new URL("./caddy-config.mjs", import.meta.url),
    "utf8",
  );
  const deploymentSource = readFileSync(
    new URL("./deployment.mjs", import.meta.url),
    "utf8",
  );
  assert.match(
    deploymentSource,
    /import \{ caddyfile, slots \} from "\.\/caddy-config\.mjs";/u,
  );
  assert.doesNotMatch(deploymentSource, /stream_close_delay/u);
  assert.doesNotMatch(source, /stream_close_delay/u);
  assert.match(source, /grace_period 5m/u);
});

test("launches every deployment slot through one shared RELEASE_DISTRIBUTION=none path", () => {
  // Both Blue and Green are started through the same `launchAgent` function
  // (a single call site parameterized by `slot`), so this one assertion
  // structurally covers both slots at once -- there is no second,
  // independently-written launch path that could omit it and silently
  // reintroduce a cross-slot PubSub/Distributed-Erlang assumption.
  const source = toolSource("deployment.mjs", "launchd.mjs");
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

test("reuses the exact reviewed compatibility SHA with only the flag-on candidate proof", () => {
  // Tech-doc 009's Experience Release Procedure: no repository edit,
  // migration, or schema contraction is allowed, so the experience release's
  // own gate manifest re-runs nothing the compatibility release already
  // proved -- only the new two-`test-user-`-context proof this SHA has
  // never faced with the flag on.
  assert.deepEqual(
    experienceGateManifest.map(({ id }) => id),
    ["experience-release-e2e"],
  );
  const gate = experienceGateManifest[0];
  assert.ok(gate.arguments.includes("--skip-nx-cache"));
  assert.equal(gate.arguments[2], "bnest-app-fe-e2e");
  assert.deepEqual(gate.arguments.slice(-2), [
    "--grep",
    "Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate",
  ]);
});

test("threads --family-chat-enabled from deploy:prepare into the launchd plist only when requested", () => {
  // Tech-doc 009 step 1: the experience candidate is the only slot ever
  // started with `BNEST_FAMILY_CHAT_ENABLED=true`; every ordinary
  // compatibility-release slot must keep omitting the key entirely so
  // `config/runtime.exs`'s default (`false`) governs unchanged.
  const source = toolSource("deployment.mjs", "launchd.mjs");
  assert.match(
    source,
    /arguments_\.includes\(\s*"--family-chat-enabled"\s*\)/u,
  );
  assert.match(
    source,
    /familyChatEnabled\s*\?\s*\{\s*BNEST_FAMILY_CHAT_ENABLED:\s*"true"\s*\}\s*:\s*\{\}/u,
  );
  assert.match(source, /familyChatEnabled = false/u);
});

test("threads --family-chat-reply-enabled the same way, and only for the experience candidate", () => {
  // Quoting is gated independently of the room it lives in, so the two flags
  // travel separately: a compatibility-release slot omits this key and still
  // answers `replyTo` for any caller, which is the whole reason the reply
  // bundle is safe to ship one release ahead of the flag. Only the
  // experience candidate asks for it, and it asks through `release.mjs` --
  // asserted here too, because a plist built correctly from an argument
  // nobody passes is still a flag nobody turns on.
  const deployment = toolSource("deployment.mjs", "launchd.mjs");
  assert.match(
    deployment,
    /arguments_\.includes\(\s*"--family-chat-reply-enabled",?\s*\)/u,
  );
  assert.match(
    deployment,
    /familyChatReplyEnabled\s*\?\s*\{\s*BNEST_FAMILY_CHAT_REPLY_ENABLED:\s*"true"\s*\}\s*:\s*\{\}/u,
  );
  assert.match(deployment, /familyChatReplyEnabled = false/u);

  const release = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  assert.match(release, /"--family-chat-reply-enabled"/u);
});

function fakeExperienceHost(overrides = {}) {
  const calls = [];
  const host = {
    calls,
    experiencePreflight: async () => {
      calls.push("preflight");
      return { revision, activeSlot: "blue" };
    },
    runGates: async () => calls.push("gates"),
    prepareExperienceCandidate: async (slot) =>
      calls.push(`experience-candidate:${slot}`),
    discardCandidate: async (slot) => calls.push(`discard:${slot}`),
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

test("promotes a same-revision flag-on candidate without building or migrating", async () => {
  const host = fakeExperienceHost();
  const result = await executeExperienceRelease(host, { drainMs: 0 });
  assert.equal(result.outcome, "passed");
  assert.equal(result.releaseRevision, revision);
  assert.equal(result.migrationState, "not-required");
  assert.deepEqual(host.calls, [
    "preflight",
    "gates",
    "experience-candidate:green",
    "activate:green",
    "routed",
    "cleanup:blue",
    "unlock",
  ]);
  assert.ok(result.evidenceIds.includes("experience-candidate-proof"));
  assert.ok(!result.evidenceIds.includes("convergence"));
});

test("never discards the shared artifact when the flag-on candidate fails", async () => {
  // The candidate and the currently-routed slot share one artifact on disk
  // (the same already-reviewed revision); discarding it on failure would
  // delete the artifact production is still serving from.
  const host = fakeExperienceHost({
    prepareExperienceCandidate: async (slot) => {
      host.calls.push(`experience-candidate:${slot}`);
      throw new ReleaseError("candidate", "candidate failed");
    },
  });
  const result = await executeExperienceRelease(host);
  assert.equal(result.outcome, "failed");
  assert.equal(result.errorCategory, "candidate");
  assert.deepEqual(host.calls.slice(-3), [
    "experience-candidate:green",
    "discard:green",
    "unlock",
  ]);
  assert.ok(!("discardArtifact" in host));
});

test("rolls back a flag-on promotion that never reaches routed proof", async () => {
  const host = fakeExperienceHost({
    proveRouted: async () => {
      host.calls.push("routed");
      throw new ReleaseError("routed-proof", "routed proof failed");
    },
  });
  const result = await executeExperienceRelease(host);
  assert.equal(result.outcome, "rolled-back");
  assert.deepEqual(host.calls.slice(-4), [
    "routed",
    "rollback",
    "discard:green",
    "unlock",
  ]);
});

test("rolls back the flag-on candidate when drain finds a continuity failure", async () => {
  const host = fakeExperienceHost({
    drainAndCleanup: async (slot) => {
      host.calls.push(`cleanup:${slot}`);
      throw new ReleaseError("continuity", "health failed");
    },
  });
  const result = await executeExperienceRelease(host);
  assert.equal(result.outcome, "rolled-back");
  assert.deepEqual(host.calls.slice(-4), [
    "cleanup:blue",
    "rollback",
    "discard:green",
    "unlock",
  ]);
});

test("selects the release mode from --mode, defaulting to compatibility", () => {
  const source = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  assert.match(
    source,
    /argumentValue\(\s*"--mode"\s*\)\s*\?\?\s*"compatibility"/u,
  );
  assert.match(
    source,
    /mode === "experience"\s*\?\s*await executeExperienceRelease/u,
  );
});

test("derives the experience release revision from the routed slot, not the checkout HEAD", () => {
  // The delivery's own compatibility release for this SHA, and every
  // `learnings.md` update after it, moves `origin/main` past whatever is
  // currently routed -- the experience release's revision must come from
  // live `proxy:status`, never from `assertReleaseSource()`'s no-argument
  // return (the checkout's current HEAD).
  const source = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  assert.match(source, /const revision = proxyStatus\.activeRevision;/u);
  assert.match(source, /await host\.experiencePreflight\(options\.revision\)/u);
  assert.match(
    source,
    /await host\.runGates\(releaseRevision, experienceGateManifest, false\)/u,
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
    convergeAfterDrain: async (rev) => calls.push(`converge:${rev}`),
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
    `converge:${revision}`,
    "unlock",
  ]);
  assert.ok(result.evidenceIds.includes("convergence"));
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
  const source = toolSource("deployment.mjs", "launchd.mjs");

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

// Linux deployment support (D-11, L-01 to L-11). One isolated fixture serves
// every case: the adapters read their roots from the environment when they
// load, so each case sets the same values. `systemctl` is a stub that records
// its calls; no case reaches a real service manager.
const systemdRoot = mkdtempSync(join(tmpdir(), "bnest-systemd-test-"));
const systemdDeployment = join(systemdRoot, "deployment");
const systemdHome = join(systemdRoot, "home");
const systemdLog = join(systemdRoot, "systemctl.log");
const systemdBin = join(systemdRoot, "bin");
// Flag files that make the stub report a unit inactive, or reset-failed fail
// as it does for a unit it does not know.
const systemdInactive = join(systemdRoot, "units-inactive");
const systemdUnknown = join(systemdRoot, "units-unknown");
after(() => rmSync(systemdRoot, { recursive: true, force: true }));
// Every test starts with an empty call log, so no assertion can pass on a call
// that an earlier test made.
beforeEach(() => writeFileSync(systemdLog, ""));

mkdirSync(systemdBin, { recursive: true });
writeFileSync(
  join(systemdBin, "systemctl"),
  `#!/bin/sh
echo "$@" >> "${systemdLog}"
case "$*" in
  *is-active*) [ -e "${systemdInactive}" ] && exit 3 ;;
  *reset-failed*) [ -e "${systemdUnknown}" ] && exit 5 ;;
esac
exit 0
`,
  { mode: 0o755 },
);
// A curl stub for the Caddy download. It writes the archive named by --output
// with bytes that are not the pinned tarball, and logs that it ran.
const caddyBin = join(systemdRoot, "caddy-bin");
const curlLog = join(systemdRoot, "curl.log");
mkdirSync(caddyBin, { recursive: true });
writeFileSync(
  join(caddyBin, "curl"),
  `#!/bin/sh
echo "$@" >> "${curlLog}"
while [ $# -gt 0 ]; do
  if [ "$1" = "--output" ]; then output="$2"; fi
  shift
done
printf 'not the pinned archive' > "$output"
`,
  { mode: 0o755 },
);
// The macOS adapter runs in one test, so its launchctl calls need a stub too.
writeFileSync(join(systemdBin, "launchctl"), "#!/bin/sh\nexit 0\n", {
  mode: 0o755,
});
mkdirSync(join(systemdDeployment, "secrets"), { recursive: true, mode: 0o700 });
mkdirSync(join(systemdDeployment, "logs"), { recursive: true });
mkdirSync(systemdHome, { recursive: true });

function writeSecret(name, value) {
  const path = join(systemdDeployment, "secrets", name);
  writeFileSync(path, `${value}\n`, { mode: 0o600 });
  return path;
}

const syntheticSecrets = {
  cookie: "synthetic-cookie-value",
  secretKeyBase: "synthetic-secret-key-base-value",
};
const secretFiles = {
  cookie: writeSecret("release.cookie", syntheticSecrets.cookie),
  secretKeyBase: writeSecret("secret_key_base", syntheticSecrets.secretKeyBase),
  webPushPublic: writeSecret("web_push_public_key", "synthetic-public-key"),
  webPushPrivate: writeSecret("web_push_private_key", "synthetic-private-key"),
};

function systemdEnvironment(overrides = {}) {
  return {
    BNEST_DEPLOY_ROOT: systemdDeployment,
    HOME: systemdHome,
    PATH: `${systemdBin}:${process.env.PATH}`,
    ...overrides,
  };
}

async function withEnvironment(variables, body) {
  const saved = Object.fromEntries(
    Object.keys(variables).map((key) => [key, process.env[key]]),
  );
  Object.assign(process.env, variables);
  try {
    return await body();
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function slotOptions(overrides = {}) {
  return {
    release: join(systemdDeployment, "releases", revision),
    runtimeRoot: join(systemdDeployment, "runtime"),
    cookieFile: secretFiles.cookie,
    secretKeyBaseFile: secretFiles.secretKeyBase,
    webPushPublicKeyFile: secretFiles.webPushPublic,
    webPushPrivateKeyFile: secretFiles.webPushPrivate,
    webPushSubject: "mailto:synthetic@example.test",
    productionHost: "service.example",
    revision,
    logPath: join(systemdDeployment, "logs", "blue.log"),
    errorPath: join(systemdDeployment, "logs", "blue.error.log"),
    familyChatEnabled: false,
    familyChatReplyEnabled: false,
    ...overrides,
  };
}

function unitFile(name) {
  return join(systemdHome, ".config", "systemd", "user", name);
}

function systemctlCalls() {
  return readFileSync(systemdLog, "utf8").split("\n").filter(Boolean);
}

// The lines of one section of a unit file, without its header.
function unitSection(unit, name) {
  const section = unit
    .split(/^\[/mu)
    .find((part) => part.startsWith(`${name}]`));
  return section ? section.split("\n") : [];
}

async function withStubFlag(flag, body) {
  writeFileSync(flag, "");
  try {
    return await body();
  } finally {
    rmSync(flag, { force: true });
  }
}

test("systemd unit: writes the slot unit with restart-always and the plist's open-file limits", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("blue", slotOptions());
    const unit = readFileSync(unitFile(systemd.unitNames.blue), "utf8");
    assert.match(unit, /^Restart=always$/mu);
    assert.ok(unitSection(unit, "Service").includes("RestartSec=5"));
    assert.ok(unitSection(unit, "Unit").includes("StartLimitIntervalSec=0"));
    assert.match(unit, /^LimitNOFILE=4096:8192$/mu);
    assert.doesNotMatch(unit, /KeepAlive/u);
    assert.match(unit, /^ExecStart=.*bin\/bnest_app"? start$/mu);
    assert.match(unit, /PHX_SERVER=true/u);
    assert.deepEqual(systemctlCalls(), [
      "--user daemon-reload",
      "--user enable bnest-app-blue.service",
      "--user reset-failed bnest-app-blue.service",
      "--user restart bnest-app-blue.service",
    ]);
  });
});

test("systemd unit: still restarts a slot when reset-failed reports the unit unknown", async () => {
  await withEnvironment(systemdEnvironment(), () =>
    withStubFlag(systemdUnknown, async () => {
      const systemd = await import("./systemd.mjs");
      systemd.installSlotService("blue", slotOptions());
      assert.deepEqual(systemctlCalls(), [
        "--user daemon-reload",
        "--user enable bnest-app-blue.service",
        "--user reset-failed bnest-app-blue.service",
        "--user restart bnest-app-blue.service",
      ]);
    }),
  );
});

test("systemd unit: holds no secret value and reads the secrets from a mode 600 EnvironmentFile", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("blue", slotOptions());
    const unit = readFileSync(unitFile(systemd.unitNames.blue), "utf8");
    for (const value of Object.values(syntheticSecrets))
      assert.equal(unit.includes(value), false);
    assert.match(unit, /^EnvironmentFile=/mu);
    const environmentFile = unit
      .match(/^EnvironmentFile=(.+)$/mu)[1]
      .replace(/^"(.*)"$/u, "$1");
    const contents = readFileSync(environmentFile, "utf8");
    assert.match(contents, /RELEASE_COOKIE=/u);
    assert.ok(contents.includes(syntheticSecrets.cookie));
    assert.equal(statSync(environmentFile).mode & 0o777, 0o600);
  });
});

test("systemd unit: puts a PATH that names node's directory in the unit", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("blue", slotOptions());
    const unit = readFileSync(unitFile(systemd.unitNames.blue), "utf8");
    const pathLine = unit.match(/^Environment="PATH=(.*)"$/mu);
    assert.ok(pathLine, "the unit carries an Environment PATH line");
    assert.ok(
      pathLine[1].split(":").includes(dirname(process.execPath)),
      "the PATH names the directory of the node that runs the tool",
    );
  });
});

test("systemd unit: carries the family-chat flags only when they are given", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService(
      "green",
      slotOptions({
        familyChatEnabled: true,
        familyChatReplyEnabled: true,
      }),
    );
    const flagged = readFileSync(unitFile(systemd.unitNames.green), "utf8");
    assert.match(flagged, /BNEST_FAMILY_CHAT_ENABLED=true/u);
    assert.match(flagged, /BNEST_FAMILY_CHAT_REPLY_ENABLED=true/u);

    systemd.installSlotService("green", slotOptions());
    const plain = readFileSync(unitFile(systemd.unitNames.green), "utf8");
    assert.doesNotMatch(plain, /BNEST_FAMILY_CHAT/u);
  });
});

function unescapeXml(text) {
  return text
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

// The EnvironmentVariables dictionary of a launchd plist.
function launchdVariables(plist) {
  const dictionary = plist.match(
    /<key>EnvironmentVariables<\/key><dict>(.*?)<\/dict>/su,
  )[1];
  return Object.fromEntries(
    [
      ...dictionary.matchAll(/<key>([^<]+)<\/key><string>([^<]*)<\/string>/gu),
    ].map(([, key, value]) => [key, unescapeXml(value)]),
  );
}

// The Environment lines of a systemd unit, with systemdQuote undone.
function unitVariables(unit) {
  return Object.fromEntries(
    [...unit.matchAll(/^Environment="(.*)"$/gmu)].map(([, quoted]) => {
      const text = quoted.replace(/%%/gu, "%").replace(/\\(.)/gu, "$1");
      const separator = text.indexOf("=");
      return [text.slice(0, separator), text.slice(separator + 1)];
    }),
  );
}

test("systemd unit: carries every launchd slot variable with the same value, except the secrets", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    const launchd = await import("./launchd.mjs");
    const { paths } = await import("./deployment-support.mjs");
    const options = slotOptions({
      familyChatEnabled: true,
      familyChatReplyEnabled: true,
    });
    // The macOS adapter writes its real plist here, so the comparison reads the
    // allowlist the launchd path ships rather than a copy of it.
    launchd.installSlotService("green", options);
    systemd.installSlotService("green", options);
    const expected = launchdVariables(
      readFileSync(
        join(paths.launchAgents, "com.bnest.app.green.plist"),
        "utf8",
      ),
    );
    const actual = unitVariables(
      readFileSync(unitFile(systemd.unitNames.green), "utf8"),
    );
    const secrets = ["RELEASE_COOKIE", "SECRET_KEY_BASE"];
    for (const secret of secrets) {
      assert.ok(secret in expected, `launchd carries ${secret}`);
      assert.equal(secret in actual, false, `the unit omits ${secret}`);
    }
    for (const [key, value] of Object.entries(expected)) {
      if (secrets.includes(key)) continue;
      assert.ok(key in actual, `the systemd unit carries ${key}`);
      // Each adapter builds its own PATH; the PATH test above checks this one.
      if (key !== "PATH")
        assert.equal(actual[key], value, `${key} has the launchd value`);
    }
  });
});

test("systemd unit: writes each production unit file at mode 600", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("blue", slotOptions());
    const unitPath = unitFile(systemd.unitNames.blue);
    assert.equal(statSync(unitPath).mode & 0o777, 0o600);
  });
});

test("systemd unit: names the Caddy, blue, and green units for drop-ins", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const { unitNames } = await import("./systemd.mjs");
    assert.deepEqual(unitNames, {
      caddy: "bnest-caddy.service",
      blue: "bnest-app-blue.service",
      green: "bnest-app-green.service",
    });
  });
});

test("systemd unit: writes the Caddy unit at mode 600 and reloads it through systemctl --user", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installCaddyService();
    const unitPath = unitFile(systemd.unitNames.caddy);
    assert.equal(statSync(unitPath).mode & 0o777, 0o600);
    const unit = readFileSync(unitPath, "utf8");
    assert.match(unit, /^ExecStart=.* run --config .* --adapter caddyfile$/mu);
    assert.match(unit, /^Restart=always$/mu);
    assert.ok(unitSection(unit, "Service").includes("RestartSec=5"));
    assert.ok(unitSection(unit, "Unit").includes("StartLimitIntervalSec=0"));
    // The stub reports the unit active, so an existing Caddy is reloaded.
    assert.deepEqual(systemctlCalls(), [
      "--user daemon-reload",
      "--user is-active --quiet bnest-caddy.service",
      "--user reload bnest-caddy.service",
    ]);
  });
});

test("systemd unit: starts a Caddy unit that is not active with enable --now", async () => {
  await withEnvironment(systemdEnvironment(), () =>
    withStubFlag(systemdInactive, async () => {
      const systemd = await import("./systemd.mjs");
      systemd.installCaddyService();
      assert.deepEqual(systemctlCalls(), [
        "--user daemon-reload",
        "--user is-active --quiet bnest-caddy.service",
        "--user reset-failed bnest-caddy.service",
        "--user enable --now bnest-caddy.service",
      ]);
    }),
  );
});

test("systemd caddy: installs the pinned Caddy tarball after its sha512 check, never through brew", () => {
  // The pin is read from beaver-nest's CI workflow, which is the one place it
  // is kept; the adapter must carry the same version and digest, and check the
  // digest before anything is extracted or installed.
  const adapter = new URL("./systemd.mjs", import.meta.url);
  const source = existsSync(adapter) ? readFileSync(adapter, "utf8") : "";
  const workflow = readFileSync(
    new URL(
      "../../../.github/workflows/scheduled-quality-gates.yml",
      import.meta.url,
    ),
    "utf8",
  );
  const digest = workflow.match(
    /CADDY_LINUX_AMD64_SHA512: "([0-9a-f]{128})"/u,
  )?.[1];
  const version = workflow.match(/CADDY_VERSION: "([0-9.]+)"/u)?.[1];
  assert.ok(digest, "the workflow pins a Caddy sha512");
  assert.ok(version, "the workflow pins a Caddy version");
  assert.ok(source.includes(digest), "the adapter pins the workflow's sha512");
  assert.ok(
    source.includes(version),
    "the adapter pins the workflow's version",
  );

  const check = source.search(/createHash\("sha512"\)/u);
  const extract = source.indexOf('"tar"');
  assert.ok(check >= 0, "the adapter computes a sha512 digest");
  assert.ok(extract > check, "the digest is checked before extraction");
  assert.doesNotMatch(source, /"brew"/u);
});

test("systemd caddy: refuses a download that does not match the pinned digest and installs nothing", async () => {
  const home = join(systemdRoot, "caddy-home");
  mkdirSync(home, { recursive: true });
  rmSync(curlLog, { force: true });
  await withEnvironment(
    systemdEnvironment({
      HOME: home,
      PATH: `${caddyBin}:${systemdBin}:${process.env.PATH}`,
    }),
    async () => {
      const systemd = await import("./systemd.mjs");
      assert.throws(
        () => systemd.ensureCaddy("x64"),
        /does not match its pinned sha512/u,
      );
      assert.match(readFileSync(curlLog, "utf8"), /--output/u);
      assert.equal(existsSync(systemd.caddyBinary()), false);
    },
  );
});

test("systemd caddy: names the host architecture and downloads nothing outside linux x64", async () => {
  const home = join(systemdRoot, "caddy-architecture-home");
  mkdirSync(home, { recursive: true });
  rmSync(curlLog, { force: true });
  await withEnvironment(
    systemdEnvironment({
      HOME: home,
      PATH: `${caddyBin}:${systemdBin}:${process.env.PATH}`,
    }),
    async () => {
      const systemd = await import("./systemd.mjs");
      // The pinned archive is the linux amd64 build; any other host would fail
      // later, with an exec format error, so it is refused before any download.
      assert.throws(
        () => systemd.ensureCaddy("arm64"),
        /pinned for linux x64 only; this host is arm64/u,
      );
      assert.equal(existsSync(curlLog), false);
      assert.equal(existsSync(systemd.caddyBinary()), false);
    },
  );
});

test("platform: darwin selects the launchd adapter", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const { serviceAdapter } = await import("./service-adapter.mjs");
    assert.equal(serviceAdapter("darwin"), await import("./launchd.mjs"));
  });
});

test("platform: linux selects the systemd adapter", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const { serviceAdapter } = await import("./service-adapter.mjs");
    assert.equal(serviceAdapter("linux"), await import("./systemd.mjs"));
  });
});

test("platform: an unsupported value is refused with a named error", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const { serviceAdapter } = await import("./service-adapter.mjs");
    assert.throws(
      () => serviceAdapter("freebsd"),
      /unsupported platform "freebsd"/u,
    );
  });
});

test("platform: both adapters provide the one interface the orchestrator calls", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const required = [
      "caddyBinary",
      "ensureCaddy",
      "installCaddyService",
      "installSlotService",
      "retireSlot",
      "copyRelease",
    ];
    for (const adapter of ["./launchd.mjs", "./systemd.mjs"]) {
      const module = await import(adapter);
      for (const name of required)
        assert.equal(
          typeof module[name],
          "function",
          `${adapter} exports ${name}`,
        );
    }
  });
});

test("systemd unit: retires a slot through systemctl --user and refuses the active slot", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    // The refusal reports through the shared failure path, which sets the exit
    // status; restore it so that this expected refusal does not fail the run.
    const savedExitCode = process.exitCode;
    try {
      assert.throws(
        () => systemd.retireSlot("blue"),
        /Refuse to retire the active slot/u,
      );
    } finally {
      process.exitCode = savedExitCode;
    }
    systemd.retireSlot("green");
    assert.deepEqual(systemctlCalls(), [
      "--user disable --now bnest-app-green.service",
    ]);
  });
});

test("systemd unit: copies a release tree with its file modes intact", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    const source = join(systemdRoot, "copy-source");
    const destination = join(systemdRoot, "copy-destination");
    mkdirSync(join(source, "bin"), { recursive: true });
    writeFileSync(join(source, "bin", "bnest_app"), "#!/bin/sh\n", {
      mode: 0o755,
    });
    systemd.copyRelease(source, destination);
    const copied = join(destination, "bin", "bnest_app");
    assert.equal(readFileSync(copied, "utf8"), "#!/bin/sh\n");
    assert.equal(statSync(copied).mode & 0o777, 0o755);
  });
});

test("systemd unit: creates a missing releases parent before copying a release", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    // A fresh deploy root has no releases/ folder yet. macOS ditto creates it;
    // cp -a does not, so the adapter must.
    const source = join(systemdRoot, "fresh-source");
    const freshRoot = join(systemdRoot, "fresh-deploy-root");
    const destination = join(freshRoot, "releases", revision);
    mkdirSync(join(source, "bin"), { recursive: true });
    writeFileSync(join(source, "bin", "bnest_app"), "#!/bin/sh\n", {
      mode: 0o755,
    });
    systemd.copyRelease(source, destination);
    assert.equal(
      readFileSync(join(destination, "bin", "bnest_app"), "utf8"),
      "#!/bin/sh\n",
    );
    assert.equal(statSync(join(freshRoot, "releases")).mode & 0o777, 0o700);
  });
});

test("fail-closed: an unsupported platform stops the tool before any file is written", () => {
  // A child process reports `freebsd` as its platform, so the real startup
  // path runs. The command is deliberately not a real one: it touches no
  // network and no service, and the home and deployment roots must stay empty.
  const home = join(systemdRoot, "fail-closed-home");
  const deployment = join(systemdRoot, "fail-closed-deployment");
  mkdirSync(home, { recursive: true });
  mkdirSync(deployment, { recursive: true });
  const preload = join(systemdRoot, "report-freebsd.cjs");
  writeFileSync(
    preload,
    'Object.defineProperty(process, "platform", { value: "freebsd" });\n',
  );
  const result = spawnSync(
    process.execPath,
    [
      "--require",
      preload,
      fileURLToPath(new URL("./deployment.mjs", import.meta.url)),
      "fail-closed-probe",
    ],
    {
      encoding: "utf8",
      env: systemdEnvironment({ HOME: home, BNEST_DEPLOY_ROOT: deployment }),
    },
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsupported platform "freebsd"/u);
  assert.deepEqual(readdirSync(home, { recursive: true }), []);
  assert.deepEqual(readdirSync(deployment, { recursive: true }), []);
});
