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
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync, inflateSync } from "node:zlib";
import test, { after, beforeEach } from "node:test";

import { caddyfile, slots } from "./caddy-config.mjs";
import {
  boundedReleaseEnvironment,
  executeRelease,
  exitCodeFor,
  gateManifest,
  MachineHost,
  refuseRemovedMode,
  ReleaseError,
  render,
  requiredOrigin,
  requiredPath,
  verifyMigrationManifest,
} from "./release.mjs";
import { normalizeProductionOrigin } from "./production-origin.mjs";

const revision = "0123456789abcdef0123456789abcdef01234567";

// The launchd slot and Caddy code moved to launchd.mjs; the orchestrator
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
      "release-family-chat-e2e",
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
  // Deployment passes the existing runtime VAPID values to both slots
  // unconditionally, since `config/runtime.exs` raises in `:prod` on every
  // boot when these are absent -- a candidate that launchd starts without
  // them never becomes ready. `launchAgent`'s `variables` object is a
  // hard-coded allowlist (unlike a plain `...process.env` spread), so a key
  // missing from it here is a key the launchd-managed process never receives.
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

test("routes a replacement handshake only to the promoted slot's port, never the prior slot's", () => {
  // The promoted slot's health-checked configuration names exactly one upstream: the promoted
  // slot's own port. The prior slot stays warm but receives no routed handshake, so its port
  // must not appear anywhere in the configuration.
  for (const promoted of Object.keys(slots)) {
    const prior = Object.keys(slots).find((slot) => slot !== promoted);
    const config = caddyfile(promoted, true);
    const upstreams = [...config.matchAll(/reverse_proxy\s+(\S+)/gu)].map(
      (match) => match[1],
    );

    assert.deepEqual(upstreams, [`127.0.0.1:${slots[promoted]}`]);
    assert.doesNotMatch(config, new RegExp(`:${slots[prior]}\\b`, "u"));
  }
});

test("denies the testing control path and strips its header in every generated Caddyfile", () => {
  // ADR 001 section 2, second layer: the compile-time gate already answers 404,
  // and Caddy also refuses `/__bnest_testing` and `/__bnest_testing/*` with 404
  // and removes the `x-bnest-testing` header before the request reaches the
  // upstream slot. A `/*` path matcher does not match the bare path.
  for (const slot of Object.keys(slots)) {
    for (const healthChecked of [true, false]) {
      const config = caddyfile(slot, healthChecked);
      const proxy = config.indexOf("\treverse_proxy ");
      assert.match(
        config,
        /^\t@bnest_testing path \/__bnest_testing \/__bnest_testing\/\*$/mu,
        `${slot} ${healthChecked}: matcher`,
      );
      const deny = config.indexOf("\trespond @bnest_testing 404\n");
      assert.ok(deny >= 0 && deny < proxy, `${slot}: 404 before the proxy`);
      const strip = config.indexOf("\t\theader_up -X-Bnest-Testing\n");
      assert.ok(strip > proxy, `${slot}: header stripped inside the proxy`);
    }
  }
});

// Synthetic BEAM files: the IFF form the audit reads (FOR1 and BEAM, an AtU8
// atom table, and an optional zlib-compressed LitT literal table). They carry
// no compiled code, so the audit tests need no Erlang or Elixir toolchain.
function beamChunk(id, data) {
  const header = Buffer.alloc(8);
  header.write(id, 0, "latin1");
  header.writeUInt32BE(data.length, 4);
  return Buffer.concat([
    header,
    data,
    Buffer.alloc((4 - (data.length % 4)) % 4),
  ]);
}

// Older OTP releases zlib-compress the literal table behind a size word; newer
// ones keep it plain, as the real test-build router shows.
function literalChunkData(literals, compressed) {
  if (!compressed) return Buffer.from(literals, "utf8");
  const size = Buffer.alloc(4);
  size.writeUInt32BE(Buffer.byteLength(literals));
  return Buffer.concat([size, deflateSync(literals)]);
}

function syntheticBeam({ atoms = [], literals, compressed = true }) {
  const names = atoms.map((atom) => Buffer.from(atom, "utf8"));
  const count = Buffer.alloc(4);
  count.writeUInt32BE(names.length);
  const chunks = [
    beamChunk(
      "AtU8",
      Buffer.concat([
        count,
        ...names.flatMap((name) => [Buffer.from([name.length]), name]),
      ]),
    ),
  ];
  if (literals !== undefined)
    chunks.push(beamChunk("LitT", literalChunkData(literals, compressed)));
  const body = Buffer.concat([Buffer.from("BEAM", "latin1"), ...chunks]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length);
  return Buffer.concat([Buffer.from("FOR1", "latin1"), length, body]);
}

const cleanRouter = syntheticBeam({
  atoms: ["Elixir.BnestAppWeb.Router", "Elixir.BnestAppWeb.Endpoint"],
  literals: "/health/ready",
});

function syntheticRelease(root, { router = cleanRouter, beams = {} } = {}) {
  const ebin = join(root, "lib", "bnest_app-0.1.0", "ebin");
  mkdirSync(ebin, { recursive: true });
  const files = {
    "Elixir.BnestApp.Storage.beam": syntheticBeam({
      atoms: ["Elixir.BnestApp.Storage"],
    }),
    ...beams,
  };
  if (router !== null) files["Elixir.BnestAppWeb.Router.beam"] = router;
  for (const [name, bytes] of Object.entries(files))
    writeFileSync(join(ebin, name), bytes);
  return root;
}

function withTempRelease(run, options) {
  const parent = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-"));
  try {
    return run(syntheticRelease(join(parent, "release"), options));
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
}

async function loadArtifactAudit() {
  return import("./release-artifact-audit.mjs");
}

test("audits a release whose beams carry no testing module or testing string", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  assert.deepEqual(
    withTempRelease((root) => auditReleaseArtifact(root)),
    { ebins: 1, beams: 2 },
  );
});

test("refuses a testing module beam in any ebin", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  for (const name of [
    "Elixir.BnestApp.TestInstance.beam",
    "Elixir.BnestAppWeb.TestingControl.Plug.beam",
    "Elixir.BnestApp.TestRuntimeRoot.beam",
  ]) {
    assert.throws(
      () =>
        withTempRelease((root) => auditReleaseArtifact(root), {
          beams: { [name]: syntheticBeam({ atoms: ["Elixir.Test"] }) },
        }),
      (error) => error.violations.some((violation) => violation.includes(name)),
      name,
    );
  }
});

test("refuses a router that names the testing path or a testing module", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  const routers = {
    "the testing path as a raw atom": syntheticBeam({
      atoms: ["Elixir.BnestAppWeb.Router", "__bnest_testing"],
    }),
    "a testing control module name": syntheticBeam({
      atoms: [
        "Elixir.BnestAppWeb.Router",
        "Elixir.BnestAppWeb.TestingControl.Plug",
      ],
    }),
    "a test instance module name": syntheticBeam({
      atoms: ["Elixir.BnestAppWeb.Router", "Elixir.BnestApp.TestInstance"],
    }),
  };
  for (const [label, router] of Object.entries(routers)) {
    assert.throws(
      () => withTempRelease((root) => auditReleaseArtifact(root), { router }),
      (error) =>
        error.violations.some((violation) => violation.includes("Router.beam")),
      label,
    );
  }
});

test("refuses a testing path that only sits in a compressed literal table", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  const router = syntheticBeam({
    atoms: ["Elixir.BnestAppWeb.Router"],
    literals: "/__bnest_testing/v1/state",
  });
  // The fixture only proves the compressed case when the raw file lacks the bytes.
  assert.equal(router.includes("__bnest_testing"), false);
  assert.throws(
    () => withTempRelease((root) => auditReleaseArtifact(root), { router }),
    (error) =>
      error.violations.some((violation) => violation.includes("Router.beam")),
  );
});

test("fails closed when the router beam or the ebin directories are missing", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  assert.throws(
    () =>
      withTempRelease((root) => auditReleaseArtifact(root), { router: null }),
    (error) =>
      error.violations.some((violation) =>
        violation.includes("Elixir.BnestAppWeb.Router.beam is missing"),
      ),
  );
  const empty = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-empty-"));
  try {
    assert.throws(
      () => auditReleaseArtifact(empty),
      (error) =>
        error.violations.some((violation) => violation.includes("no ebin")),
    );
  } finally {
    rmSync(empty, { recursive: true, force: true });
  }
});

test("reads a plain literal table, as newer OTP releases write it", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  const clean = syntheticBeam({
    atoms: ["Elixir.BnestAppWeb.Router"],
    literals: "/health/ready",
    compressed: false,
  });
  assert.deepEqual(
    withTempRelease((root) => auditReleaseArtifact(root), { router: clean }),
    { ebins: 1, beams: 2 },
  );
  const testing = syntheticBeam({
    atoms: ["Elixir.BnestAppWeb.Router"],
    literals: "/__bnest_testing/v1/state",
    compressed: false,
  });
  assert.throws(
    () =>
      withTempRelease((root) => auditReleaseArtifact(root), {
        router: testing,
      }),
    (error) =>
      error.violations.some((violation) =>
        violation.includes("names __bnest_testing"),
      ),
  );
});

test("refuses a symbolic link that could hide an ebin from the walk", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  const hidden = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-hidden-"));
  try {
    const ebin = join(hidden, "ebin");
    mkdirSync(ebin);
    writeFileSync(
      join(ebin, "Elixir.BnestApp.TestInstance.beam"),
      syntheticBeam({ atoms: ["Elixir.BnestApp.TestInstance"] }),
    );
    withTempRelease((root) => {
      symlinkSync(hidden, join(root, "lib", "bnest_app-0.1.0", "linked"));
      assert.throws(
        () => auditReleaseArtifact(root),
        (error) =>
          error.violations.some((violation) =>
            violation.includes("symbolic link"),
          ),
      );
    });
  } finally {
    rmSync(hidden, { recursive: true, force: true });
  }
});

test("reports an unreadable release as an audit violation, not a crash", async () => {
  const { auditReleaseArtifact, ReleaseArtifactAuditError } =
    await loadArtifactAudit();
  const parent = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-file-"));
  try {
    const file = join(parent, "not-a-directory");
    writeFileSync(file, "synthetic");
    assert.throws(
      () => auditReleaseArtifact(file),
      (error) => error instanceof ReleaseArtifactAuditError,
    );
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

// A compiled stub module named like a test-only module. It was built from a synthetic source name and
// stripped of debug info, docs, and compile info. The audit reads only its name and BEAM header.
const realTestBeam = fileURLToPath(
  new URL(
    "./fixtures/release-artifact-audit/Elixir.BnestApp.Test.Contracts.beam",
    import.meta.url,
  ),
);

// The raw file plus every zlib stream found inside a chunk, so a path hidden in a
// compressed chunk (Dbgi or Docs in OTP builds) is checked as well.
function beamScanBuffers(bytes) {
  const buffers = [bytes];
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const size = bytes.readUInt32BE(offset + 4);
    const data = bytes.subarray(offset + 8, offset + 8 + size);
    buffers.push(data);
    for (let index = 0; index < data.length; index += 1) {
      if (data[index] !== 0x78) continue;
      try {
        buffers.push(inflateSync(data.subarray(index)));
      } catch {
        // Not a zlib stream at this offset.
      }
    }
    offset += 8 + size + ((4 - (size % 4)) % 4);
  }
  return buffers;
}

test("the test-build beam fixture holds no local path in any chunk, compressed or not", () => {
  const needles = [
    ["a home directory prefix", "/home/"],
    ["a macOS home prefix", "/Users/"],
    ["the local home directory", homedir()],
  ].filter(([, value]) => value.length > 1);
  for (const buffer of beamScanBuffers(readFileSync(realTestBeam))) {
    const text = buffer.toString("latin1");
    for (const [label, value] of needles)
      assert.equal(text.includes(value), false, `fixture holds ${label}`);
  }
});

test("refuses a real compiled test-build beam by its module name", async () => {
  const { auditReleaseArtifact } = await loadArtifactAudit();
  const beam = readFileSync(realTestBeam);
  assert.equal(beam.toString("latin1", 0, 4), "FOR1");
  assert.equal(beam.toString("latin1", 8, 12), "BEAM");

  assert.throws(
    () =>
      withTempRelease((root) => auditReleaseArtifact(root), {
        beams: { "Elixir.BnestApp.Test.Contracts.beam": beam },
      }),
    (error) =>
      error.violations.includes(
        "lib/bnest_app-0.1.0/ebin/Elixir.BnestApp.Test.Contracts.beam: test-only module",
      ),
  );
});

test("reports a router beam that cannot be read as a violation that names the file", async () => {
  const { auditReleaseArtifact, ReleaseArtifactAuditError } =
    await loadArtifactAudit();
  const routerLabel = "lib/bnest_app-0.1.0/ebin/Elixir.BnestAppWeb.Router.beam";
  const cases = {
    "no FOR1 or BEAM header": [
      Buffer.from("synthetic text that is not a beam file"),
      "missing FOR1/BEAM header",
    ],
    "a chunk longer than the file": [
      syntheticBeam({ atoms: ["Elixir.BnestAppWeb.Router"] }).subarray(0, 40),
      "truncated chunk",
    ],
  };

  for (const [caseName, [router, reason]] of Object.entries(cases)) {
    assert.throws(
      () => withTempRelease((root) => auditReleaseArtifact(root), { router }),
      (error) =>
        error instanceof ReleaseArtifactAuditError &&
        error.violations.includes(
          `${routerLabel}: unreadable BEAM file (${reason})`,
        ),
      caseName,
    );
  }
});

test("auditBuiltArtifact refuses a dirty artifact as an artifact error and logs the violation", async () => {
  const { auditBuiltArtifact, ReleaseError } = await loadRelease();
  const parent = mkdtempSync(join(tmpdir(), "bnest-build-audit-"));
  const logged = [];

  try {
    const dirty = syntheticRelease(join(parent, "dirty"), {
      beams: {
        "Elixir.BnestApp.TestInstance.beam": syntheticBeam({
          atoms: ["Elixir.BnestApp.TestInstance"],
        }),
      },
    });

    assert.throws(
      () => auditBuiltArtifact(dirty, (message) => logged.push(message)),
      (error) =>
        error instanceof ReleaseError &&
        error.category === "artifact" &&
        error.message === "Release artifact failed the testing-module audit",
    );
    assert.equal(logged.length, 1);
    assert.match(
      logged[0],
      /Elixir\.BnestApp\.TestInstance\.beam: test-only module/u,
    );
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

test("auditBuiltArtifact passes a clean artifact without logging", async () => {
  const { auditBuiltArtifact } = await loadRelease();
  const parent = mkdtempSync(join(tmpdir(), "bnest-build-clean-"));
  const logged = [];

  try {
    const clean = syntheticRelease(join(parent, "clean"));
    assert.deepEqual(
      auditBuiltArtifact(clean, (message) => logged.push(message)),
      { ebins: 1, beams: 2 },
    );
    assert.deepEqual(logged, []);
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

async function loadRelease() {
  return import("./release.mjs");
}

// Runs the real `build` method. Git, the deployment tool, the capacity check and the logs are replaced,
// so only the artifact audit and the manifest write run for real.
async function buildHostFor(deploymentRoot) {
  const { MachineHost } = await loadRelease();
  return new (class ArtifactBuildHost extends MachineHost {
    constructor() {
      super({
        BNEST_DEPLOY_ROOT: deploymentRoot,
        BNEST_PRODUCTION_ORIGIN: "https://service.example",
        HIPPO_BIN: "unused-hippo",
      });
    }

    assertReleaseSource(expectedRevision) {
      return expectedRevision;
    }

    assertCapacity() {}

    run(command, arguments_) {
      if (
        command === "git" &&
        arguments_[0] === "worktree" &&
        arguments_[1] === "remove"
      ) {
        rmSync(arguments_.at(-1), { recursive: true, force: true });
      }
      return { stdout: "", stderr: "", status: 0 };
    }

    deployment(command) {
      assert.equal(command, "release:build");
      return { stdout: `${revision}\n` };
    }
  })();
}

test("build rejects a dirty artifact before it writes the manifest", async () => {
  const deploymentRoot = mkdtempSync(join(tmpdir(), "bnest-build-dirty-"));

  try {
    syntheticRelease(join(deploymentRoot, "releases", revision), {
      beams: {
        "Elixir.BnestApp.TestInstance.beam": syntheticBeam({
          atoms: ["Elixir.BnestApp.TestInstance"],
        }),
      },
    });
    const { ReleaseError } = await loadRelease();
    const host = await buildHostFor(deploymentRoot);

    await assert.rejects(
      () => host.build(revision, ["bnest-quick"]),
      (error) => error instanceof ReleaseError && error.category === "artifact",
    );
    assert.equal(
      existsSync(join(deploymentRoot, "manifests", `${revision}.json`)),
      false,
    );
  } finally {
    rmSync(deploymentRoot, { recursive: true, force: true });
  }
});

test("build records the manifest for a clean artifact", async () => {
  const deploymentRoot = mkdtempSync(join(tmpdir(), "bnest-build-clean-host-"));

  try {
    syntheticRelease(join(deploymentRoot, "releases", revision));
    const host = await buildHostFor(deploymentRoot);

    await host.build(revision, ["bnest-quick"]);
    assert.equal(
      existsSync(join(deploymentRoot, "manifests", `${revision}.json`)),
      true,
    );
  } finally {
    rmSync(deploymentRoot, { recursive: true, force: true });
  }
});

test("the audit command audits a release directory and exits nonzero on a violation", () => {
  const cli = fileURLToPath(
    new URL("./release-artifact-audit.mjs", import.meta.url),
  );
  const clean = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-cli-"));
  const dirty = mkdtempSync(join(tmpdir(), "bnest-artifact-audit-cli-"));
  try {
    syntheticRelease(clean);
    syntheticRelease(dirty, {
      beams: {
        "Elixir.BnestApp.TestInstance.beam": syntheticBeam({ atoms: ["x"] }),
      },
    });
    const passed = spawnSync(process.execPath, [cli, clean], {
      encoding: "utf8",
    });
    assert.equal(passed.status, 0, passed.stderr);
    const failed = spawnSync(process.execPath, [cli, dirty], {
      encoding: "utf8",
    });
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /Elixir\.BnestApp\.TestInstance\.beam/u);
    const usage = spawnSync(process.execPath, [cli], { encoding: "utf8" });
    assert.equal(usage.status, 2);
  } finally {
    rmSync(clean, { recursive: true, force: true });
    rmSync(dirty, { recursive: true, force: true });
  }
});

test("runs the artifact audit right after release:build and records artifact-audit before the manifest", async () => {
  const source = readFileSync(
    new URL("./release.mjs", import.meta.url),
    "utf8",
  );
  const build = source.indexOf('this.deployment("release:build"');
  // The call inside `build`, not the function definition above it.
  const audit = source.indexOf(
    "    auditBuiltArtifact(artifact, (message) => this.log(message));",
  );
  const manifest = source.indexOf("writePrivateJson(join(this.manifestsPath");
  assert.match(
    source,
    /import \{\s*auditReleaseArtifact,\s*ReleaseArtifactAuditError,?\s*\} from "\.\/release-artifact-audit\.mjs";/u,
  );
  assert.ok(build >= 0);
  assert.ok(audit > build);
  assert.ok(manifest > audit);

  const host = fakeHost();
  const result = await executeRelease(host, { drainMs: 0 });
  const position = result.evidenceIds.indexOf("artifact-audit");
  assert.ok(position >= 0);
  assert.equal(result.evidenceIds[position + 1], "artifact-manifest");
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

test("proves the two-member draft/offline/exact-once candidate before promotion", () => {
  // The single-stage release keeps the two-`test-user-`-context
  // draft/offline-queue/reconnect/exact-once proof as an ordinary gate: the
  // same grep the removed second-stage manifest ran, now against the ordinary
  // candidate, before promotion. Exactly one gate carries it.
  const grep =
    "Two members prove draft, offline queue, and exact-once catch-up on the promoted candidate";
  const carriers = gateManifest.filter(({ arguments: arguments_ }) =>
    arguments_.includes(grep),
  );
  assert.equal(carriers.length, 1);
  const gate = carriers[0];
  assert.equal(gate.id, "release-family-chat-e2e");
  assert.ok(gate.arguments.includes("--skip-nx-cache"));
  assert.equal(gate.arguments[2], "bnest-app-fe-e2e");
  assert.deepEqual(gate.arguments.slice(-2), ["--grep", grep]);
});

test("deploy:prepare accepts no family-chat flag key", () => {
  // The room and its replies ship in every slot, so there is no flag to
  // thread: neither the orchestrator nor either service adapter may parse,
  // forward, or emit a family-chat environment key.
  const source = toolSource("deployment.mjs", "launchd.mjs", "systemd.mjs");
  assert.doesNotMatch(source, /family-chat-enabled/u);
  assert.doesNotMatch(source, /familyChatEnabled/u);
  assert.doesNotMatch(source, /familyChatReplyEnabled/u);
  assert.doesNotMatch(source, /BNEST_FAMILY_CHAT/u);
});

test("refuses the removed --mode flag before any host is built", () => {
  assert.doesNotThrow(() => refuseRemovedMode(["--revision", revision]));
  assert.throws(
    () => refuseRemovedMode(["--mode", "compatibility"]),
    (error) =>
      error instanceof ReleaseError &&
      error.category === "configuration" &&
      /--mode.*removed/u.test(error.message),
  );
});

test("refuses every spelling of the removed --mode flag, including the = form", () => {
  for (const argv of [
    ["--mode"],
    ["--mode=experience"],
    ["--mode=compatibility"],
    ["--mode="],
    ["--mode", "compatibility"],
  ]) {
    assert.throws(
      () => refuseRemovedMode(argv),
      (error) =>
        error instanceof ReleaseError &&
        error.category === "configuration" &&
        /--mode.*removed/u.test(error.message),
      argv.join(" "),
    );
  }
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

// Linux deployment support. One isolated fixture serves
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

test("systemd unit: carries no family-chat variable", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("green", slotOptions());
    const unit = readFileSync(unitFile(systemd.unitNames.green), "utf8");
    assert.doesNotMatch(unit, /FAMILY_CHAT/u);
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
    const options = slotOptions();
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

test("systemd unit: starts the slot and Caddy units in the deployment root, not the home directory", async () => {
  await withEnvironment(systemdEnvironment(), async () => {
    const systemd = await import("./systemd.mjs");
    systemd.installSlotService("blue", slotOptions());
    systemd.installCaddyService();
    // Erlang writes erl_crash.dump to the working directory. A unit with none
    // inherits the user's home directory, so the root must be named.
    for (const unit of [systemd.unitNames.blue, systemd.unitNames.caddy]) {
      const text = readFileSync(unitFile(unit), "utf8");
      assert.ok(
        unitSection(text, "Service").includes(
          `WorkingDirectory=${systemdDeployment}`,
        ),
        `${unit} sets its working directory to the deployment root`,
      );
    }
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

// Linux promotion. The new Caddyfile is written beside the live one, so the
// rename that installs it stays on one filesystem; /tmp is often another one.
// The child runs the real deploy:promote under a Linux platform preload, with a
// stub caddy that records each configuration path it is given, a stub curl
// that reports the candidate revision as ready, and a private TMPDIR, so any
// temporary file left behind is visible.
const promotionBin = join(systemdRoot, "promotion-bin");
const promotionCaddyLog = join(systemdRoot, "promotion-caddy.log");
const promotionInvalid = join(systemdRoot, "promotion-caddy-invalid");
const promotionPreload = join(systemdRoot, "report-linux.cjs");
mkdirSync(promotionBin, { recursive: true });
writeFileSync(
  join(promotionBin, "curl"),
  `#!/bin/sh
case " $* " in
  *" -w "*) printf '200' ;;
  *) printf 'HTTP/1.1 200 OK\\r\\nx-bnest-revision: ${revision}\\r\\n' ;;
esac
`,
  { mode: 0o755 },
);
writeFileSync(
  promotionPreload,
  'Object.defineProperty(process, "platform", { value: "linux" });\n',
);

function preparePromotion(name) {
  const home = join(systemdRoot, `${name}-home`);
  const deployment = join(systemdRoot, `${name}-deployment`);
  const temporary = join(systemdRoot, `${name}-tmp`);
  const caddyDirectory = join(deployment, "caddy");
  mkdirSync(join(deployment, "slots"), { recursive: true });
  mkdirSync(caddyDirectory, { recursive: true });
  mkdirSync(temporary, { recursive: true });
  writeFileSync(
    join(deployment, "slots", "green.json"),
    `${JSON.stringify({ revision })}\n`,
  );
  const caddy = join(home, ".local", "bin");
  mkdirSync(caddy, { recursive: true });
  writeFileSync(
    join(caddy, "caddy"),
    `#!/bin/sh
echo "$@" >> "${promotionCaddyLog}"
if [ "$1" = "validate" ] && [ -e "${promotionInvalid}" ]; then exit 1; fi
exit 0
`,
    { mode: 0o755 },
  );
  writeFileSync(promotionCaddyLog, "");
  return { caddyDirectory, deployment, home, temporary };
}

function promoteGreen({ deployment, home, temporary }) {
  return spawnSync(
    process.execPath,
    [
      "--require",
      promotionPreload,
      fileURLToPath(new URL("./deployment.mjs", import.meta.url)),
      "deploy:promote",
      "--slot",
      "green",
    ],
    {
      encoding: "utf8",
      env: systemdEnvironment({
        BNEST_DEPLOY_ROOT: deployment,
        HOME: home,
        PATH: `${promotionBin}:${process.env.PATH}`,
        TMPDIR: temporary,
      }),
    },
  );
}

test("systemd caddy: validates and renames a Caddyfile written beside the live one", () => {
  const promotion = preparePromotion("promote");
  const result = promoteGreen(promotion);
  assert.equal(result.status, 0, result.stderr);

  const calls = readFileSync(promotionCaddyLog, "utf8")
    .split("\n")
    .filter(Boolean);
  const configPaths = calls.map((call) => call.match(/--config (\S+)/u)?.[1]);
  for (const [index, call] of calls.entries()) {
    if (!/^(validate|reload) /u.test(call)) continue;
    assert.equal(
      dirname(configPaths[index]),
      promotion.caddyDirectory,
      `${call.split(" ")[0]} reads the candidate beside the live Caddyfile`,
    );
  }
  assert.match(
    readFileSync(join(promotion.caddyDirectory, "Caddyfile"), "utf8"),
    /reverse_proxy 127\.0\.0\.1:4001/u,
  );
  assert.deepEqual(readdirSync(promotion.caddyDirectory), ["Caddyfile"]);
  assert.deepEqual(readdirSync(promotion.temporary), []);
});

test("systemd caddy: a failed validation leaves the live Caddyfile and no temporary file", () => {
  const promotion = preparePromotion("promote-invalid");
  const live = join(promotion.caddyDirectory, "Caddyfile");
  writeFileSync(live, "previous configuration\n");
  writeFileSync(promotionInvalid, "");
  let result;
  try {
    result = promoteGreen(promotion);
  } finally {
    rmSync(promotionInvalid, { force: true });
  }
  assert.notEqual(result.status, 0);
  assert.equal(readFileSync(live, "utf8"), "previous configuration\n");
  assert.deepEqual(readdirSync(promotion.caddyDirectory), ["Caddyfile"]);
  assert.deepEqual(readdirSync(promotion.temporary), []);
  assert.equal(existsSync(join(promotion.deployment, "state.json")), false);
});

// The deployment commands below are exercised behind doubles: importing the
// module must not run anything, so the tool is imported dynamically after a
// throwaway deploy root is set for the deployment-support module state. Every
// test passes its own paths seam, so the shared root is never written.
process.env.BNEST_DEPLOY_ROOT ??= systemdDeployment;
const { createDeploymentTool } = await import("./deployment.mjs");

const worktreeRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../..",
);

function readRepoJson(relativePath) {
  return JSON.parse(readFileSync(join(worktreeRoot, relativePath), "utf8"));
}

// Captures everything a command writes to stdout while it runs.
function captureStdout(body) {
  const written = [];
  const original = process.stdout.write;
  process.stdout.write = (chunk) => {
    written.push(String(chunk));
    return true;
  };
  try {
    body();
  } finally {
    process.stdout.write = original;
  }
  return written.join("");
}

// Captures everything a command writes to stderr while it runs.
function captureStderr(body) {
  const written = [];
  const original = process.stderr.write;
  process.stderr.write = (chunk) => {
    written.push(String(chunk));
    return true;
  };
  try {
    body();
  } finally {
    process.stderr.write = original;
  }
  return written.join("");
}

// Runs a deployment command that is expected to fail through fail(): asserts
// the exit status and returns the thrown error. The exit status is restored,
// so one expected refusal cannot fail the run.
function expectDeploymentFailure(body) {
  const savedExitCode = process.exitCode;
  process.exitCode = undefined;
  try {
    body();
  } catch (error) {
    assert.equal(process.exitCode, 1);
    return error;
  } finally {
    process.exitCode = savedExitCode;
  }
  assert.fail("expected the deployment command to fail");
}

// A paths seam pointing at an isolated temp root, mirroring the layout the
// deployment-support module builds from BNEST_DEPLOY_ROOT.
function makeDeploymentPaths(root) {
  mkdirSync(join(root, "slots"), { recursive: true });
  mkdirSync(join(root, "logs"), { recursive: true });
  mkdirSync(join(root, "caddy"), { recursive: true });
  return {
    config: join(root, "caddy", "Caddyfile"),
    state: join(root, "state.json"),
    launchAgents: join(root, "launch-agents"),
    logs: join(root, "logs"),
    releases: join(root, "releases"),
    slots: join(root, "slots"),
  };
}

function deploymentTempRoot(name) {
  return mkdtempSync(join(tmpdir(), `bnest-deploy-${name}-`));
}

// A service double that records every adapter call and answers like a healthy
// platform: the Caddy binary is a stub on PATH, slots start, nothing retires.
function recordingService(calls) {
  return {
    caddyBinary: () => "caddy",
    ensureCaddy: () => calls.push("ensure-caddy"),
    installCaddyService: () => calls.push("install-caddy-service"),
    installSlotService: (slot, options) =>
      calls.push(["install-slot", slot, options]),
    copyRelease: (source, destination) =>
      calls.push(["copy-release", source, destination]),
    retireSlot: (slot) => calls.push(["retire-slot", slot]),
  };
}

// The release build must not run in the checkout the release tool runs from:
// npm ci and the Mix build write into the tree, and a dirty source makes
// release:run refuse. A stub npm records any build command that starts.
test("release build: refuses the release checkout itself as its worktree before any build command", () => {
  const home = join(systemdRoot, "build-guard-home");
  const deployment = join(systemdRoot, "build-guard-deployment");
  const bin = join(systemdRoot, "build-guard-bin");
  const npmLog = join(systemdRoot, "build-guard-npm.log");
  mkdirSync(home, { recursive: true });
  mkdirSync(deployment, { recursive: true });
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "npm"),
    `#!/bin/sh\necho "$@" >> "${npmLog}"\nexit 1\n`,
    { mode: 0o755 },
  );
  const checkout = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const result = spawnSync(
    process.execPath,
    [
      fileURLToPath(new URL("./deployment.mjs", import.meta.url)),
      "release:build",
    ],
    {
      encoding: "utf8",
      env: systemdEnvironment({
        BNEST_DEPLOY_ROOT: deployment,
        BNEST_DEPLOY_WORKTREE: checkout,
        HOME: home,
        PATH: `${bin}:${process.env.PATH}`,
      }),
    },
  );
  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /BNEST_DEPLOY_WORKTREE must be an isolated Git worktree/u,
  );
  assert.equal(existsSync(npmLog), false);
});

// BN-DOC-05: each server keeps to its own loopback port range. The Caddy
// configuration is generated by the pure caddyfile/slots pair; the lease
// pools live in package.json and the two E2E project files.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each server keeps to its own loopback port range
test("development commands: each server keeps to its own loopback port range", () => {
  assert.deepEqual(slots, { blue: 4000, green: 4001 });
  for (const [slot, port] of [
    ["blue", 4000],
    ["green", 4001],
  ]) {
    const config = caddyfile(slot, true);
    assert.match(config, /^:4100 \{$/mu);
    assert.match(config, /^\tbind 127\.0\.0\.1$/mu);
    assert.match(
      config,
      new RegExp(`reverse_proxy 127\\.0\\.0\\.1:${port} \\{`, "u"),
    );
  }

  const start = readRepoJson("package.json").scripts.start;
  for (const flag of [
    "--lease-min 4020",
    "--lease-max 4029",
    "--lease-owner development",
  ])
    assert.ok(start.includes(flag), `start script carries ${flag}`);
  assert.match(start, /\$\{BNEST_DEV_PORT:-4020\}/u);

  const beE2e = readRepoJson("apps/bnest-app-be-e2e/project.json")["targets"][
    "test:e2e"
  ]["command"];
  assert.match(beE2e, /--lease-min 4030/u);
  assert.match(beE2e, /--lease-max 4039/u);
  const feE2e = readRepoJson("apps/bnest-app-fe-e2e/project.json")["targets"][
    "test:e2e"
  ]["command"];
  assert.match(feE2e, /--lease-min 4010/u);
  assert.match(feE2e, /--lease-max 4019/u);
});

// Runs the root start script with a recording ./hippo double in place of the
// real HIPPO binary: the double records its argv and the PORT it sees, then
// exits without executing anything, so no server ever boots.
function runStartScript(devPort) {
  const bin = mkdtempSync(join(tmpdir(), "bnest-start-bin-"));
  const argvLog = join(bin, "hippo-argv.log");
  const portLog = join(bin, "hippo-port.log");
  writeFileSync(
    join(bin, "hippo"),
    `#!/bin/sh\necho "$@" > "${argvLog}"\necho "PORT=$PORT" > "${portLog}"\nexit 0\n`,
    { mode: 0o755 },
  );
  const start = readRepoJson("package.json").scripts.start;
  const result = spawnSync(
    "sh",
    ["-c", start.replace("./hippo", join(bin, "hippo"))],
    {
      cwd: worktreeRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        ...(devPort === undefined ? {} : { BNEST_DEV_PORT: devPort }),
      },
    },
  );
  return {
    status: result.status,
    argv: readFileSync(argvLog, "utf8").trim(),
    portLine: readFileSync(portLog, "utf8").trim(),
    cleanup: () => rmSync(bin, { recursive: true, force: true }),
  };
}

// BN-CLI-01 (+BN-CFG-02): npm start serves the development app on its
// loopback port, defaulting to 4020 and following BNEST_DEV_PORT.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: npm start serves the development app on its loopback port
test("development commands: npm start serves the development app on its loopback port", () => {
  for (const [devPort, port] of [
    [undefined, "4020"],
    ["4025", "4025"],
  ]) {
    const run = runStartScript(devPort);
    try {
      assert.equal(run.status, 0);
      for (const flag of [
        "run",
        "--class service",
        `--lease-port ${port}`,
        "--lease-owner development",
        "--lease-min 4020",
        "--lease-max 4029",
        "mix phx.server",
      ])
        assert.ok(run.argv.includes(flag), `hippo argv carries ${flag}`);
      assert.equal(run.portLine, `PORT=${port}`);
    } finally {
      run.cleanup();
    }
  }
});

// BN-CLI-01 integration: the script runs with a hippo double that execs its
// command, then the endpoint config is read back for the port and loopback
// ip. The fake mix records it received phx.server; the config read-back runs
// the real Mix config for the dev profile under a HIPPO admission.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: npm start serves the development app on its loopback port
test("development commands integration: start serves the app on its loopback port", () => {
  const bin = mkdtempSync(join(tmpdir(), "bnest-start-int-bin-"));
  const hippoLog = join(bin, "hippo-argv.log");
  const mixLog = join(bin, "mix-argv.log");
  writeFileSync(
    join(bin, "hippo"),
    `#!/bin/sh\necho "$@" > "${hippoLog}"\nwhile [ "$1" != "--" ] && [ $# -gt 0 ]; do shift; done\nshift\nexec "$@"\n`,
    { mode: 0o755 },
  );
  writeFileSync(
    join(bin, "mix"),
    `#!/bin/sh\necho "$@" > "${mixLog}"\nexit 0\n`,
    { mode: 0o755 },
  );
  const start = readRepoJson("package.json").scripts.start;
  try {
    for (const [devPort, port] of [
      [undefined, "4020"],
      ["4025", "4025"],
    ]) {
      const scriptEnv = { ...process.env, PATH: `${bin}:${process.env.PATH}` };
      if (devPort === undefined) delete scriptEnv.BNEST_DEV_PORT;
      else scriptEnv.BNEST_DEV_PORT = devPort;
      const result = spawnSync(
        "sh",
        ["-c", start.replace("./hippo", join(bin, "hippo"))],
        { cwd: worktreeRoot, encoding: "utf8", env: scriptEnv },
      );
      assert.equal(result.status, 0);
      assert.ok(
        readFileSync(hippoLog, "utf8").includes(`--lease-port ${port}`),
      );
      assert.equal(readFileSync(mixLog, "utf8").trim(), "phx.server");

      const configEnv = { ...process.env };
      if (devPort === undefined) delete configEnv.BNEST_DEV_PORT;
      else configEnv.BNEST_DEV_PORT = devPort;
      // The config read-back leaves the doubles behind and invokes the real
      // Mix through the HIPPO admission used for one-shot runs.
      const config = spawnSync(
        join(worktreeRoot, "hippo"),
        [
          "run",
          "--class",
          "ephemeral",
          "--resource-tier",
          "standard",
          "--disk-path",
          ".",
          "--cwd",
          "apps/bnest-app",
          "--",
          "env",
          `PORT=${port}`,
          "MIX_ENV=dev",
          "mix",
          "run",
          "--no-start",
          "--eval",
          "IO.inspect(Application.get_env(:bnest_app, BnestAppWeb.Endpoint)[:http])",
        ],
        {
          cwd: worktreeRoot,
          encoding: "utf8",
          env: configEnv,
          timeout: 240000,
        },
      );
      assert.equal(config.status, 0, config.stderr);
      assert.match(config.stdout, /ip: \{127, 0, 0, 1\}/u);
      assert.match(config.stdout, new RegExp(`port: ${port}`, "u"));
    }
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }
});

// BN-REL-01 (+BN-DOC-04): release:run builds an immutable artifact,
// promotes it, and prints one JSON result. The full-pass host records the
// step order; the printed line is asserted over the extracted render().
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run builds an immutable artifact, promotes it, and prints one JSON result
test("release: run builds an immutable artifact, promotes it, and prints one JSON result", async () => {
  const host = fakeHost();
  const result = await executeRelease(host, { drainMs: 0 });
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
  assert.deepEqual(result.evidenceIds, [
    "preflight",
    ...gateManifest.map(({ id }) => id),
    "artifact-audit",
    "artifact-manifest",
    "migration-proof",
    "candidate-proof",
    "promotion",
    "routed-liveview",
    "cleanup",
    "convergence",
  ]);
  assert.deepEqual(new Set(result.evidenceIds).size, result.evidenceIds.length);
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.releaseRevision, revision);
  assert.equal(result.fromState, "convergence");
  assert.equal(result.toState, "complete");
  assert.equal(result.outcome, "passed");
  assert.equal(typeof result.durationMs, "number");
  assert.equal(result.nextTransition, "complete");
  assert.equal(result.errorCategory, null);
  assert.equal(result.migrationState, "not-required");
  const line = render(result);
  assert.ok(line.endsWith("\n"));
  assert.deepEqual(JSON.parse(line), JSON.parse(JSON.stringify(result)));
});

// BN-REL-02: release exits 0 for passed, queued, and deferred and 1 for every
// other outcome. Queued and deferred carry nextTransition preflight, so a
// caller retries; the exit mapping is the extracted exitCodeFor().
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release exits 0 for passed, queued, and deferred and 1 for every other outcome
test("release: exits 0 for passed, queued, and deferred and 1 for every other outcome", async () => {
  assert.deepEqual(
    ["passed", "queued", "deferred", "failed", "rolled-back"].map(exitCodeFor),
    [0, 0, 0, 1, 1],
  );
  const throwing = (category, outcome) =>
    fakeHost({
      preflight: async () => {
        throw new ReleaseError(category, `${category} stop`, outcome);
      },
    });
  assert.equal(
    (await executeRelease(throwing("concurrency", "queued"))).outcome,
    "queued",
  );
  assert.equal(
    (await executeRelease(throwing("concurrency", "queued"))).nextTransition,
    "preflight",
  );
  assert.equal(
    (await executeRelease(throwing("capacity", "deferred"))).outcome,
    "deferred",
  );
  assert.equal(
    (await executeRelease(throwing("capacity", "deferred"))).nextTransition,
    "preflight",
  );
  const failed = await executeRelease(throwing("preflight", "failed"));
  assert.equal(failed.outcome, "failed");
  assert.equal(failed.nextTransition, "diagnose");
});

// BN-REL-02 integration, failed row: a child process with no BNEST_DEPLOY_ROOT
// stops at configuration before any host call.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release exits 0 for passed, queued, and deferred and 1 for every other outcome
test("release integration: a missing deploy root stops the release at configuration", () => {
  const environment = { ...process.env };
  delete environment.BNEST_DEPLOY_ROOT;
  const result = spawnSync(
    process.execPath,
    [
      fileURLToPath(new URL("./release.mjs", import.meta.url)),
      "--revision",
      revision,
    ],
    { encoding: "utf8", env: environment },
  );
  assert.equal(result.status, 1);
  assert.deepEqual(JSON.parse(result.stdout), {
    schemaVersion: 1,
    releaseRevision: null,
    fromState: "preflight",
    toState: "stopped",
    outcome: "failed",
    evidenceIds: [],
    durationMs: JSON.parse(result.stdout).durationMs,
    nextTransition: "diagnose",
    errorCategory: "configuration",
    migrationState: "not-required",
  });
});

// BN-CLI-02 (+BN-CLI-03): each npm test command runs its Nx target under a
// HIPPO admission. The recording ./hippo double captures the whole downstream
// command without executing it; the recording npm double proves the e2e chain
// stops after a failing be run through real shell && semantics.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each npm test command runs its Nx target under a HIPPO admission
test("development commands: each npm test command runs its Nx target under a HIPPO admission", () => {
  const bin = mkdtempSync(join(tmpdir(), "bnest-testadm-bin-"));
  const hippoLog = join(bin, "hippo.log");
  writeFileSync(
    join(bin, "hippo"),
    `#!/bin/sh\necho "$@" >> "${hippoLog}"\nexit 0\n`,
    { mode: 0o755 },
  );
  const npmLog = join(bin, "npm.log");
  writeFileSync(
    join(bin, "npm"),
    `#!/bin/sh\necho "$@" >> "${npmLog}"\nexit 0\n`,
    { mode: 0o755 },
  );
  const scripts = readRepoJson("package.json").scripts;
  const hippoCases = [
    ["test", "ephemeral", "standard", "bnest-app", "test:unit"],
    ["test:live", "ephemeral", "standard", "bnest-app", "test:live"],
    ["test:e2e:be", "ephemeral", "standard", "bnest-app-be-e2e", "test:e2e"],
    ["test:e2e:fe", "ephemeral", "heavy", "bnest-app-fe-e2e", "test:e2e"],
  ];
  try {
    for (const [script, admission, tier, project, target] of hippoCases) {
      writeFileSync(hippoLog, "");
      const result = spawnSync(
        "sh",
        ["-c", scripts[script].replace("./hippo", join(bin, "hippo"))],
        {
          cwd: worktreeRoot,
          encoding: "utf8",
          env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
        },
      );
      assert.equal(result.status, 0, scripts[script]);
      const argv = readFileSync(hippoLog, "utf8");
      for (const flag of [
        "run",
        `--class ${admission}`,
        `--resource-tier ${tier}`,
        "--disk-path .",
        "nx",
        `-p ${project}`,
        `-t ${target}`,
      ])
        assert.ok(argv.includes(flag), `${script} admits ${flag}`);
    }

    // The e2e chain runs be then fe and stops after a failing be run.
    writeFileSync(
      join(bin, "npm"),
      `#!/bin/sh\necho "$@" >> "${npmLog}"\nif [ "$2" = "test:e2e:be" ] && [ -n "$FAIL_NPM_BE" ]; then exit 1; fi\nexit 0\n`,
      { mode: 0o755 },
    );
    writeFileSync(npmLog, "");
    const chained = spawnSync("sh", ["-c", scripts["test:e2e"]], {
      cwd: worktreeRoot,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    });
    assert.equal(chained.status, 0);
    assert.deepEqual(readFileSync(npmLog, "utf8").trim().split("\n"), [
      "run test:e2e:be",
      "run test:e2e:fe",
    ]);
    writeFileSync(npmLog, "");
    const failing = spawnSync("sh", ["-c", scripts["test:e2e"]], {
      cwd: worktreeRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        FAIL_NPM_BE: "1",
      },
    });
    assert.notEqual(failing.status, 0);
    assert.deepEqual(readFileSync(npmLog, "utf8").trim().split("\n"), [
      "run test:e2e:be",
    ]);
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }
});

// The refusal text the spec states, read from its scenario, so the tool, the BE
// model, and the spec cannot drift apart without a failing test.
function removedModeMessage() {
  const feature = readFileSync(
    new URL(
      "../../../specs/apps/bnest/app-be/behaviours/release_and_deploy.feature",
      import.meta.url,
    ),
    "utf8",
  );
  const scenario = feature.indexOf(
    "Scenario: release:run fails closed when --mode is passed at all",
  );
  assert.notEqual(scenario, -1, "the spec names the removed-mode scenario");
  const message = /its stderr says "([^"]+)"/u.exec(
    feature.slice(scenario),
  )?.[1];
  assert.ok(message, "the removed-mode scenario states its refusal text");
  return message;
}

test("the BE model mirrors the spec's removed-mode refusal and the = form", () => {
  const modelSource = readFileSync(
    new URL("../test/behaviour/release_and_deploy_model.ex", import.meta.url),
    "utf8",
  );
  assert.ok(
    modelSource.includes(removedModeMessage()),
    "the BE model states the spec's refusal text",
  );
  assert.match(
    modelSource,
    /starts_with\?\([^,]+, "--mode="\)/u,
    "the BE model refuses every --mode= value",
  );
});

// BN-REL-04 integration: node tools/release.mjs --mode (or --mode=<value>), with any value, prints
// one JSON result with outcome failed, errorCategory configuration, a null
// revision, and the removal named on stderr; it exits 1, having taken no lock
// and touched no slot.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run fails closed when --mode is passed at all, with an error naming its removal
test("release integration: fails closed when --mode is passed at all, with an error naming its removal", () => {
  const deployment = deploymentTempRoot("rel-mode");
  try {
    for (const modeArguments of [
      ["--mode", "experience"],
      ["--mode", "compatibility"],
      ["--mode=experience"],
      ["--mode=compatibility"],
      ["--mode="],
    ]) {
      const result = spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL("./release.mjs", import.meta.url)),
          ...modeArguments,
        ],
        {
          encoding: "utf8",
          env: systemdEnvironment({ BNEST_DEPLOY_ROOT: deployment }),
        },
      );
      assert.equal(result.status, 1, `${modeArguments.join(" ")} must fail`);
      assert.equal(
        result.stderr,
        `${removedModeMessage()}\n`,
        `${modeArguments.join(" ")} stderr`,
      );
      assert.deepEqual(JSON.parse(result.stdout), {
        schemaVersion: 1,
        releaseRevision: null,
        fromState: "preflight",
        toState: "stopped",
        outcome: "failed",
        evidenceIds: [],
        durationMs: JSON.parse(result.stdout).durationMs,
        nextTransition: "diagnose",
        errorCategory: "configuration",
        migrationState: "not-required",
      });
    }
    assert.deepEqual(readdirSync(deployment, { recursive: true }), []);
  } finally {
    rmSync(deployment, { recursive: true, force: true });
  }
});

// A deployment tool with recording run/read doubles over an isolated temp
// root. Secrets and origins come from the environment the tests set.
function isolatedDeploymentTool({ arguments_, serviceCalls, runs, reads }) {
  const root = deploymentTempRoot("deploy-unit");
  const paths = makeDeploymentPaths(root);
  const service = recordingService(serviceCalls);
  const tool = createDeploymentTool({
    arguments_,
    paths,
    deploymentRoot: root,
    service,
    run: (command, args, options = {}) => {
      runs.push({ command, args, env: options.env });
      return { status: 0, stdout: "" };
    },
    // A recording double over the real temp files: every read is observed,
    // and cookie and secret files keep their own contents.
    readFileSync: (path, encoding) => {
      reads.push(path);
      return readFileSync(path, encoding);
    },
  });
  return { tool, root, paths };
}

function deploymentSecrets(root) {
  const secrets = join(root, "secrets");
  mkdirSync(secrets, { recursive: true });
  const cookie = join(secrets, "release.cookie");
  const secret = join(secrets, "secret_key_base");
  writeFileSync(cookie, "synthetic-cookie\n");
  writeFileSync(secret, "synthetic-secret\n");
  return { cookie, secret };
}

function completeDeployEnv(root, secrets) {
  return {
    BNEST_RUNTIME_ROOT: join(root, "runtime"),
    BNEST_DEPLOY_COOKIE_FILE: secrets.cookie,
    BNEST_DEPLOY_SECRET_KEY_BASE_FILE: secrets.secret,
    BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE: secrets.cookie,
    BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE: secrets.secret,
    BNEST_WEB_PUSH_SUBJECT: "mailto:synthetic@example.test",
    BNEST_PRODUCTION_ORIGIN: "https://service.example",
  };
}

// BN-REL-06: release:build, release:migrate, and release:converge each run
// one step against the immutable artifact.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:build, release:migrate, and release:converge each run one step against the immutable artifact
test("deployment: release steps run one step each against the immutable artifact", async () => {
  // release:migrate runs the artifact's persistent-schedules migration with
  // the secure-cookie production environment.
  {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: ["release:migrate", "--revision", revision],
      serviceCalls,
      runs,
      reads,
    });
    mkdirSync(join(root, "releases", revision), { recursive: true });
    const secrets = deploymentSecrets(root);
    await withEnvironment(completeDeployEnv(root, secrets), () => {
      const printed = captureStdout(() => tool.dispatch("release:migrate"));
      assert.equal(printed, "");
    });
    assert.equal(runs.length, 1);
    assert.equal(
      runs[0].command,
      join(root, "releases", revision, "bin", "bnest_app"),
    );
    assert.deepEqual(runs[0].args, [
      "eval",
      "BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(DateTime.utc_now())",
    ]);
    for (const [key, value] of [
      ["BNEST_STABLE", "true"],
      ["BNEST_RUNTIME_ROOT", join(root, "runtime")],
      ["BNEST_COOKIE_SECURE", "true"],
      ["PHX_HOST", "service.example"],
      ["RELEASE_DISTRIBUTION", "none"],
      ["RELEASE_COOKIE", "synthetic-cookie"],
      ["SECRET_KEY_BASE", "synthetic-secret"],
    ])
      assert.equal(runs[0].env[key], value, `migration env carries ${key}`);
    rmSync(root, { recursive: true, force: true });
  }

  // release:converge runs the family-chat convergence once, same env shape.
  {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: ["release:converge", "--revision", revision],
      serviceCalls,
      runs,
      reads,
    });
    mkdirSync(join(root, "releases", revision), { recursive: true });
    const secrets = deploymentSecrets(root);
    await withEnvironment(completeDeployEnv(root, secrets), () => {
      captureStdout(() => tool.dispatch("release:converge"));
    });
    assert.equal(runs.length, 1);
    assert.equal(
      runs[0].command,
      join(root, "releases", revision, "bin", "bnest_app"),
    );
    assert.deepEqual(runs[0].args, [
      "eval",
      "BnestApp.Release.Migrations.FamilyChat.converge_after_drain!()",
    ]);
    assert.equal(runs[0].env.RELEASE_DISTRIBUTION, "none");
    assert.equal(runs[0].env.RELEASE_COOKIE, "synthetic-cookie");
    rmSync(root, { recursive: true, force: true });
  }

  // Both refuse an artifact that does not exist.
  for (const command of ["release:migrate", "release:converge"]) {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: [command, "--revision", revision],
      serviceCalls,
      runs,
      reads,
    });
    const secrets = deploymentSecrets(root);
    const error = await withEnvironment(completeDeployEnv(root, secrets), () =>
      expectDeploymentFailure(() => tool.dispatch(command)),
    );
    assert.equal(error.message, `Release ${revision} does not exist.`);
    assert.equal(runs.length, 0);
    rmSync(root, { recursive: true, force: true });
  }

  // release:build refuses an existing release and prints the built revision.
  {
    const runs = [];
    const serviceCalls = [];
    const worktree = deploymentTempRoot("deploy-worktree");
    const root = deploymentTempRoot("deploy-build");
    const output = (command, arguments_) => {
      assert.deepEqual(
        [command, ...arguments_.slice(0, 2)],
        ["git", "-C", worktree],
      );
      return revision;
    };
    const buildTool = createDeploymentTool({
      arguments_: ["release:build"],
      paths: makeDeploymentPaths(root),
      deploymentRoot: root,
      service: recordingService(serviceCalls),
      run: (command, args, options = {}) => {
        runs.push({ command, args, env: options.env });
        return { status: 0, stdout: "" };
      },
      output,
    });
    const printed = await withEnvironment(
      { BNEST_DEPLOY_WORKTREE: worktree },
      () => captureStdout(() => buildTool.dispatch("release:build")),
    );
    assert.equal(printed, `${revision}\n`);
    assert.deepEqual(
      runs.map(({ command }) => command),
      ["npm", "mix", "mix", "mix", "mix"],
    );
    assert.deepEqual(serviceCalls, [
      [
        "copy-release",
        join(root, "build", revision, "rel", "bnest_app"),
        join(root, "releases", revision),
      ],
    ]);

    // A second build refuses to overwrite the immutable artifact.
    mkdirSync(join(root, "releases", revision), { recursive: true });
    const again = await withEnvironment(
      { BNEST_DEPLOY_WORKTREE: worktree },
      () => expectDeploymentFailure(() => buildTool.dispatch("release:build")),
    );
    assert.equal(
      again.message,
      `Release ${revision} already exists; refuse to overwrite an immutable artifact.`,
    );
    rmSync(root, { recursive: true, force: true });
    rmSync(worktree, { recursive: true, force: true });
  }

  // release:build refuses a worktree inside the repository before any build.
  {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: ["release:build"],
      serviceCalls,
      runs,
      reads,
    });
    const error = await withEnvironment(
      { BNEST_DEPLOY_WORKTREE: worktreeRoot },
      () => expectDeploymentFailure(() => tool.dispatch("release:build")),
    );
    assert.equal(
      error.message,
      "BNEST_DEPLOY_WORKTREE must be an isolated Git worktree.",
    );
    assert.equal(runs.length, 0);
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-07: deploy:prepare and deploy:promote take a blue or green slot.
// prepare installs the service and records the revision once ready;
// promote validates and reloads a Caddyfile, then records both slots.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:prepare and deploy:promote take a blue or green slot
test("deployment: prepare and promote take a blue or green slot", async () => {
  // deploy:prepare accepts blue and green and records the revision once the
  // slot is ready.
  for (const slot of ["blue", "green"]) {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { root, paths } = isolatedDeploymentTool({
      arguments_: ["deploy:prepare", "--slot", slot, "--revision", revision],
      serviceCalls,
      runs,
      reads,
    });
    const secrets = deploymentSecrets(root);
    // The status probe asks for the code with -w while readiness reads the
    // headers with -D, so the double answers each shape the tool asks for.
    const curl = (command, args) => {
      assert.equal(command, "curl");
      if (args.includes("-w")) return { status: 0, stdout: "200" };
      return {
        status: 0,
        stdout: `HTTP/1.1 200 OK\r\nx-bnest-revision: ${revision}\r\n`,
      };
    };
    const ready = createDeploymentTool({
      arguments_: ["deploy:prepare", "--slot", slot, "--revision", revision],
      paths,
      deploymentRoot: root,
      service: recordingService(serviceCalls),
      run: (command, args, options = {}) => {
        runs.push({ command, args, env: options.env });
        return { status: 0, stdout: "" };
      },
      readFileSync: (path, encoding) => {
        reads.push(path);
        return readFileSync(path, encoding);
      },
      spawnSync: curl,
    });
    mkdirSync(join(root, "releases", revision), { recursive: true });
    await withEnvironment(completeDeployEnv(root, secrets), () =>
      captureStdout(() => ready.dispatch("deploy:prepare")),
    );
    const installed = serviceCalls.find((call) => call[0] === "install-slot");
    assert.deepEqual(installed[1], slot);
    assert.equal(installed[2].revision, revision);
    assert.equal(installed[2].productionHost, "service.example");
    assert.deepEqual(
      JSON.parse(readFileSync(join(paths.slots, `${slot}.json`), "utf8")),
      {
        revision,
      },
    );
    assert.equal(runs.length, 0);
    rmSync(root, { recursive: true, force: true });
  }

  // deploy:promote validates and reloads a Caddyfile for the slot, then
  // records the previous slot and revision.
  {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const root = deploymentTempRoot("deploy-promote");
    const paths = makeDeploymentPaths(root);
    const curl = (command, args) => {
      if (args.includes("-w")) return { status: 0, stdout: "200" };
      return {
        status: 0,
        stdout: "HTTP/1.1 200 OK\r\nx-bnest-revision: new-revision\r\n",
      };
    };
    const tool = createDeploymentTool({
      arguments_: ["deploy:promote", "--slot", "green"],
      paths,
      deploymentRoot: root,
      service: recordingService(serviceCalls),
      run: (command, args, options = {}) => {
        runs.push({ command, args });
        return { status: 0, stdout: "" };
      },
      readFileSync: (path, encoding) => {
        reads.push(path);
        return readFileSync(path, encoding);
      },
      spawnSync: curl,
      // File-backed like production: promote writes the state file, then the
      // status read sees the routed slot instead of a stale double.
      state: () => {
        try {
          return JSON.parse(readFileSync(paths.state, "utf8"));
        } catch {
          return {
            activeSlot: "blue",
            activeRevision: revision,
            previousSlot: null,
            previousRevision: null,
            healthChecked: false,
          };
        }
      },
    });
    writeFileSync(
      join(paths.slots, "green.json"),
      `${JSON.stringify({ revision: "new-revision" })}\n`,
    );
    const printed = captureStdout(() => tool.dispatch("deploy:promote"));
    const status = JSON.parse(printed);
    assert.equal(status.activeSlot, "green");
    assert.equal(status.activeRevision, "new-revision");
    assert.equal(status.previousSlot, "blue");
    assert.equal(status.previousRevision, revision);
    assert.equal(status.probe, "/health/ready");
    assert.equal(status.caddyReady, true);
    assert.equal(status.httpStatus, "200");
    assert.match(
      readFileSync(paths.config, "utf8"),
      /reverse_proxy 127\.0\.0\.1:4001/u,
    );
    const configCalls = runs.filter(({ args }) => args.includes("--config"));
    assert.ok(configCalls.length >= 2);
    for (const { args } of configCalls)
      assert.equal(
        dirname(args[args.indexOf("--config") + 1]),
        dirname(paths.config),
      );
    rmSync(root, { recursive: true, force: true });
  }

  // Any other value or a missing --slot is refused.
  for (const args of [
    ["deploy:prepare", "--slot", "teal", "--revision", revision],
    ["deploy:prepare", "--revision", revision],
    ["deploy:promote", "--slot", "teal"],
    ["deploy:promote"],
  ]) {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: args,
      serviceCalls,
      runs,
      reads,
    });
    const secrets = deploymentSecrets(root);
    const captured = await withEnvironment(
      completeDeployEnv(root, secrets),
      () =>
        captureStderr(() =>
          expectDeploymentFailure(() => tool.dispatch(args[0])),
        ),
    );
    assert.match(
      captured,
      /^bnest deployment: --slot must be blue or green\.\n$/u,
    );
    assert.equal(runs.length, 0);
    assert.equal(serviceCalls.length, 0);
    rmSync(root, { recursive: true, force: true });
  }

  // deploy:prepare without --revision is refused; promote refuses an already
  // active or unprepared slot.
  {
    const runs = [];
    const reads = [];
    const serviceCalls = [];
    const { tool, root } = isolatedDeploymentTool({
      arguments_: ["deploy:prepare", "--slot", "blue"],
      serviceCalls,
      runs,
      reads,
    });
    const secrets = deploymentSecrets(root);
    const missing = await withEnvironment(
      completeDeployEnv(root, secrets),
      () => expectDeploymentFailure(() => tool.dispatch("deploy:prepare")),
    );
    assert.equal(
      missing.message,
      "--revision is required; run release:build first.",
    );
    rmSync(root, { recursive: true, force: true });
  }
  {
    const root = deploymentTempRoot("deploy-promote-refuse");
    const paths = makeDeploymentPaths(root);
    const tool = createDeploymentTool({
      arguments_: ["deploy:promote", "--slot", "blue"],
      paths,
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
      spawnSync: () => ({ status: 0, stdout: `x-bnest-revision: ${revision}` }),
      state: () => ({ activeSlot: "blue", activeRevision: revision }),
    });
    writeFileSync(
      join(paths.slots, "blue.json"),
      `${JSON.stringify({ revision })}\n`,
    );
    const active = expectDeploymentFailure(() =>
      tool.dispatch("deploy:promote"),
    );
    assert.equal(active.message, "blue is already active.");
    const unprepared = createDeploymentTool({
      arguments_: ["deploy:promote", "--slot", "green"],
      paths,
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
      spawnSync: () => ({ status: 0, stdout: "" }),
      state: () => ({ activeSlot: "blue", activeRevision: revision }),
    });
    const missing = expectDeploymentFailure(() =>
      unprepared.dispatch("deploy:promote"),
    );
    assert.equal(missing.message, "green has not been prepared.");
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-07 integration: prepare and promote run as child processes with
// caddy, curl and systemctl doubles and a temp deploy root.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:prepare and deploy:promote take a blue or green slot
test("deployment integration: prepare and promote take a blue or green slot", () => {
  const root = deploymentTempRoot("deploy-slot-int");
  const home = deploymentTempRoot("deploy-slot-home");
  const bin = join(root, "bin");
  const curlLog = join(root, "curl.log");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "curl"),
    `#!/bin/sh\necho "$@" >> "${curlLog}"\ncase " $* " in\n  *" -w "*) printf '200' ;;\n  *) printf 'HTTP/1.1 200 OK\\r\\nx-bnest-revision: ${revision}\\r\\n' ;;\nesac\n`,
    { mode: 0o755 },
  );
  // The systemd adapter resolves Caddy to its install path under the home
  // directory, so the double lives there rather than on PATH.
  const caddyHome = join(home, ".local", "bin");
  mkdirSync(caddyHome, { recursive: true });
  writeFileSync(join(caddyHome, "caddy"), "#!/bin/sh\nexit 0\n", {
    mode: 0o755,
  });
  writeFileSync(join(bin, "systemctl"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
  try {
    const secrets = deploymentSecrets(root);
    mkdirSync(join(root, "releases", revision), { recursive: true });
    mkdirSync(join(root, "caddy"), { recursive: true });
    const env = {
      ...process.env,
      HOME: home,
      BNEST_DEPLOY_ROOT: root,
      PATH: `${bin}:${process.env.PATH}`,
      ...completeDeployEnv(root, secrets),
    };
    const deployment = fileURLToPath(
      new URL("./deployment.mjs", import.meta.url),
    );
    const prepare = spawnSync(
      process.execPath,
      [deployment, "deploy:prepare", "--slot", "green", "--revision", revision],
      { encoding: "utf8", env },
    );
    assert.equal(prepare.status, 0, prepare.stderr);
    assert.deepEqual(
      JSON.parse(readFileSync(join(root, "slots", "green.json"), "utf8")),
      {
        revision,
      },
    );
    const promote = spawnSync(
      process.execPath,
      [deployment, "deploy:promote", "--slot", "green"],
      { encoding: "utf8", env },
    );
    assert.equal(promote.status, 0, promote.stderr);
    const status = JSON.parse(promote.stdout);
    assert.equal(status.activeSlot, "green");
    assert.equal(status.activeRevision, revision);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
});

// BN-REL-08: promotion waits up to 60 seconds for the slot to report its
// revision. awaitReady takes an injected clock and a curl double: the slot
// answers at once and the wait ends, or it never does and the wait fails
// after 60 seconds without touching a real slot.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: Promotion waits up to 60 seconds for the slot to report its revision
test("deployment: promotion waits up to 60 seconds for the slot revision", () => {
  // The slot answers with the revision header at once and the wait proceeds.
  {
    const root = deploymentTempRoot("deploy-ready");
    const tool = createDeploymentTool({
      arguments_: [],
      paths: makeDeploymentPaths(root),
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
      spawnSync: () => ({
        status: 0,
        stdout: `HTTP/1.1 200 OK\r\nx-bnest-revision: ${revision}\r\n`,
      }),
    });
    tool.awaitReady("blue", revision);
    rmSync(root, { recursive: true, force: true });
  }

  // The slot answers with the wrong revision, so the wait runs the clock to
  // 60 seconds and fails with the fixed line and exit 1.
  {
    const root = deploymentTempRoot("deploy-timeout");
    let virtualNow = 1_000_000;
    let sleeps = 0;
    const curls = [];
    const tool = createDeploymentTool({
      arguments_: [],
      paths: makeDeploymentPaths(root),
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
      spawnSync: (command, args) => {
        curls.push(args.at(-1));
        return {
          status: 0,
          stdout: "HTTP/1.1 200 OK\r\nx-bnest-revision: stale\r\n",
        };
      },
      now: () => virtualNow,
      sleep: () => {
        sleeps += 1;
        virtualNow += 500;
      },
    });
    const error = expectDeploymentFailure(() =>
      tool.awaitReady("green", revision),
    );
    assert.equal(
      error.message,
      "green did not become ready within 60 seconds.",
    );
    assert.ok(virtualNow - 1_000_000 >= 60_000);
    assert.ok(sleeps > 0);
    assert.ok(curls.length > 1);
    assert.ok(
      curls.every((url) => url === "http://127.0.0.1:4001/health/ready"),
    );
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-08 integration, ready row: a curl double answers at once and the
// promotion proceeds. (The timeout row has no integration seam that shortens
// a child's clock, so the injected-clock row above is its proof.)
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: Promotion waits up to 60 seconds for the slot to report its revision
test("deployment integration: promotion proceeds when the slot answers at once", () => {
  const root = deploymentTempRoot("deploy-ready-int");
  const home = deploymentTempRoot("deploy-ready-home");
  const bin = join(root, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "curl"),
    `#!/bin/sh\ncase " $* " in\n  *" -w "*) printf '200' ;;\n  *) printf 'HTTP/1.1 200 OK\\r\\nx-bnest-revision: ${revision}\\r\\n' ;;\nesac\n`,
    { mode: 0o755 },
  );
  try {
    mkdirSync(join(root, "releases", revision), { recursive: true });
    mkdirSync(join(root, "caddy"), { recursive: true });
    const caddyHome = join(home, ".local", "bin");
    mkdirSync(caddyHome, { recursive: true });
    writeFileSync(join(caddyHome, "caddy"), "#!/bin/sh\nexit 0\n", {
      mode: 0o755,
    });
    writeFileSync(join(bin, "systemctl"), "#!/bin/sh\nexit 0\n", {
      mode: 0o755,
    });
    const secrets = deploymentSecrets(root);
    const deployment = fileURLToPath(
      new URL("./deployment.mjs", import.meta.url),
    );
    const env = {
      ...process.env,
      HOME: home,
      BNEST_DEPLOY_ROOT: root,
      PATH: `${bin}:${process.env.PATH}`,
      ...completeDeployEnv(root, secrets),
    };
    const prepare = spawnSync(
      process.execPath,
      [deployment, "deploy:prepare", "--slot", "green", "--revision", revision],
      { encoding: "utf8", env },
    );
    assert.equal(prepare.status, 0, prepare.stderr);
    const promote = spawnSync(
      process.execPath,
      [deployment, "deploy:promote", "--slot", "green"],
      { encoding: "utf8", env },
    );
    assert.equal(promote.status, 0, promote.stderr);
    assert.equal(JSON.parse(promote.stdout).activeSlot, "green");
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
});

// BN-REL-09: deploy:rollback returns traffic to the previous slot or refuses.
// rollback promotes the previous slot; with none recorded the command stops.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:rollback returns traffic to the previous slot or refuses
test("deployment: rollback returns traffic to the previous slot or refuses", () => {
  // A previous slot exists and becomes active again.
  {
    const root = deploymentTempRoot("deploy-rollback");
    const paths = makeDeploymentPaths(root);
    const runs = [];
    const tool = createDeploymentTool({
      arguments_: ["deploy:rollback"],
      paths,
      deploymentRoot: root,
      service: recordingService([]),
      run: (command, args) => {
        runs.push([command, ...args]);
        return { status: 0, stdout: "" };
      },
      spawnSync: (command, args) => {
        if (args.includes("-w")) return { status: 0, stdout: "200" };
        return {
          status: 0,
          stdout: `HTTP/1.1 200 OK\r\nx-bnest-revision: ${revision}\r\n`,
        };
      },
      state: () => {
        try {
          return JSON.parse(readFileSync(paths.state, "utf8"));
        } catch {
          return {
            activeSlot: "green",
            activeRevision: "new",
            previousSlot: "blue",
            previousRevision: revision,
          };
        }
      },
    });
    writeFileSync(
      join(paths.slots, "blue.json"),
      `${JSON.stringify({ revision })}\n`,
    );
    const printed = captureStdout(() => tool.dispatch("deploy:rollback"));
    assert.equal(JSON.parse(printed).activeSlot, "blue");
    assert.ok(
      runs.some(
        ([command, ...args]) => command === "caddy" && args[0] === "reload",
      ),
      "rollback reloads Caddy for the previous slot",
    );
    rmSync(root, { recursive: true, force: true });
  }

  // None exists and the command stops with the fixed line.
  {
    const root = deploymentTempRoot("deploy-rollback-none");
    const paths = makeDeploymentPaths(root);
    const tool = createDeploymentTool({
      arguments_: ["deploy:rollback"],
      paths,
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
      spawnSync: () => ({ status: 0, stdout: "" }),
      state: () => ({ activeSlot: "blue", activeRevision: revision }),
    });
    const error = expectDeploymentFailure(() =>
      tool.dispatch("deploy:rollback"),
    );
    assert.equal(error.message, "No previous slot is available for rollback.");
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-09 integration: rollback with and without a previous slot.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:rollback returns traffic to the previous slot or refuses
test("deployment integration: rollback returns traffic to the previous slot or refuses", () => {
  const root = deploymentTempRoot("deploy-rollback-int");
  const home = deploymentTempRoot("deploy-rollback-home");
  const bin = join(root, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "curl"),
    `#!/bin/sh\ncase " $* " in\n  *" -w "*) printf '200' ;;\n  *) printf 'HTTP/1.1 200 OK\\r\\nx-bnest-revision: ${revision}\\r\\n' ;;\nesac\n`,
    { mode: 0o755 },
  );
  try {
    const caddyHome = join(home, ".local", "bin");
    mkdirSync(caddyHome, { recursive: true });
    writeFileSync(join(caddyHome, "caddy"), "#!/bin/sh\nexit 0\n", {
      mode: 0o755,
    });
    writeFileSync(join(bin, "systemctl"), "#!/bin/sh\nexit 0\n", {
      mode: 0o755,
    });
    mkdirSync(join(root, "caddy"), { recursive: true });
    mkdirSync(join(root, "slots"), { recursive: true });
    writeFileSync(
      join(root, "state.json"),
      `${JSON.stringify({ activeSlot: "green", activeRevision: "new", previousSlot: "blue", previousRevision: revision, healthChecked: true })}\n`,
    );
    writeFileSync(
      join(root, "slots", "blue.json"),
      `${JSON.stringify({ revision })}\n`,
    );
    const deployment = fileURLToPath(
      new URL("./deployment.mjs", import.meta.url),
    );
    const env = {
      ...process.env,
      HOME: home,
      BNEST_DEPLOY_ROOT: root,
      PATH: `${bin}:${process.env.PATH}`,
    };
    const rolled = spawnSync(
      process.execPath,
      [deployment, "deploy:rollback"],
      {
        encoding: "utf8",
        env,
      },
    );
    assert.equal(rolled.status, 0, rolled.stderr);
    assert.equal(JSON.parse(rolled.stdout).activeSlot, "blue");

    writeFileSync(
      join(root, "state.json"),
      `${JSON.stringify({ activeSlot: "blue", activeRevision: revision, healthChecked: false })}\n`,
    );
    const refused = spawnSync(
      process.execPath,
      [deployment, "deploy:rollback"],
      {
        encoding: "utf8",
        env,
      },
    );
    assert.notEqual(refused.status, 0);
    assert.match(
      refused.stderr,
      /No previous slot is available for rollback\./u,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
});

// BN-REL-10: deploy:retire stops a slot through the platform service adapter
// and refuses the active slot. Linux stops the unit with systemctl --user;
// darwin boots it out with launchctl; the active slot is refused.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:retire stops a slot through the platform service adapter and refuses the active slot
test("deployment: retire stops a slot through the platform service adapter and refuses the active slot", async () => {
  // The command reaches the adapter's retireSlot for the named slot.
  {
    const serviceCalls = [];
    const root = deploymentTempRoot("deploy-retire-cmd");
    const tool = createDeploymentTool({
      arguments_: ["deploy:retire", "--slot", "green"],
      paths: makeDeploymentPaths(root),
      deploymentRoot: root,
      service: recordingService(serviceCalls),
      run: () => ({ status: 0, stdout: "" }),
    });
    tool.dispatch("deploy:retire");
    assert.deepEqual(serviceCalls, [["retire-slot", "green"]]);
    rmSync(root, { recursive: true, force: true });
  }

  // The real adapters refuse the active slot and stop any other one: linux
  // through systemctl --user disable --now, darwin through launchctl bootout.
  // The shared systemd fixture has no state file, so the default blue slot is
  // active for every adapter under test.
  await withEnvironment(systemdEnvironment(), async () => {
    const { retireSlot: linuxRetire } = await import("./systemd.mjs");
    const savedExitCode = process.exitCode;
    try {
      assert.throws(
        () => linuxRetire("blue"),
        /Refuse to retire the active slot/u,
      );
    } finally {
      process.exitCode = savedExitCode;
    }
    linuxRetire("green");
    assert.deepEqual(systemctlCalls(), [
      "--user disable --now bnest-app-green.service",
    ]);

    const launchBin = mkdtempSync(join(tmpdir(), "bnest-launchctl-bin-"));
    const launchLog = join(launchBin, "launchctl.log");
    writeFileSync(
      join(launchBin, "launchctl"),
      `#!/bin/sh\necho "$@" > "${launchLog}"\nexit 0\n`,
      { mode: 0o755 },
    );
    try {
      await withEnvironment(
        { PATH: `${launchBin}:${process.env.PATH}` },
        async () => {
          const { retireSlot: darwinRetire } = await import("./launchd.mjs");
          const saved = process.exitCode;
          try {
            assert.throws(
              () => darwinRetire("blue"),
              /Refuse to retire the active slot/u,
            );
          } finally {
            process.exitCode = saved;
          }
          darwinRetire("green");
          assert.match(readFileSync(launchLog, "utf8"), /bootout/u);
        },
      );
    } finally {
      rmSync(launchBin, { recursive: true, force: true });
    }
  });
});

// BN-REL-10 integration: the host's own platform row runs for real with
// systemctl and launchctl doubles on PATH. On this linux host, retiring the
// green slot records the systemd disable call; retiring blue is refused.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:retire stops a slot through the platform service adapter and refuses the active slot
test("deployment integration: retire stops a slot through the host service manager", () => {
  const root = deploymentTempRoot("deploy-retire-int");
  const home = deploymentTempRoot("deploy-retire-home");
  const bin = join(root, "bin");
  mkdirSync(bin, { recursive: true });
  const systemctlLog = join(root, "systemctl.log");
  writeFileSync(
    join(bin, "systemctl"),
    `#!/bin/sh\necho "$@" >> "${systemctlLog}"\nexit 0\n`,
    { mode: 0o755 },
  );
  writeFileSync(join(bin, "launchctl"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
  try {
    writeFileSync(
      join(root, "state.json"),
      `${JSON.stringify({ activeSlot: "blue", activeRevision: revision, healthChecked: false })}\n`,
    );
    const deployment = fileURLToPath(
      new URL("./deployment.mjs", import.meta.url),
    );
    const env = {
      ...process.env,
      HOME: home,
      BNEST_DEPLOY_ROOT: root,
      PATH: `${bin}:${process.env.PATH}`,
    };
    const stopped = spawnSync(
      process.execPath,
      [deployment, "deploy:retire", "--slot", "green"],
      {
        encoding: "utf8",
        env,
      },
    );
    assert.equal(stopped.status, 0, stopped.stderr);
    assert.deepEqual(readFileSync(systemctlLog, "utf8").trim().split("\n"), [
      "--user disable --now bnest-app-green.service",
    ]);
    const refused = spawnSync(
      process.execPath,
      [deployment, "deploy:retire", "--slot", "blue"],
      {
        encoding: "utf8",
        env,
      },
    );
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /Refuse to retire the active slot\./u);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
});

// BN-REL-13: the release builds in a detached worktree and removes it
// afterwards, also when the build fails. MachineHost.build records git
// worktree add, the build, and worktree remove with a run double; remove
// still runs when the build double throws.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release builds in a detached worktree and removes it afterwards, also when the build fails
test("release: the build runs in a detached worktree and removes it afterwards", async () => {
  const root = deploymentTempRoot("rel-worktree");
  try {
    const host = new MachineHost({
      BNEST_DEPLOY_ROOT: root,
      BNEST_PRODUCTION_ORIGIN: "https://service.example",
      HIPPO_BIN: "/bin/true",
    });
    host.assertReleaseSource = () => {};
    const calls = [];
    // The build step fails at npm ci: the worktree is still removed.
    host.run = (command, args) => {
      calls.push([command, ...args]);
      return "";
    };
    host.deployment = () => {
      throw new Error("npm ci failed");
    };
    const evidenceIds = [];
    await assert.rejects(host.build(revision, evidenceIds), /npm ci failed/u);
    assert.equal(calls[0][0], "git");
    assert.deepEqual(calls[0].slice(1, 4), ["worktree", "add", "--detach"]);
    assert.equal(calls[0][4].startsWith(`${tmpdir()}/bnest-release-`), true);
    assert.equal(calls[0][5], revision);
    assert.deepEqual(calls[calls.length - 1].slice(0, 4), [
      "git",
      "worktree",
      "remove",
      "--force",
    ]);
    assert.equal(calls[calls.length - 1][4], calls[0][4]);

    // The build step succeeds: add and remove bracket the same worktree.
    const success = [];
    host.run = (command, args) => {
      success.push([command, ...args]);
      return "";
    };
    host.deployment = () => ({ status: 0, stdout: `${revision}\n` });
    mkdirSync(join(root, "releases", revision), { recursive: true });
    try {
      await host.build(revision, evidenceIds);
    } catch (error) {
      assert.match(
        error.message,
        /audit|artifact|ebin|does not exist|unreadable/u,
      );
    }
    assert.equal(success[0][0], "git");
    assert.deepEqual(success[0].slice(1, 4), ["worktree", "add", "--detach"]);
    assert.deepEqual(success[success.length - 1].slice(0, 4), [
      "git",
      "worktree",
      "remove",
      "--force",
    ]);
    assert.equal(success[success.length - 1][4], success[0][4]);
    // A failed build leaves no worktree behind under the temp directory.
    assert.equal(
      success[0][4] === calls[0][4],
      false,
      "each build uses a fresh worktree directory",
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-13 integration: a temp git repository proves the worktree list
// afterwards equals the list before, while the real build fails fast at
// npm ci inside the worktree.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release builds in a detached worktree and removes it afterwards, also when the build fails
test("release integration: the build uses a detached worktree and removes it", () => {
  const container = deploymentTempRoot("rel-worktree-int");
  const repo = join(container, "repo");
  mkdirSync(repo, { recursive: true });
  const git = (...args) =>
    spawnSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", ...args], {
      cwd: repo,
      encoding: "utf8",
    });
  assert.equal(git("init", "--quiet").status, 0);
  writeFileSync(
    join(repo, "package.json"),
    `${JSON.stringify({ name: "wt", version: "0.0.0" })}\n`,
  );
  assert.equal(git("add", ".").status, 0);
  assert.equal(git("commit", "--quiet", "-m", "init").status, 0);
  const head = git("rev-parse", "HEAD").stdout.trim();
  const before = git("worktree", "list").stdout;
  try {
    // Everything runs for real except the checkout hygiene check (the temp
    // repo is not origin/main) and the git working directory, which the
    // double retargets from the tool checkout to the temp repo. npm ci then
    // fails fast on the lockless package.json, and the worktree is removed.
    const script = `
const { MachineHost } = await import(${JSON.stringify(fileURLToPath(new URL("./release.mjs", import.meta.url)))});
const host = new MachineHost({
  BNEST_DEPLOY_ROOT: ${JSON.stringify(join(container, "deploy"))},
  BNEST_PRODUCTION_ORIGIN: "https://service.example",
  HIPPO_BIN: "/bin/true",
});
host.assertReleaseSource = () => {};
const calls = [];
const realRun = host.run.bind(host);
host.run = (command, args = [], options = {}) => {
  calls.push([command, ...args]);
  if (command === "git") return realRun(command, args, { ...options, cwd: ${JSON.stringify(repo)} });
  return realRun(command, args, options);
};
try {
  await host.build(${JSON.stringify(head)}, []);
  process.stdout.write("BUILD-STATUS: unexpected-pass\\n");
} catch (error) {
  process.stdout.write("BUILD-STATUS: failed\\n");
}
process.stdout.write("CALLS: " + JSON.stringify(calls.map(([command, ...rest]) => [command, ...rest.slice(0, 2)])) + "\\n");
`;
    const result = spawnSync(
      process.execPath,
      ["--input-type=module", "--eval", script],
      {
        encoding: "utf8",
        env: { ...process.env, BNEST_DEPLOY_ROOT: join(container, "deploy") },
        timeout: 120000,
      },
    );
    assert.match(result.stdout, /BUILD-STATUS: failed/u);
    assert.match(result.stdout, /"git","worktree","add"/u);
    assert.match(result.stdout, /"node".*"release:build"/u);
    assert.match(result.stdout, /"git","worktree","remove"/u);
    assert.equal(git("worktree", "list").stdout, before);
  } finally {
    rmSync(container, { recursive: true, force: true });
  }
});

// BN-REL-15: the release tool picks the service manager for the platform and
// stops on any other platform. darwin uses launchd, linux uses systemd;
// win32 and freebsd stop with the fixed line and exit 1 before any command
// runs or any file is written.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release tool picks the service manager for the platform and stops on any other platform
test("deployment: the release tool picks the service manager for the platform", async () => {
  const { serviceAdapter } = await import("./service-adapter.mjs");
  assert.equal(serviceAdapter("darwin"), await import("./launchd.mjs"));
  assert.equal(serviceAdapter("linux"), await import("./systemd.mjs"));
  for (const platform of ["win32", "freebsd"]) {
    assert.throws(
      () => serviceAdapter(platform),
      (error) =>
        error.message ===
        `unsupported platform "${platform}": the release tool supports darwin (launchd) and linux (systemd) only.`,
    );
  }
});

// BN-REL-15 integration, host platform row: the tool proceeds past the
// platform check on this host. (The other platforms cannot be observed from
// this host without injecting code, so the launchd and systemd rows above
// are the proof there.)
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release tool picks the service manager for the platform and stops on any other platform
test("deployment integration: the release tool accepts the host platform", () => {
  const root = deploymentTempRoot("deploy-platform-int");
  try {
    const result = spawnSync(
      process.execPath,
      [
        fileURLToPath(new URL("./deployment.mjs", import.meta.url)),
        "proxy:status",
      ],
      {
        encoding: "utf8",
        env: { ...process.env, BNEST_DEPLOY_ROOT: root, HOME: root },
      },
    );
    assert.doesNotMatch(result.stderr, /unsupported platform/u);
    assert.ok(JSON.parse(result.stdout));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-11: a missing revision or an unknown deployment command is refused.
// Each prints bnest deployment: <message> on stderr and exits 1 with no side
// effect, through the exported dispatcher.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A missing revision or an unknown deployment command is refused
test("deployment: a missing revision or an unknown deployment command is refused", async () => {
  for (const [args, message] of [
    [
      ["deploy:prepare", "--slot", "blue"],
      "--revision is required; run release:build first.",
    ],
    [["release:migrate"], "--revision is required; run release:build first."],
    [["release:converge"], "--revision is required; run release:build first."],
    [["deploy:unknown"], "Unknown deployment command: deploy:unknown"],
    [[], "Unknown deployment command: (missing)"],
  ]) {
    const root = deploymentTempRoot("deploy-dispatch");
    const tool = createDeploymentTool({
      arguments_: args,
      paths: makeDeploymentPaths(root),
      deploymentRoot: root,
      service: recordingService([]),
      run: () => ({ status: 0, stdout: "" }),
    });
    const stderr = await withEnvironment(
      completeDeployEnv(root, deploymentSecrets(root)),
      () =>
        captureStderr(() =>
          expectDeploymentFailure(() => tool.dispatch(args[0])),
        ),
    );
    assert.equal(stderr, `bnest deployment: ${message}\n`);
    assert.equal(existsSync(join(root, "state.json")), false);
    assert.equal(existsSync(join(root, "caddy", "Caddyfile")), false);
    assert.deepEqual(readdirSync(join(root, "slots")), []);
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-11 integration: the same refusals as child processes with a temp
// deploy root.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A missing revision or an unknown deployment command is refused
test("deployment integration: a missing revision or an unknown deployment command is refused", () => {
  const deployment = fileURLToPath(
    new URL("./deployment.mjs", import.meta.url),
  );
  for (const [args, message] of [
    [
      ["deploy:prepare", "--slot", "blue"],
      "--revision is required; run release:build first.",
    ],
    [["release:migrate"], "--revision is required; run release:build first."],
    [["release:converge"], "--revision is required; run release:build first."],
    [["deploy:unknown"], "Unknown deployment command: deploy:unknown"],
    [[], "Unknown deployment command: (missing)"],
  ]) {
    const root = deploymentTempRoot("deploy-dispatch-int");
    const result = spawnSync(process.execPath, [deployment, ...args], {
      encoding: "utf8",
      env: { ...process.env, BNEST_DEPLOY_ROOT: root },
    });
    assert.equal(result.status, 1);
    // The refusal line comes first; node then reports the uncaught throw.
    assert.ok(result.stderr.startsWith(`bnest deployment: ${message}\n`));
    assert.deepEqual(readdirSync(root, { recursive: true }), []);
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-12: a deploy root inside the repository or a production origin that
// is not a bare HTTPS origin is refused. The pure checks are requiredPath and
// requiredOrigin over an environment double; under release:run the same
// causes give a JSON result with outcome failed and errorCategory
// configuration.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
test("deployment: a bad deploy root or production origin is refused", () => {
  assert.equal(
    requiredPath(
      { BNEST_DEPLOY_ROOT: "/tmp/bnest-deploy" },
      "BNEST_DEPLOY_ROOT",
    ),
    "/tmp/bnest-deploy",
  );
  for (const [environment, message] of [
    [{}, "BNEST_DEPLOY_ROOT is required"],
    [
      { BNEST_DEPLOY_ROOT: worktreeRoot },
      "BNEST_DEPLOY_ROOT must be outside the repository",
    ],
    [
      { BNEST_DEPLOY_ROOT: join(worktreeRoot, "apps") },
      "BNEST_DEPLOY_ROOT must be outside the repository",
    ],
  ])
    assert.throws(
      () => requiredPath(environment, "BNEST_DEPLOY_ROOT"),
      new RegExp(`${message}`, "u"),
    );
  assert.equal(
    requiredOrigin(
      { BNEST_PRODUCTION_ORIGIN: "https://service.example" },
      "BNEST_PRODUCTION_ORIGIN",
    ),
    "https://service.example",
  );
  for (const [value, message] of [
    [undefined, "BNEST_PRODUCTION_ORIGIN is required"],
    ["http://service.example", "Production origin must be a bare HTTPS origin"],
    [
      "https://service.example/path",
      "Production origin must be a bare HTTPS origin",
    ],
    [
      "https://user@service.example",
      "Production origin must be a bare HTTPS origin",
    ],
    [
      "https://service.example/?query=1",
      "Production origin must be a bare HTTPS origin",
    ],
    [
      "https://service.example/#fragment",
      "Production origin must be a bare HTTPS origin",
    ],
  ])
    assert.throws(
      () =>
        requiredOrigin(
          value === undefined ? {} : { BNEST_PRODUCTION_ORIGIN: value },
          "BNEST_PRODUCTION_ORIGIN",
        ),
      new RegExp(`BNEST_PRODUCTION_ORIGIN: ${message}`, "u"),
    );
});

// BN-REL-12 integration: child processes for deployment.mjs and release.mjs;
// the checks run before any host call.
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
test("deployment integration: a bad deploy root or production origin is refused", () => {
  const deployment = fileURLToPath(
    new URL("./deployment.mjs", import.meta.url),
  );
  const release = fileURLToPath(new URL("./release.mjs", import.meta.url));

  // A deploy root inside the checkout stops both tools before anything else.
  for (const tool of [deployment, release]) {
    const result = spawnSync(process.execPath, [tool, "proxy:status"], {
      encoding: "utf8",
      env: { ...process.env, BNEST_DEPLOY_ROOT: join(worktreeRoot, "apps") },
    });
    assert.notEqual(result.status, 0);
    if (tool === deployment)
      assert.match(
        result.stderr,
        /BNEST_DEPLOY_ROOT must be outside the repository working tree\./u,
      );
    else {
      assert.equal(JSON.parse(result.stdout).outcome, "failed");
      assert.equal(JSON.parse(result.stdout).errorCategory, "configuration");
    }
  }

  // A missing deploy root stops both tools before anything else.
  for (const tool of [deployment, release]) {
    const environment = { ...process.env };
    delete environment.BNEST_DEPLOY_ROOT;
    const result = spawnSync(process.execPath, [tool, "proxy:status"], {
      encoding: "utf8",
      env: environment,
    });
    assert.notEqual(result.status, 0);
    if (tool === deployment)
      assert.match(
        result.stderr,
        /BNEST_DEPLOY_ROOT must point to machine-local deployment state\./u,
      );
    else {
      assert.equal(JSON.parse(result.stdout).outcome, "failed");
      assert.equal(JSON.parse(result.stdout).errorCategory, "configuration");
    }
  }

  // A production origin that is not a bare HTTPS origin stops the release
  // before any host call.
  {
    const root = deploymentTempRoot("deploy-origin-int");
    const result = spawnSync(
      process.execPath,
      [release, "--revision", revision],
      {
        encoding: "utf8",
        env: {
          ...process.env,
          BNEST_DEPLOY_ROOT: root,
          BNEST_PRODUCTION_ORIGIN: "http://service.example",
        },
      },
    );
    assert.equal(result.status, 1);
    assert.equal(JSON.parse(result.stdout).outcome, "failed");
    assert.equal(JSON.parse(result.stdout).errorCategory, "configuration");
    assert.deepEqual(readdirSync(root, { recursive: true }), []);
    rmSync(root, { recursive: true, force: true });
  }
});

// BN-REL-06 integration: migrate and converge run against a fake
// bin/bnest_app in a temp release that records its argv and environment.
// (A real build is npm ci plus mix release of the whole application.)
// @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:build, release:migrate, and release:converge each run one step against the immutable artifact
test("deployment integration: migrate and converge run the artifact binary with the production environment", () => {
  const root = deploymentTempRoot("deploy-migrate-int");
  const home = deploymentTempRoot("deploy-migrate-home");
  try {
    const release = join(root, "releases", revision);
    mkdirSync(join(release, "bin"), { recursive: true });
    const argvLog = join(root, "argv.log");
    const envLog = join(root, "env.log");
    writeFileSync(
      join(release, "bin", "bnest_app"),
      `#!/bin/sh\necho "$@" > "${argvLog}"\nenv > "${envLog}"\nexit 0\n`,
      { mode: 0o755 },
    );
    const secrets = deploymentSecrets(root);
    const env = {
      ...process.env,
      HOME: home,
      BNEST_DEPLOY_ROOT: root,
      ...completeDeployEnv(root, secrets),
    };
    for (const [command, fragment] of [
      ["release:migrate", "PersistentSchedules.apply_and_verify!"],
      ["release:converge", "FamilyChat.converge_after_drain!"],
    ]) {
      const result = spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL("./deployment.mjs", import.meta.url)),
          command,
          "--revision",
          revision,
        ],
        { encoding: "utf8", env },
      );
      assert.equal(result.status, 0, result.stderr);
      assert.match(readFileSync(argvLog, "utf8"), new RegExp(fragment, "u"));
      const recorded = readFileSync(envLog, "utf8");
      for (const line of [
        "BNEST_STABLE=true",
        "BNEST_COOKIE_SECURE=true",
        "RELEASE_DISTRIBUTION=none",
        "RELEASE_COOKIE=synthetic-cookie",
        "SECRET_KEY_BASE=synthetic-secret",
        "PHX_HOST=service.example",
      ])
        assert.ok(
          recorded.split("\n").includes(line),
          `${command} env carries ${line}`,
        );
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
});

// BN-CLI-04: the tailnet commands drive Tailscale Serve for the Caddy port.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: The tailnet commands drive Tailscale Serve for the Caddy port
test("development commands: the tailnet commands drive Tailscale Serve for the Caddy port", () => {
  const targets = readRepoJson("apps/bnest-app/project.json").targets;
  assert.deepEqual(
    {
      "tailnet:up": targets["tailnet:up"].command,
      "tailnet:status": targets["tailnet:status"].command,
      "tailnet:down": targets["tailnet:down"].command,
    },
    {
      "tailnet:up": "tailscale serve --bg --yes --https=443 --set-path=/ 4100",
      "tailnet:status": "tailscale serve status",
      "tailnet:down": "tailscale serve --https=443 --set-path=/ off",
    },
  );
});

// BN-CLI-04 integration: each target runs with a tailscale double on PATH
// that records its argv and exits 0 or 1; the target's exit status equals the
// double's.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: The tailnet commands drive Tailscale Serve for the Caddy port
test("development commands integration: tailnet targets propagate the tailscale double status", () => {
  const bin = mkdtempSync(join(tmpdir(), "bnest-tailnet-bin-"));
  const argvLog = join(bin, "tailscale-argv.log");
  const targets = readRepoJson("apps/bnest-app/project.json").targets;
  try {
    for (const [command, recorded] of [
      [
        targets["tailnet:up"].command,
        "serve --bg --yes --https=443 --set-path=/ 4100",
      ],
      [targets["tailnet:status"].command, "serve status"],
      [targets["tailnet:down"].command, "serve --https=443 --set-path=/ off"],
    ]) {
      for (const status of [0, 1]) {
        writeFileSync(
          join(bin, "tailscale"),
          `#!/bin/sh\necho "$@" > "${argvLog}"\nexit ${status}\n`,
          { mode: 0o755 },
        );
        const result = spawnSync("sh", ["-c", command], {
          encoding: "utf8",
          env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
        });
        assert.equal(result.status, status, `${command} exits ${status}`);
        assert.equal(readFileSync(argvLog, "utf8").trim(), recorded);
      }
    }
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }
});

// BN-CLI-27 (+BN-GATE-08): each Nx target runs the checks it names, in order.
// The reviewed `test:coverage:behaviour` row is the `test:behaviour:verify`
// target: verify runs the Elixir and Vitest binding checks.
// @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each Nx target runs the checks it names, in order
test("development commands: each Nx target runs the checks it names, in order", () => {
  const targets = readRepoJson("apps/bnest-app/project.json").targets;
  const cases = [
    [
      "lint",
      [
        "mix format --check-formatted",
        "mix credo --strict",
        "npm exec -- oxlint --deny correctness --deny suspicious --deny pedantic --deny perf --deny-warnings --report-unused-disable-directives assets/js",
        "npm exec -- oxlint -A all -D no-restricted-globals --deny-warnings assets/test/unit",
        "mix deps.unlock --check-unused",
      ],
      [],
      false,
    ],
    [
      "typecheck",
      [
        "MIX_ENV=test mix compile --warnings-as-errors --force",
        "MIX_ENV=test mix dialyzer --no-compile --format short",
        "npm exec -- tsc --project assets/tsconfig.json --noEmit",
      ],
      [],
      false,
    ],
    ["format", ["mix format --check-formatted"], [], undefined],
    [
      "test:quick",
      [
        "npm exec -- nx run -p bnest-app -t typecheck",
        "npm exec -- nx run -p bnest-app -t lint",
        "npm exec -- nx run -p bnest-app -t test:unit",
        "npm exec -- nx run -p bnest-app -t test:behaviour:verify",
        "npm exec -- nx run -p bnest-app -t test:behaviour:coverage",
      ],
      [],
      false,
    ],
    [
      "test:integration",
      ["tools/test-integration-denied.sh"],
      ["test-data:cleanup"],
      undefined,
    ],
    [
      "test:live",
      [
        "BNEST_TEST_LAYER=integration MIX_ENV=test mix do compile --warnings-as-errors + test --warnings-as-errors --only ci-exempt --max-cases 1 test/integration/bnest_app/codex_chat/live_codex_test.exs",
      ],
      ["test-data:cleanup"],
      undefined,
    ],
    [
      "test:behaviour:verify",
      [
        "MIX_ENV=test mix run --no-start test/behaviour/verify.exs",
        'npm exec -- vitest run test/behaviour/verify.ts --root assets --config vitest.config.mts --testNamePattern "binding coverage"',
      ],
      [],
      false,
    ],
  ];
  for (const [name, commands, dependsOn, parallel] of cases) {
    const target = targets[name];
    const actual = (target.options?.commands ?? []).map(
      ({ command }) => command,
    );
    assert.deepEqual(
      actual.length > 0 ? actual : [target.command],
      commands,
      `${name} runs its checks in order`,
    );
    assert.deepEqual(target.dependsOn ?? [], dependsOn, `${name} dependencies`);
    assert.equal(target.options?.parallel, parallel, `${name} parallelism`);
  }
});
