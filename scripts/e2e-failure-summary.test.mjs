import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";

const script = path.join(import.meta.dirname, "e2e-failure-summary.mjs");
const workspace = mkdtempSync(
  path.join(os.tmpdir(), "e2e-failure-summary-test-"),
);
after(() => rmSync(workspace, { recursive: true, force: true }));

// Assembled at run time so that no literal in this repository has the shape the logs screen refuses.
const leakShapedPath = ["", "home", "synthetic-account", "checkout"].join("/");
const ESCAPE = String.fromCodePoint(27);

function testEntry(status, errors = []) {
  return { projectName: "chromium", results: [{ status, errors }] };
}

function summaryWith(errorMessage) {
  const describeBlock = {
    title: "Sends a message",
    line: 8,
    column: 8,
    suites: [],
    specs: [
      {
        title: "Example #1",
        line: 10,
        column: 10,
        tests: [testEntry("failed", [{ message: errorMessage }])],
      },
      {
        title: "Example #2",
        line: 17,
        column: 10,
        tests: [testEntry("passed")],
      },
    ],
  };
  const family = {
    title: "Family chat",
    line: 4,
    column: 6,
    specs: [],
    suites: [describeBlock],
  };
  const file = {
    title: "chat.feature.spec.js",
    line: 0,
    column: 0,
    specs: [],
    suites: [family],
  };
  return { suites: [file], errors: [], stats: { expected: 1, unexpected: 1 } };
}

function multiLineMessage() {
  return [
    `${ESCAPE}[31mExpected: 200${ESCAPE}[39m`,
    "",
    "Received: 500",
    "Call log:",
    "  - waiting for the page",
    "  - this fourth line is not kept",
  ].join("\n");
}

function runScript(summaryPath) {
  return spawnSync(process.execPath, [script, summaryPath], {
    encoding: "utf8",
  });
}

function writeFixture(name, content) {
  const file = path.join(workspace, name);
  writeFileSync(
    file,
    typeof content === "string" ? content : JSON.stringify(content),
  );
  return file;
}

describe("e2e-failure-summary", () => {
  it("prints the failing titles and their first error lines, and exits 0", () => {
    const message = multiLineMessage();
    const result = runScript(
      writeFixture("failing.json", summaryWith(message)),
    );

    assert.equal(result.status, 0);
    assert.equal(result.stderr, "");
    assert.match(
      result.stdout,
      /^1 failing test in the Playwright summary\.$/mu,
    );
    assert.match(
      result.stdout,
      /^Family chat > Sends a message > Example #1 \[chromium, failed\]$/mu,
    );
    assert.match(result.stdout, /^ {4}Expected: 200$/mu);
    assert.match(result.stdout, /^ {4}Call log:$/mu);
    assert.doesNotMatch(result.stdout, /this fourth line is not kept/u);
    assert.doesNotMatch(result.stdout, /Example #2/u);
    assert.equal(result.stdout.includes(ESCAPE), false);
  });

  it("refuses a summary whose error text carries a leak-shaped path: exit 1 and nothing on stdout", () => {
    const message = `Could not open ${leakShapedPath}/report.txt`;
    const result = runScript(
      writeFixture("leaking.json", summaryWith(message)),
    );

    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /refused by the logs screen/u);
    assert.equal(result.stderr.includes(leakShapedPath), false);
  });

  it("prints one line and exits 0 when no summary was written", () => {
    const result = runScript(path.join(workspace, "absent-summary.json"));

    assert.equal(result.status, 0);
    assert.equal(
      result.stdout,
      "No Playwright summary was written for this run.\n",
    );
    assert.equal(result.stderr, "");
  });
});
