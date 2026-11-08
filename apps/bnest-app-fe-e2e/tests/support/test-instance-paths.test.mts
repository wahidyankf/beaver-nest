import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { deriveTestInstancePaths } from "./test-instance-paths.mts";

type FixtureCase = {
  name: string;
  input: {
    flatRunRoot: string;
    sqliteRunRoot: string;
    runId: string;
    instanceId: string;
  };
  expect: unknown;
};

type Fixture = { schemaVersion: number; cases: FixtureCase[] };

// The same JSON file is read by the Elixir test. It lives in bnest-app so that
// both implementations are pinned to one source of expected values.
const fixture = JSON.parse(
  readFileSync(
    new URL(
      "../../../bnest-app/test/fixtures/test_instance_paths.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as Fixture;

test("the shared fixture declares schema version 1 and both outcomes", () => {
  assert.equal(fixture.schemaVersion, 1);
  assert.ok(fixture.cases.some((testCase) => isOkExpectation(testCase.expect)));
  assert.ok(
    fixture.cases.some((testCase) => !isOkExpectation(testCase.expect)),
  );
});

test("the path mirror returns the fixture result for every case", () => {
  for (const testCase of fixture.cases) {
    assert.deepEqual(
      deriveTestInstancePaths(testCase.input),
      testCase.expect,
      testCase.name,
    );
  }
});

test("the path mirror rejects non-string inputs as the Elixir module does", () => {
  const valid = {
    flatRunRoot: "/synthetic/data/test/runs/unit-run-1",
    sqliteRunRoot: "/synthetic/bnest/data/test/runs/unit-run-1",
    runId: "unit-run-1",
    instanceId: "a1b2c3d4e5f6g7h8",
  };

  assert.deepEqual(deriveTestInstancePaths({ ...valid, runId: null }), {
    ok: false,
    error: "invalid_run_id",
  });
  assert.deepEqual(deriveTestInstancePaths({ ...valid, instanceId: null }), {
    ok: false,
    error: "invalid_instance_id",
  });
  assert.deepEqual(deriveTestInstancePaths({ ...valid, flatRunRoot: null }), {
    ok: false,
    error: "invalid_root",
  });
});

function isOkExpectation(expect: unknown): boolean {
  return (
    typeof expect === "object" &&
    expect !== null &&
    (expect as { ok?: unknown }).ok === true
  );
}
