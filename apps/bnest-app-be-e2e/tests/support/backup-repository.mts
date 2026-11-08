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
    env: gitChildEnvironment(),
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`backup repository init failed: ${result.stderr}`);
  }
}

// A pre-push hook exports git's repository variables (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, and more), and a child
// git inherits them, so `git init <path>` would act on the hook's repository instead of creating one at <path>. Every
// GIT_* name is removed from the environment a git child receives, so each child works on the repository it names.
export function gitChildEnvironment(): NodeJS.ProcessEnv {
  const environment: NodeJS.ProcessEnv = {};
  for (const [name, value] of Object.entries(process.env)) {
    if (!name.startsWith("GIT_")) environment[name] = value;
  }
  return environment;
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
