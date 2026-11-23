import { existsSync } from "node:fs";
import path from "node:path";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  currentInstance,
  runId,
  testingControl,
} from "../support/active-instance.mts";
import { liveRuntimeRoot } from "../support/sqlite-storage";

// E2E bindings for runtime_configuration.feature's
// `BNEST_RUNTIME_ROOT moves the flat-file runtime root` outline (BN-CFG-04). The E2E runner sets its run-scoped
// runtime root and every scenario reads and writes under it: the When step asserts the current instance's root
// through the testing-control probe client, and the Then step checks the row against the same derivation the unit
// adapter proves.
//
// @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: BNEST_RUNTIME_ROOT moves the flat-file runtime root

const { Before, Given, Then, When } = createBdd();

type Carried = {
  raw?: string;
  cwd?: string;
  runRoot?: string;
  instanceRoot?: string;
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// The derivation the unit layer proves, mirrored so the row reads the same way at this layer.
function expectedRoot(raw: string, cwd: string): string {
  if (raw === "(unset)") return "(default)";
  if (path.posix.isAbsolute(raw)) return raw;
  return path.posix.join(cwd, raw);
}

Given(
  "BNEST_RUNTIME_ROOT is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, raw: string) => {
    carried = { raw };
  },
);

When(
  "the runtime root is derived with {string}",
  // eslint-disable-next-line no-empty-pattern
  async ({}, cwd: string) => {
    // The runner sets the run-scoped root: the helper throws when it is missing.
    const runRoot = liveRuntimeRoot();
    expect(path.isAbsolute(runRoot)).toBe(true);
    // Every scenario reads and writes under that root: the current instance's root is the run root itself (the
    // production SQLite phase) or its instance directory (a flat-primary scenario).
    const state = await testingControl().state();
    expect(state.runId).toBe(runId());
    const instanceRoot = currentInstance().environment["BNEST_RUNTIME_ROOT"];
    expect(
      instanceRoot === runRoot ||
        instanceRoot ===
          path.join(runRoot, "instances", state.instance?.instanceId ?? ""),
    ).toBe(true);
    expect(existsSync(instanceRoot)).toBe(true);
    expect(cwd).not.toBe("");
    carried = { ...carried, cwd, runRoot, instanceRoot };
  },
);

Then(
  "the runtime root is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, resolved: string) => {
    expect(
      expectedRoot(
        required(carried.raw, "root value"),
        required(carried.cwd, "working directory"),
      ),
    ).toBe(resolved);
    // The scenario ran under the run-scoped root the runner set.
    expect(required(carried.runRoot, "run root")).toBe(liveRuntimeRoot());
    expect(required(carried.instanceRoot, "instance root")).toContain(
      required(carried.runRoot, "run root"),
    );
  },
);
