import path from "node:path";

// Mirrors BnestApp.TestInstance.Paths.derive/4 in apps/bnest-app/test/support/test_instance_paths.ex.
// The shared fixture apps/bnest-app/test/fixtures/test_instance_paths.json pins both sides, so a change
// to either implementation must change the fixture as well. Checks run in the Elixir order: run id,
// instance id, flat root, SQLite root. Nothing here touches the filesystem.

const instanceIdPattern = /^[a-z0-9]{16}$/u;
const runIdPattern = /^[a-z0-9][a-z0-9_-]{0,127}$/u;
const markerName = ".bnest-test-instance.json";
const databaseFile = "bnest.sqlite3";

export type TestInstancePathInput = {
  flatRunRoot: unknown;
  sqliteRunRoot: unknown;
  runId: unknown;
  instanceId: unknown;
};

export type TestInstancePaths = {
  runId: string;
  instanceId: string;
  shortId: string;
  generation: string;
  flatRunRoot: string;
  sqliteRunRoot: string;
  flatInstanceRoot: string;
  sqliteInstanceRoot: string;
  flatMarkerPath: string;
  sqliteMarkerPath: string;
  dbDirectory: string;
  dbFile: string;
  backupRepositoryDirectory: string;
  storageConfigDirectory: string;
  storagePointerPath: string;
  backupConfigPath: string;
};

export type TestInstancePathError =
  "invalid_run_id" | "invalid_instance_id" | "invalid_root";

export type DeriveTestInstancePathsResult =
  | { ok: true; paths: TestInstancePaths }
  | { ok: false; error: TestInstancePathError };

export function deriveTestInstancePaths(
  input: TestInstancePathInput,
): DeriveTestInstancePathsResult {
  const { flatRunRoot, sqliteRunRoot, runId, instanceId } = input;

  if (!isRunId(runId)) return { ok: false, error: "invalid_run_id" };
  if (!isInstanceId(instanceId))
    return { ok: false, error: "invalid_instance_id" };
  if (!isRoot(flatRunRoot, runId) || !isRoot(sqliteRunRoot, runId)) {
    return { ok: false, error: "invalid_root" };
  }

  return {
    ok: true,
    paths: build(flatRunRoot, sqliteRunRoot, runId, instanceId),
  };
}

function isRunId(value: unknown): value is string {
  return typeof value === "string" && runIdPattern.test(value);
}

function isInstanceId(value: unknown): value is string {
  return typeof value === "string" && instanceIdPattern.test(value);
}

// A root must be absolute, already normalised (no `..`, `.`, `//` or trailing slash) and named
// exactly after its run. `path.posix.resolve` removes the same forms that `Path.expand` removes.
function isRoot(root: unknown, runId: string): root is string {
  return (
    typeof root === "string" &&
    root.startsWith("/") &&
    path.posix.resolve(root) === root &&
    path.posix.basename(root) === runId
  );
}

function build(
  flatRunRoot: string,
  sqliteRunRoot: string,
  runId: string,
  instanceId: string,
): TestInstancePaths {
  const flatInstanceRoot = path.posix.join(
    flatRunRoot,
    "instances",
    instanceId,
  );
  const sqliteInstanceRoot = path.posix.join(
    sqliteRunRoot,
    "instances",
    instanceId,
  );
  const dbDirectory = path.posix.join(sqliteInstanceRoot, "db");
  const storageConfigDirectory = path.posix.join(
    sqliteRunRoot,
    "storage-config",
  );

  return {
    runId,
    instanceId,
    shortId: instanceId.slice(0, 8),
    generation: `test-${instanceId}`,
    flatRunRoot,
    sqliteRunRoot,
    flatInstanceRoot,
    sqliteInstanceRoot,
    flatMarkerPath: path.posix.join(flatInstanceRoot, markerName),
    sqliteMarkerPath: path.posix.join(sqliteInstanceRoot, markerName),
    dbDirectory,
    dbFile: path.posix.join(dbDirectory, databaseFile),
    backupRepositoryDirectory: path.posix.join(
      sqliteInstanceRoot,
      "backup-repository",
    ),
    storageConfigDirectory,
    storagePointerPath: path.posix.join(storageConfigDirectory, "storage.json"),
    backupConfigPath: path.posix.join(storageConfigDirectory, "backup.json"),
  };
}
