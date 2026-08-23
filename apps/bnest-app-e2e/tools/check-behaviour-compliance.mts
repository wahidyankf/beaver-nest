import { spawnSync } from "node:child_process";
import path from "node:path";

import { findFiles, validateFeatureFiles } from "./behaviour-compliance.mts";

const workspaceRoot = process.cwd();
const featureRoot = path.join(workspaceRoot, "specs/bnest/app/behaviours");
const testsRoot = path.join(workspaceRoot, "apps/bnest-app-e2e/tests");
const playwrightConfig = "apps/bnest-app-e2e/playwright.config.mts";
const directSpecPattern = /\.spec\.(?:[cm]?[jt]s)$/u;

function runBddgen(args: string[]): string {
  const result = spawnSync("npm", ["exec", "--", "bddgen", ...args], {
    cwd: workspaceRoot,
    encoding: "utf8",
    env: { ...process.env, FORCE_COLOR: "0" },
  });
  const output = `${result.stdout}${result.stderr}`;

  if (result.status !== 0) {
    throw new Error(output.trim());
  }

  return output;
}

async function main(): Promise<void> {
  const featureFiles = await findFiles(featureRoot, (fileName) =>
    fileName.endsWith(".feature"),
  );

  if (featureFiles.length === 0) {
    throw new Error(`No feature files were found below '${featureRoot}'.`);
  }

  const structuralErrors = await validateFeatureFiles(featureFiles);

  if (structuralErrors.length > 0) {
    throw new Error(structuralErrors.join("\n"));
  }

  const directSpecs = await findFiles(testsRoot, (fileName) =>
    directSpecPattern.test(fileName),
  );

  if (directSpecs.length > 0) {
    throw new Error(
      `Direct Playwright journey specs are forbidden:\n${directSpecs.join("\n")}`,
    );
  }

  runBddgen(["--config", playwrightConfig]);
  const unusedOutput = runBddgen([
    "export",
    "--config",
    playwrightConfig,
    "--unused-steps",
  ]);
  const unusedCount = /Unused steps \((\d+)\):/u.exec(unusedOutput)?.[1];

  if (unusedCount === undefined) {
    throw new Error(
      `Could not determine the unused-step count:\n${unusedOutput.trim()}`,
    );
  }

  if (unusedCount !== "0") {
    throw new Error(unusedOutput.trim());
  }
}

try {
  await main();
} catch (error: unknown) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
