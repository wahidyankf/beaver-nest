import { execFileSync, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

import { slots } from "./caddy-config.mjs";

// Shared by the orchestrator and both service adapters. Reads its roots from
// the environment when it loads, so every importer runs under BNEST_DEPLOY_ROOT.
export const repositoryRoot = resolve(import.meta.dirname, "../../..");
export const deploymentRoot = requiredEnvironment("BNEST_DEPLOY_ROOT");
export const paths = {
  config: join(deploymentRoot, "caddy", "Caddyfile"),
  state: join(deploymentRoot, "state.json"),
  // macOS only; read by the launchd adapter.
  launchAgents: join(homedir(), "Library", "LaunchAgents"),
  logs: join(deploymentRoot, "logs"),
  releases: join(deploymentRoot, "releases"),
  slots: join(deploymentRoot, "slots"),
};

export function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) fail(`${name} must point to machine-local deployment state.`);
  return resolve(value);
}

export function fail(message) {
  process.stderr.write(`bnest deployment: ${message}\n`);
  process.exitCode = 1;
  throw new Error(message);
}

export function run(command_, args, options = {}) {
  const result = spawnSync(command_, args, {
    encoding: "utf8",
    stdio: "inherit",
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) fail(`${command_} exited with ${result.status}.`);
}

export function output(command_, args, options = {}) {
  return execFileSync(command_, args, { encoding: "utf8", ...options }).trim();
}

export function writeAtomic(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  const temporary = join(dirname(path), `.${Date.now()}-${process.pid}.tmp`);
  writeFileSync(temporary, contents, { encoding: "utf8", mode: 0o600 });
  renameSync(temporary, path);
}

export function state() {
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
