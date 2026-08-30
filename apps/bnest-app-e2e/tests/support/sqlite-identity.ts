import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { TestInfo } from "@playwright/test";
import type { StorageScenario } from "./sqlite-storage";
import {
  cleanupTestRuntime,
  createTestRuntime,
  type TestRuntime,
} from "./test-runtime.mts";

export type IdentityStorageScenario = StorageScenario & {
  pairedRuntime: TestRuntime;
};

type EvalResult = { status: number; stdout: string; stderr: string };

const repositoryRoot = process.cwd();
const appDirectory = path.join(repositoryRoot, "apps/bnest-app");

export function isolatedIdentityStorageScenario(
  testInfo: TestInfo,
  label: string,
): IdentityStorageScenario {
  const digest = createHash("sha256")
    .update(
      `${testInfo.project.name}:${testInfo.file}:${testInfo.title}:${label}`,
    )
    .digest("hex")
    .slice(0, 12);
  const runtime = createTestRuntime(`sqlite-identity-${digest}`);
  const pointerDirectory = path.join(runtime.path, "storage-config");
  mkdirSync(pointerDirectory, { recursive: true });

  return {
    flatRoot: runtime.path,
    pointerPath: path.join(pointerDirectory, "storage.json"),
    homeDirectory: os.homedir(),
    runId: runtime.runId,
    pairedRuntime: runtime,
  };
}

export function cleanupIdentityStorageScenario(
  scenario: IdentityStorageScenario,
): void {
  cleanupTestRuntime(scenario.pairedRuntime);
}

export function runStorageEval(
  scenario: IdentityStorageScenario,
  expression: string,
): EvalResult {
  const realHome = os.homedir();
  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: appDirectory,
    env: {
      ...process.env,
      MIX_ENV: "test",
      HOME: realHome,
      BNEST_IDENTITY_CUTOVER: "true",
      BNEST_RUNTIME_ROOT: scenario.flatRoot,
      BNEST_STORAGE_CONFIG: scenario.pointerPath,
      BNEST_TEST_LAYER: "integration",
      BNEST_TEST_RUN_ID: scenario.runId,
      ASDF_DIR: process.env["ASDF_DIR"] ?? path.join(realHome, ".asdf"),
      ASDF_DATA_DIR:
        process.env["ASDF_DATA_DIR"] ?? path.join(realHome, ".asdf"),
    },
    encoding: "utf8",
  });

  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

export function retireFlatIdentitySources(
  scenario: IdentityStorageScenario,
): void {
  if (scenario.flatRoot !== scenario.pairedRuntime.path) {
    throw new Error("Identity retirement requires its exact marked flat root");
  }

  for (const relative of [
    "system/bootstrap.json",
    "system/accounts",
    "system/usernames",
  ]) {
    rmSync(path.join(scenario.flatRoot, relative), {
      recursive: true,
      force: false,
    });
  }
}
