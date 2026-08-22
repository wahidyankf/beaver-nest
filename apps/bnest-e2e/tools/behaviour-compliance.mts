import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const scenarioPattern = /^(?:Scenario(?: Outline| Template)?|Example):/iu;

interface FeatureState {
  currentScenario?: string;
  hasFeature: boolean;
  hasThen: boolean;
  hasWhen: boolean;
  insideDocString: boolean;
  scenarioCount: number;
}

function startsStep(keyword: "When" | "Then", line: string): boolean {
  return line.toLowerCase().startsWith(`${keyword.toLowerCase()} `);
}

function finishScenario(
  resourceName: string,
  state: FeatureState,
  errors: string[],
): void {
  if (state.currentScenario === undefined) {
    return;
  }

  if (!state.hasWhen) {
    errors.push(
      `${resourceName}: ${state.currentScenario} requires a When step.`,
    );
  }

  if (!state.hasThen) {
    errors.push(
      `${resourceName}: ${state.currentScenario} requires a Then step.`,
    );
  }
}

function inspectLine(
  resourceName: string,
  state: FeatureState,
  errors: string[],
  line: string,
): void {
  const trimmed = line.trim();

  if (trimmed.startsWith('"""') || trimmed.startsWith("```")) {
    state.insideDocString = !state.insideDocString;
    return;
  }

  if (state.insideDocString || trimmed.startsWith("#")) {
    return;
  }

  if (trimmed.toLowerCase().startsWith("feature:")) {
    state.hasFeature = true;
  } else if (scenarioPattern.test(trimmed)) {
    finishScenario(resourceName, state, errors);
    state.scenarioCount += 1;
    state.currentScenario = trimmed;
    state.hasWhen = false;
    state.hasThen = false;
  } else if (
    state.currentScenario !== undefined &&
    startsStep("When", trimmed)
  ) {
    state.hasWhen = true;
  } else if (
    state.currentScenario !== undefined &&
    startsStep("Then", trimmed)
  ) {
    state.hasThen = true;
  }
}

export function validateFeatureSource(
  resourceName: string,
  source: string,
): string[] {
  const errors: string[] = [];
  const state: FeatureState = {
    hasFeature: false,
    hasThen: false,
    hasWhen: false,
    insideDocString: false,
    scenarioCount: 0,
  };

  for (const line of source
    .replaceAll("\r\n", "\n")
    .replaceAll("\r", "\n")
    .split("\n")) {
    inspectLine(resourceName, state, errors, line);
  }

  finishScenario(resourceName, state, errors);

  if (!state.hasFeature) {
    errors.push(`${resourceName}: missing Feature: declaration.`);
  }

  if (state.scenarioCount === 0) {
    errors.push(`${resourceName}: feature must contain at least one scenario.`);
  }

  return errors;
}

export async function findFiles(
  root: string,
  predicate: (fileName: string) => boolean,
): Promise<string[]> {
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry): Promise<string[]> => {
      const entryPath = path.join(root, entry.name);

      if (entry.isDirectory()) {
        return findFiles(entryPath, predicate);
      }

      return Promise.resolve(
        entry.isFile() && predicate(entry.name) ? [entryPath] : [],
      );
    }),
  );

  return files.flat().toSorted();
}

export async function validateFeatureFiles(
  featureFiles: string[],
): Promise<string[]> {
  const results = await Promise.all(
    featureFiles.map(async (featureFile) =>
      validateFeatureSource(featureFile, await readFile(featureFile, "utf8")),
    ),
  );

  return results.flat();
}
