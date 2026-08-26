import { execFileSync, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";

const [command, ...arguments_] = process.argv.slice(2);
const slots = { blue: 4000, green: 4001 };
const label = "com.bnest.caddy";
const repositoryRoot = resolve(import.meta.dirname, "../../..");
const deploymentRoot = requiredEnvironment("BNEST_DEPLOY_ROOT");

if (inside(repositoryRoot, deploymentRoot)) {
  fail("BNEST_DEPLOY_ROOT must be outside the repository working tree.");
}

const paths = {
  config: join(deploymentRoot, "caddy", "Caddyfile"),
  state: join(deploymentRoot, "state.json"),
  launchAgents: join(homedir(), "Library", "LaunchAgents"),
  logs: join(deploymentRoot, "logs"),
  releases: join(deploymentRoot, "releases"),
  slots: join(deploymentRoot, "slots"),
};

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
    retireSlot(requiredSlot());
    break;
  default:
    fail(`Unknown deployment command: ${command || "(missing)"}`);
}

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) fail(`${name} must point to machine-local deployment state.`);
  return resolve(value);
}

function fail(message) {
  process.stderr.write(`bnest deployment: ${message}\n`);
  process.exitCode = 1;
  throw new Error(message);
}

function requiredSlot() {
  const index = arguments_.indexOf("--slot");
  const slot = index >= 0 ? arguments_[index + 1] : undefined;
  if (!(slot in slots)) fail("--slot must be blue or green.");
  return slot;
}

function run(command_, args, options = {}) {
  const result = spawnSync(command_, args, {
    encoding: "utf8",
    stdio: "inherit",
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) fail(`${command_} exited with ${result.status}.`);
}

function output(command_, args, options = {}) {
  return execFileSync(command_, args, { encoding: "utf8", ...options }).trim();
}

function writeAtomic(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  const temporary = join(dirname(path), `.${Date.now()}-${process.pid}.tmp`);
  writeFileSync(temporary, contents, { encoding: "utf8", mode: 0o600 });
  renameSync(temporary, path);
}

function state() {
  if (!existsSync(paths.state))
    return {
      activeSlot: "blue",
      activeRevision: null,
      previousSlot: null,
      previousRevision: null,
      healthChecked: false,
    };

  try {
    const parsed = JSON.parse(readFileSync(paths.state, "utf8"));
    if (!(parsed.activeSlot in slots)) throw new Error("invalid active slot");
    return {
      activeRevision: null,
      healthChecked: false,
      previousRevision: null,
      previousSlot: null,
      ...parsed,
    };
  } catch {
    fail("Deployment state is unreadable; refuse to route traffic blindly.");
  }
}

function caddyfile(slot, healthChecked) {
  const healthCheck = healthChecked ? "\t\thealth_uri /health/ready\n" : "";

  return `{
\tadmin 127.0.0.1:2019
\tgrace_period 5m
}

:4100 {
\tbind 127.0.0.1
\treverse_proxy 127.0.0.1:${slots[slot]} {
\t\theader_up X-Forwarded-Proto https
${healthCheck}
\t\tstream_close_delay 5m
\t}
}
`;
}

function caddyBinary() {
  try {
    return `${output("brew", ["--prefix", "caddy"])}/bin/caddy`;
  } catch {
    return "/opt/homebrew/bin/caddy";
  }
}

function ensureCaddy() {
  if (!existsSync(caddyBinary())) run("brew", ["install", "caddy"]);
}

function caddyLaunchAgent() {
  const binary = caddyBinary();
  const plistPath = join(paths.launchAgents, `${label}.plist`);

  return {
    path: plistPath,
    contents: `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array>
    <string>${binary}</string><string>run</string><string>--config</string><string>${paths.config}</string><string>--adapter</string><string>caddyfile</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${join(paths.logs, "caddy.log")}</string>
  <key>StandardErrorPath</key><string>${join(paths.logs, "caddy.error.log")}</string>
</dict></plist>
`,
  };
}

function installProxy() {
  ensureCaddy();
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

  const agent = caddyLaunchAgent();
  writeAtomic(agent.path, agent.contents);
  const domain = `gui/${process.getuid()}`;

  const installed = spawnSync("launchctl", ["print", `${domain}/${label}`], {
    stdio: "ignore",
  });
  if (installed.status !== 0) {
    run("launchctl", ["bootstrap", domain, agent.path]);
  } else {
    run(caddyBinary(), [
      "reload",
      "--config",
      paths.config,
      "--adapter",
      "caddyfile",
    ]);
  }

  process.stdout.write(
    `Caddy is managed at 127.0.0.1:4100 for ${deploymentState.activeSlot}.\n`,
  );
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

  if (!existsSync(destination)) {
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
    run("ditto", [release, destination]);
  }

  process.stdout.write(`${revision}\n`);
}

function slotLabel(slot) {
  return `com.bnest.app.${slot}`;
}

function slotNode(slot) {
  return `bnest_${slot}@${output("hostname", ["-s"])}`;
}

function prepareSlot(slot) {
  const revision =
    argumentValue("--revision") ||
    fail("--revision is required; run release:build first.");
  const runtimeRoot = requiredEnvironment("BNEST_RUNTIME_ROOT");
  const cookie = requiredEnvironment("BNEST_DEPLOY_COOKIE_FILE");
  const secretKeyBase = requiredEnvironment(
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
  );
  const release = join(paths.releases, revision);
  if (!existsSync(release)) fail(`Release ${revision} does not exist.`);

  const current = state();
  const peer = current.healthChecked ? slotNode(current.activeSlot) : null;
  const plistPath = join(paths.launchAgents, `${slotLabel(slot)}.plist`);
  const logPath = join(paths.logs, `${slot}.log`);
  const errorPath = join(paths.logs, `${slot}.error.log`);
  mkdirSync(paths.logs, { recursive: true });

  writeAtomic(
    plistPath,
    launchAgent(
      slot,
      release,
      runtimeRoot,
      cookie,
      secretKeyBase,
      revision,
      peer,
      logPath,
      errorPath,
    ),
  );

  const domain = `gui/${process.getuid()}`;
  spawnSync("launchctl", ["bootout", `${domain}/${slotLabel(slot)}`], {
    stdio: "ignore",
  });
  run("launchctl", ["bootstrap", domain, plistPath]);
  awaitReady(slot, revision);
  writeAtomic(slotMetadataPath(slot), JSON.stringify({ revision }) + "\n");
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

function launchAgent(
  slot,
  release,
  runtimeRoot,
  cookieFile,
  secretKeyBaseFile,
  revision,
  peer,
  logPath,
  errorPath,
) {
  const variables = {
    PHX_SERVER: "true",
    PORT: String(slots[slot]),
    BNEST_STABLE: "true",
    BNEST_RUNTIME_ROOT: runtimeRoot,
    BNEST_COOKIE_SECURE: "true",
    BNEST_RELEASE_REVISION: revision,
    BNEST_DEPLOY_SLOT: slot,
    RELEASE_DISTRIBUTION: "name",
    RELEASE_NODE: `bnest_${slot}`,
    RELEASE_COOKIE: readFileSync(cookieFile, "utf8").trim(),
    SECRET_KEY_BASE: readFileSync(secretKeyBaseFile, "utf8").trim(),
    ...(peer ? { BNEST_DEPLOY_PEER: peer } : {}),
  };
  const environment = Object.entries(variables)
    .map(
      ([key, value]) => `<key>${key}</key><string>${escapeXml(value)}</string>`,
    )
    .join("");

  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${slotLabel(slot)}</string>
  <key>ProgramArguments</key><array><string>${release}/bin/bnest_app</string><string>start</string></array>
  <key>EnvironmentVariables</key><dict>${environment}</dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${logPath}</string><key>StandardErrorPath</key><string>${errorPath}</string>
</dict></plist>
`;
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

function retireSlot(slot) {
  if (state().activeSlot === slot) fail("Refuse to retire the active slot.");
  spawnSync(
    "launchctl",
    ["bootout", `gui/${process.getuid()}/${slotLabel(slot)}`],
    { stdio: "ignore" },
  );
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

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function inside(parent, child) {
  const path = relative(parent, child);
  return path === "" || (!path.startsWith("..") && !path.startsWith("/"));
}
