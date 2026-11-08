import { lstatSync, readdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";

// A scenario that saves the default backup destination needs the instance's `backup-repository/` to be an isolated
// git repository that ignores its `data/` folder (ADR 001, section 3). A spawn creates only the empty directory,
// because most scenarios never back up, so the scenario that does makes the repository itself. Only an empty
// `instances/<id>/backup-repository` directory is touched.
const instanceDirectoryName = /^[a-z0-9]{16}$/u;

export function initializeBackupRepository(repository: string): void {
  if (!isInstanceBackupRepository(repository)) {
    throw new Error(
      "the path is not an instance's backup-repository directory",
    );
  }
  let stat;
  try {
    stat = lstatSync(repository);
  } catch {
    throw new Error("the backup repository is not a real directory");
  }
  if (!stat.isDirectory()) {
    throw new Error("the backup repository is not a real directory");
  }
  if (readdirSync(repository).length > 0) {
    throw new Error("the backup repository is not empty");
  }
  writeFileSync(path.join(repository, ".gitignore"), "/data/*\n", {
    encoding: "utf8",
    flag: "wx",
  });
  const result = spawnSync("git", ["init", "--quiet", repository], {
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`backup repository init failed: ${result.stderr}`);
  }
}

function isInstanceBackupRepository(repository: string): boolean {
  const instance = path.dirname(repository);
  return (
    path.isAbsolute(repository) &&
    path.basename(repository) === "backup-repository" &&
    instanceDirectoryName.test(path.basename(instance)) &&
    path.basename(path.dirname(instance)) === "instances"
  );
}
