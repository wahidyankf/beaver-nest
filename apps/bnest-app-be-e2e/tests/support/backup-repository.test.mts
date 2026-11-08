import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  gitChildEnvironment,
  initializeBackupRepository,
} from "./backup-repository.mts";

// Each test uses a temporary directory laid out like an instance, never data/test or ~/bnest.
function temporaryInstance(): { repository: string; cleanup: () => void } {
  const base = mkdtempSync(
    path.join(os.tmpdir(), "bnest-backup-repository-test-"),
  );
  const repository = path.join(
    base,
    "instances",
    "a1b2c3d4e5f6g7h8",
    "backup-repository",
  );
  mkdirSync(repository, { recursive: true });
  return {
    repository,
    cleanup: () => rmSync(base, { recursive: true, force: true }),
  };
}

test("makes the empty instance directory an isolated git repository that ignores its data folder", () => {
  const { repository, cleanup } = temporaryInstance();
  try {
    initializeBackupRepository(repository);

    assert.equal(
      readFileSync(path.join(repository, ".gitignore"), "utf8"),
      "/data/*\n",
    );
    assert.equal(existsSync(path.join(repository, ".git")), true);
    const ignored = spawnSync(
      "git",
      ["-C", repository, "check-ignore", "-q", "data/backup"],
      { env: gitChildEnvironment() },
    );
    assert.equal(ignored.status, 0);
  } finally {
    cleanup();
  }
});

// A pre-push hook runs with git's repository variables exported, so a child git inherits them and works on the
// hook's repository, not on the new one. The helper must create its own repository whatever the caller exports.
test("creates its own repository even when git's repository variables point at another one", () => {
  const { repository, cleanup } = temporaryInstance();
  const outer = mkdtempSync(
    path.join(os.tmpdir(), "bnest-backup-repository-outer-"),
  );
  const names = ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"] as const;
  const saved = new Map(names.map((name) => [name, process.env[name]]));
  try {
    assert.equal(
      spawnSync("git", ["init", "--quiet", outer], {
        env: gitChildEnvironment(),
      }).status,
      0,
    );
    const gitDir = path.join(outer, ".git");
    const entriesBefore = readdirSync(outer).toSorted();
    const configBefore = readFileSync(path.join(gitDir, "config"), "utf8");
    process.env["GIT_DIR"] = gitDir;
    process.env["GIT_WORK_TREE"] = outer;
    process.env["GIT_INDEX_FILE"] = path.join(gitDir, "index");

    initializeBackupRepository(repository);

    assert.equal(existsSync(path.join(repository, ".git")), true);
    assert.deepEqual(readdirSync(outer).toSorted(), entriesBefore);
    assert.equal(
      readFileSync(path.join(gitDir, "config"), "utf8"),
      configBefore,
    );
    assert.equal(existsSync(path.join(outer, ".gitignore")), false);
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    rmSync(outer, { recursive: true, force: true });
    cleanup();
  }
});

test("refuses a directory that is not an instance's backup repository, and touches nothing", () => {
  const { repository, cleanup } = temporaryInstance();
  try {
    const elsewhere = path.join(path.dirname(repository), "db");
    mkdirSync(elsewhere);
    assert.throws(
      () => initializeBackupRepository(elsewhere),
      /instance's backup-repository/u,
    );
    assert.throws(
      () =>
        initializeBackupRepository(
          path.join(
            path.dirname(path.dirname(repository)),
            "backup-repository",
          ),
        ),
      /instance's backup-repository/u,
    );
    assert.equal(existsSync(path.join(elsewhere, ".git")), false);
  } finally {
    cleanup();
  }
});

test("refuses a directory that already holds something, and a symlink", () => {
  const { repository, cleanup } = temporaryInstance();
  try {
    writeFileSync(path.join(repository, "stray"), "x");
    assert.throws(
      () => initializeBackupRepository(repository),
      /is not empty/u,
    );

    const base = path.dirname(path.dirname(repository));
    const linked = path.join(
      base,
      "instances",
      "z9y8x7w6v5u4t3s2",
      "backup-repository",
    );
    mkdirSync(path.dirname(linked), { recursive: true });
    symlinkSync(repository, linked);
    assert.throws(
      () => initializeBackupRepository(linked),
      /not a real directory/u,
    );
  } finally {
    cleanup();
  }
});

test("refuses a missing directory", () => {
  const { repository, cleanup } = temporaryInstance();
  try {
    rmSync(repository, { recursive: true });
    assert.throws(
      () => initializeBackupRepository(repository),
      /not a real directory/u,
    );
  } finally {
    cleanup();
  }
});
