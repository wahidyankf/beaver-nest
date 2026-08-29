import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  rmSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const appDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(appDirectory, "../../..");
const defaultRoots = [
  path.join(repositoryRoot, "data/test/runs"),
  path.join(os.homedir(), "bnest/data/test/runs"),
];
const owner = "bnest-test-harness";

export function cleanupStaleTestData({
  roots = defaultRoots,
  olderThanHours = 24,
  now = Date.now(),
} = {}) {
  const threshold = now - olderThanHours * 60 * 60 * 1000;
  let removed = 0;
  let retained = 0;

  for (const root of roots) {
    if (!existsSync(root) || lstatSync(root).isSymbolicLink()) continue;

    for (const entry of readdirSync(root, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
      const candidate = path.join(root, entry.name);
      if (path.dirname(path.resolve(candidate)) !== path.resolve(root))
        continue;

      const marker = readMarker(candidate);
      if (!validMarker(marker, entry.name)) {
        retained += 1;
        continue;
      }

      const createdAt = Date.parse(String(marker["createdAt"]));
      if (
        !Number.isFinite(createdAt) ||
        createdAt > threshold ||
        ownerAlive(marker)
      ) {
        retained += 1;
        continue;
      }

      rmSync(candidate, { recursive: true, force: false });
      removed += 1;
    }
  }

  return { removed, retained };
}

function readMarker(candidate) {
  const markerPath = path.join(candidate, ".bnest-test-run.json");
  if (!existsSync(markerPath) || lstatSync(markerPath).isSymbolicLink())
    return undefined;

  try {
    return JSON.parse(readFileSync(markerPath, "utf8"));
  } catch {
    return undefined;
  }
}

function validMarker(marker, runId) {
  return (
    marker?.["schemaVersion"] === 1 &&
    marker?.["recordType"] === "bnest-test-run" &&
    marker?.["runId"] === runId &&
    marker?.["owner"] === owner
  );
}

function ownerAlive(marker) {
  const markerHostname = normalizeHostname(marker["hostname"]);

  if (
    markerHostname &&
    markerHostname !== "local" &&
    markerHostname !== normalizeHostname(os.hostname())
  ) {
    return true;
  }

  const pid = Number(marker["pid"]);
  if (!Number.isInteger(pid) || pid <= 0) return false;

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function normalizeHostname(value) {
  return value ? String(value).toLowerCase().split(".", 1)[0] : "";
}

function parseOlderThanHours(arguments_) {
  if (arguments_.length === 0) return 24;
  if (arguments_.length !== 2 || arguments_[0] !== "--older-than-hours") {
    throw new Error(
      "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]",
    );
  }

  const value = Number(arguments_[1]);
  if (!Number.isFinite(value) || value < 0)
    throw new Error("hours must be non-negative");
  return value;
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const result = cleanupStaleTestData({
    olderThanHours: parseOlderThanHours(process.argv.slice(2)),
  });
  process.stdout.write(
    `test data cleanup: removed=${result.removed} retained=${result.retained}\n`,
  );
}
