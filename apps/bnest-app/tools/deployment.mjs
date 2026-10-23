import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";

import { caddyfile, slots } from "./caddy-config.mjs";
import {
  deploymentRoot,
  fail,
  output,
  paths,
  repositoryRoot,
  requiredEnvironment,
  run,
  state,
  writeAtomic,
} from "./deployment-support.mjs";
import { normalizeProductionOrigin } from "./production-origin.mjs";
import { serviceAdapter } from "./service-adapter.mjs";

const [command, ...arguments_] = process.argv.slice(2);

if (inside(repositoryRoot, deploymentRoot)) {
  fail("BNEST_DEPLOY_ROOT must be outside the repository working tree.");
}

// The platform picks one service adapter; an unsupported platform stops here,
// before any command runs or any file is written (L-05).
let service;
try {
  service = serviceAdapter(process.platform);
} catch (error) {
  fail(error.message);
}

// Shared code keeps calling `caddyBinary()`; the adapter supplies the path.
const caddyBinary = () => service.caddyBinary();

switch (command) {
  case "proxy:install":
    installProxy();
    break;
  case "proxy:status":
    printStatus();
    break;
  case "release:build":
    buildRelease();
    break;
  case "release:migrate":
    migrateRelease();
    break;
  case "release:converge":
    convergeRelease();
    break;
  case "deploy:prepare":
    prepareSlot(requiredSlot());
    break;
  case "deploy:promote":
    promoteSlot(requiredSlot());
    break;
  case "deploy:rollback":
    rollback();
    break;
  case "deploy:retire":
    service.retireSlot(requiredSlot());
    break;
  default:
    fail(`Unknown deployment command: ${command || "(missing)"}`);
}

function requiredProductionOrigin() {
  const value = process.env.BNEST_PRODUCTION_ORIGIN;
  if (!value)
    fail("BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin.");
  try {
    return normalizeProductionOrigin(value);
  } catch (error) {
    fail(error.message);
  }
}

function requiredWebPushSubject() {
  const value = process.env.BNEST_WEB_PUSH_SUBJECT;
  if (!value)
    fail("BNEST_WEB_PUSH_SUBJECT must be a mailto: or https: contact.");
  return value;
}

function requiredSlot() {
  const index = arguments_.indexOf("--slot");
  const slot = index >= 0 ? arguments_[index + 1] : undefined;
  if (!(slot in slots)) fail("--slot must be blue or green.");
  return slot;
}

function printStatus() {
  const deploymentState = state();
  const probe = deploymentState.healthChecked ? "/health/ready" : "/login";
  const result = spawnSync(
    "curl",
    [
      "-sS",
      "--max-time",
      "3",
      "-o",
      "/dev/null",
      "-w",
      "%{http_code}",
      `http://127.0.0.1:4100${probe}`,
    ],
    {
      encoding: "utf8",
    },
  );
  const httpStatus = result.stdout?.trim() || null;
  const caddyReady = result.status === 0 && httpStatus === "200";

  process.stdout.write(
    JSON.stringify(
      {
        activeSlot: deploymentState.activeSlot,
        activeRevision: deploymentState.activeRevision,
        previousSlot: deploymentState.previousSlot || null,
        previousRevision: deploymentState.previousRevision || null,
        probe,
        caddyReady,
        httpStatus,
      },
      null,
      2,
    ) + "\n",
  );

  if (!caddyReady) process.exitCode = 1;
}

function installProxy() {
  service.ensureCaddy();
  mkdirSync(paths.logs, { recursive: true });
  const deploymentState = state();
  writeAtomic(
    paths.config,
    caddyfile(deploymentState.activeSlot, deploymentState.healthChecked),
  );
  run(caddyBinary(), ["fmt", "--overwrite", paths.config]);
  run(caddyBinary(), [
    "validate",
    "--config",
    paths.config,
    "--adapter",
    "caddyfile",
  ]);
  service.installCaddyService();

  process.stdout.write(
    `Caddy is managed at 127.0.0.1:4100 for ${deploymentState.activeSlot}.\n`,
  );
}

function buildRelease() {
  const worktree = requiredEnvironment("BNEST_DEPLOY_WORKTREE");
  if (
    relative(repositoryRoot, worktree) &&
    !relative(repositoryRoot, worktree).startsWith("..")
  ) {
    fail("BNEST_DEPLOY_WORKTREE must be an isolated Git worktree.");
  }

  const revision = output("git", ["-C", worktree, "rev-parse", "HEAD"]);
  const buildPath = join(deploymentRoot, "build", revision);
  const source = join(worktree, "apps", "bnest-app");
  const release = join(buildPath, "rel", "bnest_app");
  const destination = join(paths.releases, revision);

  if (existsSync(destination))
    fail(
      `Release ${revision} already exists; refuse to overwrite an immutable artifact.`,
    );

  run("npm", ["ci"], { cwd: worktree, env: process.env });
  run("mix", ["deps.get", "--only", "prod", "--check-locked"], {
    cwd: source,
    env: { ...process.env, MIX_ENV: "prod", MIX_BUILD_PATH: buildPath },
  });
  run("mix", ["compile"], {
    cwd: source,
    env: { ...process.env, MIX_ENV: "prod", MIX_BUILD_PATH: buildPath },
  });
  run("mix", ["assets.deploy"], {
    cwd: source,
    env: { ...process.env, MIX_ENV: "prod", MIX_BUILD_PATH: buildPath },
  });
  run("mix", ["release", "--overwrite"], {
    cwd: source,
    env: { ...process.env, MIX_ENV: "prod", MIX_BUILD_PATH: buildPath },
  });
  service.copyRelease(release, destination);

  process.stdout.write(`${revision}\n`);
}

function prepareSlot(slot) {
  const revision =
    argumentValue("--revision") ||
    fail("--revision is required; run release:build first.");
  const familyChatEnabled = arguments_.includes("--family-chat-enabled");
  const familyChatReplyEnabled = arguments_.includes(
    "--family-chat-reply-enabled",
  );
  const runtimeRoot = requiredEnvironment("BNEST_RUNTIME_ROOT");
  const cookie = requiredEnvironment("BNEST_DEPLOY_COOKIE_FILE");
  const secretKeyBase = requiredEnvironment(
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
  );
  const webPushPublicKey = requiredEnvironment(
    "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE",
  );
  const webPushPrivateKey = requiredEnvironment(
    "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE",
  );
  const webPushSubject = requiredWebPushSubject();
  const productionOrigin = requiredProductionOrigin();
  const release = join(paths.releases, revision);
  if (!existsSync(release)) fail(`Release ${revision} does not exist.`);

  const logPath = join(paths.logs, `${slot}.log`);
  const errorPath = join(paths.logs, `${slot}.error.log`);
  mkdirSync(paths.logs, { recursive: true });

  // The adapter writes the slot's service definition and starts it.
  service.installSlotService(slot, {
    release,
    runtimeRoot,
    cookieFile: cookie,
    secretKeyBaseFile: secretKeyBase,
    webPushPublicKeyFile: webPushPublicKey,
    webPushPrivateKeyFile: webPushPrivateKey,
    webPushSubject,
    productionHost: productionOrigin.host,
    revision,
    logPath,
    errorPath,
    familyChatEnabled,
    familyChatReplyEnabled,
  });
  awaitReady(slot, revision);
  writeAtomic(slotMetadataPath(slot), JSON.stringify({ revision }) + "\n");
}

function migrateRelease() {
  const revision =
    argumentValue("--revision") ||
    fail("--revision is required; run release:build first.");
  const runtimeRoot = requiredEnvironment("BNEST_RUNTIME_ROOT");
  const cookieFile = requiredEnvironment("BNEST_DEPLOY_COOKIE_FILE");
  const secretKeyBaseFile = requiredEnvironment(
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
  );
  const productionOrigin = requiredProductionOrigin();
  const release = join(paths.releases, revision);
  if (!existsSync(release)) fail(`Release ${revision} does not exist.`);

  run(
    join(release, "bin", "bnest_app"),
    [
      "eval",
      "BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(DateTime.utc_now())",
    ],
    {
      env: {
        ...process.env,
        BNEST_STABLE: "true",
        BNEST_RUNTIME_ROOT: runtimeRoot,
        BNEST_COOKIE_SECURE: "true",
        PHX_HOST: productionOrigin.host,
        RELEASE_DISTRIBUTION: "none",
        RELEASE_COOKIE: readFileSync(cookieFile, "utf8").trim(),
        SECRET_KEY_BASE: readFileSync(secretKeyBaseFile, "utf8").trim(),
      },
    },
  );
}

// Tech-doc 009 ("Backup Schedule Migration"): "After the compatibility
// revision is routed and every runnable slot supports the new Backup
// service, managed release calls a public Scheduler operation that
// force-converges this key once"; and push retention "becomes enabled only
// after old-slot drain." Run once, after `deploy:retire` of the prior slot
// (release.mjs's `drainAndCleanup`), against the newly-routed release's own
// artifact, the same bare-`eval` shape as `migrateRelease` above.
function convergeRelease() {
  const revision =
    argumentValue("--revision") ||
    fail("--revision is required; run release:build first.");
  const runtimeRoot = requiredEnvironment("BNEST_RUNTIME_ROOT");
  const cookieFile = requiredEnvironment("BNEST_DEPLOY_COOKIE_FILE");
  const secretKeyBaseFile = requiredEnvironment(
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
  );
  const productionOrigin = requiredProductionOrigin();
  const release = join(paths.releases, revision);
  if (!existsSync(release)) fail(`Release ${revision} does not exist.`);

  run(
    join(release, "bin", "bnest_app"),
    ["eval", "BnestApp.Release.Migrations.FamilyChat.converge_after_drain!()"],
    {
      env: {
        ...process.env,
        BNEST_STABLE: "true",
        BNEST_RUNTIME_ROOT: runtimeRoot,
        BNEST_COOKIE_SECURE: "true",
        PHX_HOST: productionOrigin.host,
        RELEASE_DISTRIBUTION: "none",
        RELEASE_COOKIE: readFileSync(cookieFile, "utf8").trim(),
        SECRET_KEY_BASE: readFileSync(secretKeyBaseFile, "utf8").trim(),
      },
    },
  );
}

function slotMetadataPath(slot) {
  return join(paths.slots, `${slot}.json`);
}

function preparedRevision(slot) {
  const path = slotMetadataPath(slot);
  if (!existsSync(path)) fail(`${slot} has not been prepared.`);

  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    if (typeof parsed.revision !== "string" || parsed.revision.length === 0)
      throw new Error("invalid revision");
    return parsed.revision;
  } catch {
    fail(`${slot} preparation metadata is unreadable.`);
  }
}

function promoteSlot(slot) {
  const revision = preparedRevision(slot);
  awaitReady(slot, revision);
  const current = state();
  if (current.activeSlot === slot) fail(`${slot} is already active.`);

  const temporary = join(
    tmpdir(),
    `bnest-caddy-${slot}-${process.pid}.caddyfile`,
  );
  writeFileSync(temporary, caddyfile(slot, true), {
    encoding: "utf8",
    mode: 0o600,
  });
  run(caddyBinary(), ["fmt", "--overwrite", temporary]);
  run(caddyBinary(), [
    "validate",
    "--config",
    temporary,
    "--adapter",
    "caddyfile",
  ]);
  run(caddyBinary(), [
    "reload",
    "--config",
    temporary,
    "--adapter",
    "caddyfile",
  ]);
  renameSync(temporary, paths.config);
  writeAtomic(
    paths.state,
    JSON.stringify({
      activeSlot: slot,
      activeRevision: revision,
      previousSlot: current.activeSlot,
      previousRevision: current.activeRevision,
      healthChecked: true,
    }) + "\n",
  );
  printStatus();
}

function rollback() {
  const current = state();
  if (!current.previousSlot)
    fail("No previous slot is available for rollback.");
  promoteSlot(current.previousSlot);
}

function awaitReady(slot, revision) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const result = spawnSync(
      "curl",
      [
        "-fsS",
        "--max-time",
        "2",
        "-D",
        "-",
        "-o",
        "/dev/null",
        `http://127.0.0.1:${slots[slot]}/health/ready`,
      ],
      {
        encoding: "utf8",
      },
    );
    const revisionHeader = `x-bnest-revision: ${revision}`.toLowerCase();
    if (
      result.status === 0 &&
      result.stdout.toLowerCase().split(/\r?\n/u).includes(revisionHeader)
    )
      return;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
  }
  fail(`${slot} did not become ready within 60 seconds.`);
}

function argumentValue(name) {
  const index = arguments_.indexOf(name);
  return index >= 0 ? arguments_[index + 1] : undefined;
}

function inside(parent, child) {
  const path = relative(parent, child);
  return path === "" || (!path.startsWith("..") && !path.startsWith("/"));
}
