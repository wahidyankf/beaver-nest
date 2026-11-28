import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";

import { findFiles } from "./behaviour-compliance.mts";

// Runs the app-fe scenarios that tests/integration binds at the integration level. The selection reads each
// `@scenario <feature>: <name>` line as RHINO does, so the run covers exactly the rows the level declares, through
// the same Playwright steps as the E2E run, with BNEST_E2E_LAYER=integration (no reverse proxy, loopback only).

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
const bindingRoot = path.resolve(import.meta.dirname, "../tests/integration");
const corpusPrefix = "specs/apps/bnest/app-fe/behaviours/";
const referencePattern = /@scenario\s+(\S+?\.feature(?:\.md)?):(.*)$/u;

interface Reference {
  feature: string;
  name: string;
}

function referencesIn(source: string): Reference[] {
  return source.split("\n").flatMap((line) => {
    const match = referencePattern.exec(line);
    if (match === null) return [];
    return [{ feature: match[1] ?? "", name: (match[2] ?? "").trim() }];
  });
}

async function problemWith(reference: Reference): Promise<string | undefined> {
  if (!reference.feature.startsWith(corpusPrefix)) {
    return `${reference.feature}: not a feature of ${corpusPrefix}`;
  }
  const source = await readFile(
    path.join(repositoryRoot, reference.feature),
    "utf8",
  );
  const declared = source
    .split("\n")
    .map((line) => line.trim())
    .some(
      (line) =>
        line === `Scenario: ${reference.name}` ||
        line === `Scenario Outline: ${reference.name}`,
    );
  return declared
    ? undefined
    : `${reference.feature}: no scenario named "${reference.name}"`;
}

function escapeRegExp(text: string): string {
  return text.replaceAll(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

async function main(): Promise<void> {
  const bindingFiles = await findFiles(bindingRoot, (fileName) =>
    fileName.endsWith(".ts"),
  );
  const references = (
    await Promise.all(
      bindingFiles.map(async (file) =>
        referencesIn(await readFile(file, "utf8")),
      ),
    )
  ).flat();

  if (references.length === 0) {
    throw new Error(
      `No integration binding was found below '${bindingRoot}'; the integration run would select nothing.`,
    );
  }

  const problems = (
    await Promise.all(references.map((reference) => problemWith(reference)))
  ).filter((problem): problem is string => problem !== undefined);
  if (problems.length > 0) throw new Error(problems.join("\n"));

  const names = [...new Set(references.map((reference) => reference.name))];
  // One desktop project: the tablet and mobile projects re-run the same steps under touch and tablet emulation, which
  // the E2E layer owns. Without this, a run selects the scenarios of every project.
  const result = spawnSync(
    "node",
    [
      path.resolve(import.meta.dirname, "run-e2e.mts"),
      "--project",
      "chromium",
      "--grep",
      names.map((name) => escapeRegExp(name)).join("|"),
      ...process.argv.slice(2),
    ],
    {
      cwd: repositoryRoot,
      env: { ...process.env, BNEST_E2E_LAYER: "integration" },
      stdio: "inherit",
    },
  );

  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
  console.error(
    `integration: ${names.length} bound scenario(s) from ${references.length} reference(s)`,
  );
}

try {
  await main();
} catch (error: unknown) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
