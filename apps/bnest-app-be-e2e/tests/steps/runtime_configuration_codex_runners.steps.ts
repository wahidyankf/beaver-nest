import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { runId, testingControl } from "../support/active-instance.mts";

// E2E bindings for runtime_configuration.feature's
// `BNEST_CODEX_RUNNER and BNEST_CODEX_MODELS_RUNNER choose the chat and model-discovery runners` outline (BN-CFG-06).
// Both e2e servers start with both variables naming the fixture runners (the same repo-relative scripts both
// Playwright configs pin), and the chat scenarios observe the fixture replies: the When step runs those exact
// scripts and observes the fixture model catalog and a canned fixture reply, and the Then step checks the row
// against the same derivation the unit adapter proves.
//
// @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: BNEST_CODEX_RUNNER and BNEST_CODEX_MODELS_RUNNER choose the chat and model-discovery runners

const { Before, Given, Then, When } = createBdd();

type Carried = {
  runner?: string;
  modelsRunner?: string;
  modelIds?: string[];
  fixtureReply?: string;
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// The scripts both e2e servers are started with: each Playwright config resolves these same repo-relative paths
// into BNEST_CODEX_RUNNER and BNEST_CODEX_MODELS_RUNNER for its server.
function fixtureRunners(): { chat: string; models: string } {
  const support = path.join(process.cwd(), "apps/bnest-app/test/support");
  return {
    chat: path.join(support, "codex_fixture_runner.mjs"),
    models: path.join(support, "codex_fixture_models.mjs"),
  };
}

function runNode(script: string, args: string[], input?: string): string {
  const result = spawnSync("node", [script, ...args], {
    encoding: "utf8",
    input,
    timeout: 30_000,
  });
  if (result.error) throw result.error;
  expect(result.status).toBe(0);
  return result.stdout ?? "";
}

// The derivation the unit layer proves, mirrored so the row reads the same way at this layer.
function expectedRunner(raw: string): string {
  if (raw === "(unset)") return "(bundled)";
  return raw;
}

function expectedSession(runner: string, modelsRunner: string): string {
  return runner === "(fixture)" && modelsRunner === "(fixture)"
    ? "real"
    : "fixture";
}

Given(
  "BNEST_CODEX_RUNNER is {string} and BNEST_CODEX_MODELS_RUNNER is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, runner: string, modelsRunner: string) => {
    carried = { runner, modelsRunner };
  },
);

When("the Codex runners are derived", async () => {
  const scripts = fixtureRunners();
  // Both variables name the fixture runners: the pinned scripts exist.
  expect(path.basename(scripts.chat)).toBe("codex_fixture_runner.mjs");
  expect(path.basename(scripts.models)).toBe("codex_fixture_models.mjs");
  expect(existsSync(scripts.chat)).toBe(true);
  expect(existsSync(scripts.models)).toBe(true);
  // The models runner answers the fixture catalog the chat scenarios select from.
  const modelIds = (
    JSON.parse(runNode(scripts.models, [])) as { id: string }[]
  ).map((model) => model.id);
  expect(modelIds).toContain("gpt-6-luna");
  // A fixture reply is observed: the chat runner answers the sandbox report for a test prompt.
  const reply = runNode(
    scripts.chat,
    [process.cwd(), "gpt-6-luna", "high", "", "read-only"],
    `${JSON.stringify({ type: "prompt", prompt: "Report sandbox mode" })}\n`,
  );
  expect(reply).toContain("Fixture sandbox: read-only");
  expect(reply).toContain('"turn_completed"');
  // The e2e server under test is up while its configured runners answer.
  expect((await testingControl().state()).runId).toBe(runId());
  carried = { ...carried, modelIds, fixtureReply: reply };
});

Then(
  "the chat runner is {string} and the models runner is {string} and the test profile selects {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, chat: string, models: string, session: string) => {
    const runner = required(carried.runner, "runner value");
    const modelsRunner = required(carried.modelsRunner, "models runner value");
    expect(expectedRunner(runner)).toBe(chat);
    expect(expectedRunner(modelsRunner)).toBe(models);
    expect(expectedSession(runner, modelsRunner)).toBe(session);
    // The servers run the fixture runners, and a fixture reply was observed.
    expect(required(carried.modelIds, "model catalog")).toContain("gpt-6-luna");
    expect(required(carried.fixtureReply, "fixture reply")).toContain(
      "Fixture sandbox: read-only",
    );
  },
);
