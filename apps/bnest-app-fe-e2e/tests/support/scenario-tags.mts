import path from "node:path";

const backupRepositoryTag = "@backup-repository";
const openSetupTag = "@open-setup";
const instanceIdPattern = /^[a-z0-9]{16}$/u;

// `@open-setup` keeps `/setup` open, so its instance is seeded with no account. Only a flat-primary instance
// keeps setup open (ADR 001, section 2), so the tag belongs with `@flat-primary`. Every other flat-primary
// scenario is seeded like a SQLite-primary one.
export function seedsAccountsForTags(tags: readonly string[]): boolean {
  return !tags.includes(openSetupTag);
}

// `@backup-repository` marks a scenario that uses Backup's default destination. A spawn leaves the instance's
// `backup-repository/` an empty directory, and that destination fails closed unless the directory is a git
// repository that ignores `data/`, so the scenario's Before hook makes it one (ADR 001, section 3).
export function needsBackupRepository(tags: readonly string[]): boolean {
  return tags.includes(backupRepositoryTag);
}

// The instance's backup repository, beside its database under the SQLite run root. The run's storage pointer
// is `<sqlite run root>/storage-config/storage.json`, so the run root is two levels above it.
export function backupRepositoryOf(storageConfig: string, instanceId: string): string {
  if (!path.isAbsolute(storageConfig)) {
    throw new Error("the storage config path must be absolute");
  }
  if (!instanceIdPattern.test(instanceId)) {
    throw new Error("the instance id must be 16 lowercase letters or digits");
  }
  const sqliteRunRoot = path.dirname(path.dirname(storageConfig));
  return path.join(sqliteRunRoot, "instances", instanceId, "backup-repository");
}
