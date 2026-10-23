// Linux service adapter for the deployment tool (D-11). It writes the systemd
// user units for the two slots and for Caddy, and drives them through
// `systemctl --user`. The orchestrator in deployment.mjs picks this adapter
// when process.platform is "linux".

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { slots } from "./caddy-config.mjs";
import {
  fail,
  paths,
  repositoryRoot,
  run,
  state,
  writeAtomic,
} from "./deployment-support.mjs";

// Unit names are fixed here so that drop-ins can target them (L-02).
export const unitNames = {
  caddy: "bnest-caddy.service",
  blue: "bnest-app-blue.service",
  green: "bnest-app-green.service",
};

// The pin is the one in beaver-nest's scheduled quality gates; a test holds
// this copy equal to that workflow (L-01).
const caddyVersion = "2.11.4";
const caddySha512 =
  "8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9";

export function caddyBinary() {
  return join(homedir(), ".local", "bin", "caddy");
}

// Installs the pinned Caddy when it is missing. The archive's digest is
// checked before anything is extracted or copied into place.
export function ensureCaddy() {
  const binary = caddyBinary();
  if (existsSync(binary)) return;
  const directory = mkdtempSync(join(tmpdir(), "bnest-caddy-"));
  try {
    const archive = join(directory, "caddy.tar.gz");
    run("curl", [
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      "--output",
      archive,
      `https://github.com/caddyserver/caddy/releases/download/v${caddyVersion}/caddy_${caddyVersion}_linux_amd64.tar.gz`,
    ]);
    const digest = createHash("sha512")
      .update(readFileSync(archive))
      .digest("hex");
    if (digest !== caddySha512)
      throw new Error("Caddy archive does not match its pinned sha512.");
    run("tar", [
      "--extract",
      "--gzip",
      "--file",
      archive,
      "--directory",
      directory,
      "caddy",
    ]);
    mkdirSync(dirname(binary), { recursive: true });
    copyFileSync(join(directory, "caddy"), binary);
    chmodSync(binary, 0o755);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

export function installCaddyService() {
  const unit = unitNames.caddy;
  writeAtomic(unitPath(unit), caddyUnit());
  systemctl("daemon-reload");
  if (serviceActive(unit)) systemctl("reload", unit);
  else systemctl("enable", "--now", unit);
}

function caddyUnit() {
  return [
    "[Unit]",
    "Description=Bnest Caddy reverse proxy",
    "",
    "[Service]",
    "Type=simple",
    `ExecStart=${caddyBinary()} run --config ${paths.config} --adapter caddyfile`,
    `ExecReload=${caddyBinary()} reload --config ${paths.config} --adapter caddyfile`,
    "Restart=always",
    `StandardOutput=append:${join(paths.logs, "caddy.log")}`,
    `StandardError=append:${join(paths.logs, "caddy.error.log")}`,
    "",
    "[Install]",
    "WantedBy=default.target",
    "",
  ].join("\n");
}

export function installSlotService(slot, options) {
  const unit = unitNames[slot];
  const environmentPath = join(paths.slots, `${slot}.env`);
  // Secrets live only in this mode 600 file, never in the unit (L-03).
  writeAtomic(environmentPath, secretEnvironment(options));
  writeAtomic(unitPath(unit), slotUnit(slot, { ...options, environmentPath }));
  systemctl("daemon-reload");
  systemctl("enable", unit);
  systemctl("restart", unit);
}

// Stopping a slot that is not routed. Like the launchd adapter, a unit that is
// already gone is not an error.
export function retireSlot(slot) {
  if (state().activeSlot === slot) fail("Refuse to retire the active slot.");
  spawnSync("systemctl", ["--user", "disable", "--now", unitNames[slot]], {
    stdio: "ignore",
  });
}

// cp -a keeps the release's file modes, which the copy must carry; ditto does
// the same job on macOS (L-09).
export function copyRelease(source, destination) {
  run("cp", ["-a", source, destination]);
}

function slotUnit(slot, options) {
  const variables = {
    PATH: servicePath(),
    PHX_SERVER: "true",
    PORT: String(slots[slot]),
    BNEST_STABLE: "true",
    BNEST_RUNTIME_ROOT: options.runtimeRoot,
    BNEST_REPOSITORY_ROOT: repositoryRoot,
    BNEST_CODEX_WORKING_DIRECTORY: repositoryRoot,
    BNEST_COOKIE_SECURE: "true",
    BNEST_IDENTITY_CUTOVER: "true",
    BNEST_RELEASE_REVISION: options.revision,
    BNEST_DEPLOY_SLOT: slot,
    PHX_HOST: options.productionHost,
    RELEASE_DISTRIBUTION: "none",
    BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE: options.webPushPublicKeyFile,
    BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE: options.webPushPrivateKeyFile,
    BNEST_WEB_PUSH_SUBJECT: options.webPushSubject,
    // The family-chat flags appear only when given, as in the launchd adapter.
    ...(options.familyChatEnabled ? { BNEST_FAMILY_CHAT_ENABLED: "true" } : {}),
    ...(options.familyChatReplyEnabled
      ? { BNEST_FAMILY_CHAT_REPLY_ENABLED: "true" }
      : {}),
  };

  return [
    "[Unit]",
    `Description=Bnest app slot ${slot}`,
    "",
    "[Service]",
    "Type=simple",
    `ExecStart=${options.release}/bin/bnest_app start`,
    `EnvironmentFile=${options.environmentPath}`,
    ...Object.entries(variables).map(
      ([key, value]) => `Environment=${systemdQuote(`${key}=${value}`)}`,
    ),
    "Restart=always",
    "LimitNOFILE=4096:8192",
    `StandardOutput=append:${options.logPath}`,
    `StandardError=append:${options.errorPath}`,
    "",
    "[Install]",
    "WantedBy=default.target",
    "",
  ].join("\n");
}

function secretEnvironment(options) {
  const cookie = readFileSync(options.cookieFile, "utf8").trim();
  const secretKeyBase = readFileSync(options.secretKeyBaseFile, "utf8").trim();
  return [
    `RELEASE_COOKIE=${environmentQuote(cookie)}`,
    `SECRET_KEY_BASE=${environmentQuote(secretKeyBase)}`,
    "",
  ].join("\n");
}

// The node that runs this tool comes first, so a unit always finds the same
// node as the release (L-04). Only absolute entries are kept: a relative entry
// would resolve against the service's working directory.
function servicePath() {
  const directories = [
    dirname(process.execPath),
    ...(process.env.PATH || "/usr/local/bin:/usr/bin:/bin").split(":"),
  ];
  return [
    ...new Set(directories.filter((entry) => entry.startsWith("/"))),
  ].join(":");
}

// Systemd unit values: `%` is a specifier, so it is doubled.
function systemdQuote(text) {
  return `"${text.replace(/[\\"]/gu, "\\$&").replace(/%/gu, "%%")}"`;
}

// EnvironmentFile values: double quotes with backslash escapes.
function environmentQuote(text) {
  return `"${text.replace(/[\\"]/gu, "\\$&")}"`;
}

function unitPath(unit) {
  const directory = join(homedir(), ".config", "systemd", "user");
  mkdirSync(directory, { recursive: true });
  return join(directory, unit);
}

function systemctl(...args) {
  run("systemctl", ["--user", ...args]);
}

function serviceActive(unit) {
  return (
    spawnSync("systemctl", ["--user", "is-active", "--quiet", unit], {
      stdio: "ignore",
    }).status === 0
  );
}
