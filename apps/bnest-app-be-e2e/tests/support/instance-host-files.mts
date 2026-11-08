import { existsSync } from "node:fs";
import { deriveTestInstancePaths } from "./test-instance-paths.mts";

// The host files one test instance makes, derived from the same pure paths the server uses (ADR 001, section 3).
// A scenario checks them after the delete, so teardown is proved on the filesystem and not only through the server's
// own report. Nothing here removes or creates anything.

export type RunRoots = {
  flatRunRoot: string;
  sqliteRunRoot: string;
  runId: string;
};

export type InstanceHostFiles = {
  // The flat instance root exists for a flat-primary instance only.
  instanceRoots: [string, string];
  storagePointer: string;
  backupConfiguration: string;
};

export function instanceHostFiles(
  roots: RunRoots,
  instanceId: string,
): InstanceHostFiles {
  const derived = deriveTestInstancePaths({ ...roots, instanceId });
  if (!derived.ok) {
    throw new Error(`cannot derive the instance paths: ${derived.error}`);
  }
  const { paths } = derived;
  return {
    instanceRoots: [paths.flatInstanceRoot, paths.sqliteInstanceRoot],
    storagePointer: paths.storagePointerPath,
    backupConfiguration: paths.backupConfigPath,
  };
}

// The paths of `files` that exist now, in a fixed order.
export function presentHostFiles(files: InstanceHostFiles): string[] {
  return [
    ...files.instanceRoots,
    files.storagePointer,
    files.backupConfiguration,
  ].filter((entry) => existsSync(entry));
}
