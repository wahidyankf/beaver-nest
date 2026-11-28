// Plain Vitest unit coverage for the scheduled quality-gates workflow. Each test reads the real workflow, the
// Playwright projects, and the gate registry as text and compares them, so a dropped matrix project, a swapped job, a
// changed cron or zone, or a leg that points at the wrong registry entry fails here. Nothing runs, no network is
// reached, and no file is written. The repository has no YAML parser dependency, so the files are read by their
// fixed two-space layout.

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const repositoryFile = (path: string): string =>
  readFileSync(new URL(`../../../../../${path}`, import.meta.url), "utf8");

const workflow = repositoryFile(
  ".github/workflows/scheduled-quality-gates.yml",
);
const playwrightConfig = repositoryFile(
  "apps/bnest-app-fe-e2e/playwright.config.mts",
);
const registry = repositoryFile("repo-config.yml");

const setupProject = "one-time-setup";
const frontendJob = "bnest-test-e2e-fe";
const backendJob = "bnest-test-e2e-be";

// The text under each `key:` that stands alone on a line at the given indent, in declared order. A block runs to the
// next key at the same indent.
function blocksAt(text: string, indent: number): Map<string, string> {
  const key = new RegExp(`^ {${indent}}([A-Za-z0-9_-]+):\\s*$`, "u");
  const blocks = new Map<string, string[]>();
  let current: string[] | undefined;
  for (const line of text.split("\n")) {
    const name = key.exec(line)?.[1];
    if (name !== undefined) {
      current = [];
      blocks.set(name, current);
    } else {
      current?.push(line);
    }
  }
  return new Map([...blocks].map(([name, lines]) => [name, lines.join("\n")]));
}

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the workflow has no ${what}`);
  return value;
}

const jobs = blocksAt(
  required(blocksAt(workflow, 0).get("jobs"), "jobs block"),
  2,
);
const jobNames = [...jobs.keys()];

// `needs: a` or `needs: [a, b]`, as the job names it lists.
function needs(job: string): string[] {
  const listed = /^ {4}needs:\s*\[?([^\]\n]*)\]?\s*$/mu.exec(
    required(jobs.get(job), job),
  )?.[1];
  return (listed ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name !== "");
}

function matrixProjects(): string[] {
  const listed = /^ {8}project:\s*\[([^\]]*)\]/mu.exec(
    required(jobs.get(frontendJob), frontendJob),
  )?.[1];
  return required(listed, "front-end matrix project list")
    .split(",")
    .map((name) => name.trim());
}

// The Playwright projects other than the shared setup project, in the order the config declares them.
function playwrightProjects(): string[] {
  const afterProjects = playwrightConfig.slice(
    playwrightConfig.indexOf("projects: ["),
  );
  const names = [...afterProjects.matchAll(/^ {6}name: "([^"]+)"/gmu)].map(
    (match) => required(match[1], "project name"),
  );
  return names.filter((name) => name !== setupProject);
}

interface Entry {
  readonly id: string;
  readonly body: string;
  readonly surfaces: string[];
}

// Registry entries in declared order, each with the surfaces under its `run-on:` key.
function registryEntries(): Entry[] {
  const parts = registry.split(/^ {4}- id: (\S+)$/mu);
  const entries: Entry[] = [];
  for (let index = 1; index < parts.length; index += 2) {
    const body = (parts[index + 1] ?? "").split(/^\S/mu)[0] ?? "";
    const runOn = /run-on:\n((?: {8}.*(?:\n|$))*)/u.exec(body)?.[1] ?? "";
    const surfaces = [...runOn.matchAll(/^ {8}([a-z-]+):/gmu)].map((match) =>
      required(match[1], "surface"),
    );
    entries.push({ id: required(parts[index], "entry id"), body, surfaces });
  }
  return entries;
}

const entries = registryEntries();
const entry = (id: string): Entry =>
  required(
    entries.find((candidate) => candidate.id === id),
    `registry entry ${id}`,
  );
const scheduledIds = entries
  .filter((candidate) => candidate.surfaces.includes("scheduled"))
  .map((candidate) => candidate.id);

describe("scheduled quality-gates workflow", () => {
  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("runs at 06:00 and 18:00 WIB on one schedule, and on manual dispatch", () => {
    const trigger = required(blocksAt(workflow, 0).get("on"), "on block");

    expect(
      [...trigger.matchAll(/^\s+- cron: "([^"]*)"$/gmu)].map(
        (match) => match[1],
      ),
      "the workflow runs on exactly one cron, 0 6,18 * * *",
    ).toEqual(["0 6,18 * * *"]);
    expect(
      [...trigger.matchAll(/^\s+timezone: "([^"]*)"$/gmu)].map(
        (match) => match[1],
      ),
      "the schedule runs in the Asia/Jakarta zone",
    ).toEqual(["Asia/Jakarta"]);
    expect(trigger).toMatch(/^ {2}workflow_dispatch:/mu);
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("runs serially without cancelling a run that is in progress", () => {
    const concurrency = required(
      blocksAt(workflow, 0).get("concurrency"),
      "concurrency block",
    );

    expect(concurrency).toMatch(/^ {2}group: \S+$/mu);
    expect(concurrency).toMatch(/^ {2}cancel-in-progress: false$/mu);
    expect(concurrency).not.toMatch(/cancel-in-progress: (?!false\b)/u);
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("runs the back-end and the front-end suites as different jobs, neither waiting for the other", () => {
    expect(
      [...jobNames].sort(),
      "the workflow declares one job for the back-end suite and one for the front-end suite, and no other",
    ).toEqual([backendJob, frontendJob].sort());
    expect(backendJob).not.toBe(frontendJob);
    expect(
      required(jobs.get(backendJob), backendJob),
      "the back-end job runs no front-end entry",
    ).not.toContain("--entry test-e2e-fe");
    expect(
      required(jobs.get(frontendJob), frontendJob),
      "the front-end job runs no back-end entry",
    ).not.toContain("--entry test-e2e-be");
    expect(
      needs(backendJob),
      "the back-end job must not wait for the front-end job",
    ).not.toContain(frontendJob);
    expect(
      needs(frontendJob),
      "the front-end job must not wait for the back-end job",
    ).not.toContain(backendJob);
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("runs the integration suite on every pull request, so no scheduled leg runs it", () => {
    expect(entry("test-integration").surfaces).toEqual(["pull-request"]);
    expect(scheduledIds.some((id) => /integration/u.test(id))).toBe(false);
    expect(
      jobNames.some((name) => /integration/u.test(name)),
      "the workflow has no integration job",
    ).toBe(false);
    expect(
      workflow,
      "no step runs the integration entry or target",
    ).not.toMatch(/--entry test-integration|test:integration/u);
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("matrixes the front-end job over the Playwright projects, in the registry order", () => {
    const projects = playwrightProjects();

    expect(projects.length).toBeGreaterThan(0);
    expect(
      matrixProjects(),
      "the front-end matrix lists the Playwright projects in playwright.config.mts, except one-time-setup",
    ).toEqual(projects);
    expect(
      entries
        .map((candidate) => candidate.id)
        .filter((id) => id.startsWith("test-e2e-fe-")),
      "the registry lists one test-e2e-fe entry per Playwright project, in the same order",
    ).toEqual(projects.map((project) => `test-e2e-fe-${project}`));
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("points each leg at its own scheduled registry entry, which runs only that project", () => {
    const backend = required(jobs.get(backendJob), backendJob);
    const frontend = required(jobs.get(frontendJob), frontendJob);

    expect(backend).toContain(
      "./rhino gate run --surface scheduled --entry test-e2e-be\n",
    );
    expect(frontend).toContain(
      "./rhino gate run --surface scheduled --entry test-e2e-fe-${{ matrix.project }}\n",
    );
    expect(entry("test-e2e-be").surfaces).toEqual(["scheduled"]);
    for (const project of matrixProjects()) {
      const leg = entry(`test-e2e-fe-${project}`);
      expect(leg.surfaces).toEqual(["scheduled"]);
      expect(
        [...leg.body.matchAll(/--project=(\S+) \}/gu)].map((match) => match[1]),
        `test-e2e-fe-${project} runs only --project=${project}`,
      ).toEqual([project]);
    }
  });

  // @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  it("leaves no scheduled registry entry without a job that runs it", () => {
    const run = [
      "test-e2e-be",
      ...matrixProjects().map((project) => `test-e2e-fe-${project}`),
    ];

    expect(scheduledIds).toEqual(run);
  });
});
