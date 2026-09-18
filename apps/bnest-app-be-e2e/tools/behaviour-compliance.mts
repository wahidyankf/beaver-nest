import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const scenarioPattern = /^(?:Scenario(?: Outline| Template)?|Example):/iu;
const exemptionTags = new Set(["integration-exempt", "e2e-exempt"]);
const forbiddenTags = new Set([
  "unit-exempt",
  "no-unit",
  "no-integration",
  "no-e2e",
]);
const exemptionCommentPattern =
  /^# Exemption\((integration|e2e)\): (.+); alternative-proof: (.+)$/u;
const invalidReasonPattern =
  /\b(?:hard|slow|flaky|cost(?:ly)?|expensive|not yet implemented|todo)\b/iu;

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
  errors.push(...validateExemptionPolicy(resourceName, source));

  if (!state.hasFeature) {
    errors.push(`${resourceName}: missing Feature: declaration.`);
  }

  if (state.scenarioCount === 0) {
    errors.push(`${resourceName}: feature must contain at least one scenario.`);
  }

  return errors;
}

type TagReference = { line: number; name: string };

function validateExemptionPolicy(
  resourceName: string,
  source: string,
): string[] {
  const errors: string[] = [];
  const lines = source
    .replaceAll("\r\n", "\n")
    .replaceAll("\r", "\n")
    .split("\n");
  let pending: TagReference[] = [];

  lines.forEach((line, index) => {
    const trimmed = line.trim();
    const lineNumber = index + 1;
    if (trimmed.startsWith("@")) {
      pending.push(
        ...validateTagLine(resourceName, trimmed, lineNumber, errors),
      );
      return;
    }
    if (gherkinDeclaration(trimmed)) {
      errors.push(
        ...declarationErrors(resourceName, lines, pending, trimmed, lineNumber),
      );
      pending = [];
      return;
    }
    if (trimmed !== "" && !trimmed.startsWith("#") && pending.length > 0) {
      errors.push(
        `${resourceName}:${lineNumber}: tags must be followed by their Gherkin declaration.`,
      );
      pending = [];
    }
  });

  if (pending.length > 0)
    errors.push(
      `${resourceName}: dangling tags are not attached to a scenario.`,
    );
  return errors;
}

function validateTagLine(
  resourceName: string,
  line: string,
  lineNumber: number,
  errors: string[],
): TagReference[] {
  return line
    .split(/\s+/u)
    .filter((part) => part.startsWith("@"))
    .map((part) => part.slice(1))
    .map((name) => {
      if (forbiddenTags.has(name))
        errors.push(
          `${resourceName}:${lineNumber}: @${name} is forbidden; unit has no exemption and higher layers use the layer-specific @integration-exempt and @e2e-exempt tags.`,
        );
      return { line: lineNumber, name };
    });
}

function declarationErrors(
  resourceName: string,
  lines: string[],
  pending: TagReference[],
  declaration: string,
  lineNumber: number,
): string[] {
  const exemptions = pending.filter(({ name }) => exemptionTags.has(name));
  if (exemptions.length === 0) return [];
  const errors = exemptions.flatMap((tag) =>
    documentedExemptionErrors(resourceName, lines, tag),
  );
  if (!scenarioPattern.test(declaration))
    errors.push(
      `${resourceName}:${lineNumber}: exemption tags may only annotate a Scenario or Scenario Outline.`,
    );
  return errors;
}

function documentedExemptionErrors(
  resourceName: string,
  lines: string[],
  exemption: TagReference,
): string[] {
  const match = exemptionCommentPattern.exec(
    lines[exemption.line - 2]?.trim() ?? "",
  );
  const layer = exemption.name.replace("-exempt", "");
  if (match === null || match[1] !== layer)
    return [
      `${resourceName}:${exemption.line}: @${exemption.name} requires the immediately preceding comment ` +
        `'# Exemption(${layer}): <reason>; alternative-proof: <Nx target/scenario>'.`,
    ];
  const errors: string[] = [];
  if (invalidReasonPattern.test(match[2] ?? ""))
    errors.push(
      `${resourceName}:${exemption.line}: an exemption cannot be justified by difficulty, speed, cost, flakiness, or missing implementation.`,
    );
  if (!/^[a-z0-9-]+:test(?::[a-z0-9-]+)*\s+\/\s+\S/iu.test(match[3] ?? ""))
    errors.push(
      `${resourceName}:${exemption.line}: alternative-proof must name an Nx test target and scenario after ' / '.`,
    );
  return errors;
}

function gherkinDeclaration(line: string): boolean {
  return /^(?:Feature|Rule|Background|Scenario(?: Outline| Template)?|Examples?|Example):/iu.test(
    line,
  );
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
