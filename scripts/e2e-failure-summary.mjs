#!/usr/bin/env node
// Prints the failing tests of one Playwright run from its JSON summary, once the logs screen has cleared the text.
//
// Usage: node scripts/e2e-failure-summary.mjs <path-to-json-summary>
//
// A missing or unreadable summary prints one line and exits 0. A summary that the logs screen refuses prints nothing to
// stdout, one line to stderr, and exits 1. What is printed is the failing test titles, the first error lines of each,
// and the run-level errors: no stack traces, attachments, test output, raw JSON, or paths.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const MAX_TESTS = 200;
const MAX_MESSAGE_LINES = 3;
const MAX_LINE_LENGTH = 300;
const MAX_RUN_ERRORS = 20;
const FAILING_STATUSES = new Set(["failed", "timedOut", "interrupted"]);
const ESCAPE = String.fromCodePoint(27);
const ANSI_SEQUENCE = new RegExp(`${ESCAPE}\\[[0-?]*[ -/]*[@-~]`, "gu");
const NO_SUMMARY_LINE = "No Playwright summary was written for this run.";
const REFUSED_LINE =
  "e2e-failure-summary: the summary was refused by the logs screen; nothing was printed to stdout.";
const BROKEN_LINE =
  "e2e-failure-summary: the summary could not be built; nothing was printed to stdout.";

const repoRoot = path.resolve(import.meta.dirname, "..");
const logsScreen = path.join(
  repoRoot,
  "scripts",
  "public-safety",
  "outbound-preflight.sh",
);

function readSummary(summaryPath) {
  try {
    const parsed = JSON.parse(readFileSync(summaryPath, "utf8"));
    return parsed !== null && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

// A file suite carries its file name at line 0; a describe block has a line and contributes its title.
function* testsWithTitles(suites, parentTitles = []) {
  for (const suite of suites ?? []) {
    const titles =
      suite.line > 0 && suite.title
        ? [...parentTitles, suite.title]
        : parentTitles;
    for (const spec of suite.specs ?? []) {
      for (const test of spec.tests ?? []) {
        yield { title: [...titles, spec.title].join(" > "), test };
      }
    }
    yield* testsWithTitles(suite.suites, titles);
  }
}

function messageLines(error) {
  const message = typeof error?.message === "string" ? error.message : "";
  return message
    .replaceAll(ANSI_SEQUENCE, "")
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter((line) => line !== "")
    .slice(0, MAX_MESSAGE_LINES)
    .map((line) => line.slice(0, MAX_LINE_LENGTH));
}

function resultErrors(result) {
  if (Array.isArray(result.errors)) return result.errors;
  return result.error ? [result.error] : [];
}

function plural(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function buildText(summary) {
  const failing = [];
  for (const { title, test } of testsWithTitles(summary.suites)) {
    const last = Array.isArray(test.results) ? test.results.at(-1) : undefined;
    if (last !== undefined && FAILING_STATUSES.has(last.status)) {
      failing.push({
        title: title.replaceAll(/\s+/gu, " "),
        project: String(test.projectName ?? ""),
        status: last.status,
        lines: resultErrors(last).flatMap((error) => messageLines(error)),
      });
    }
  }

  const out = [
    `${plural(failing.length, "failing test")} in the Playwright summary.`,
  ];
  for (const test of failing.slice(0, MAX_TESTS)) {
    out.push(`${test.title} [${test.project}, ${test.status}]`);
    for (const line of test.lines) out.push(`    ${line}`);
  }
  const omitted = failing.length - Math.min(failing.length, MAX_TESTS);
  if (omitted > 0) {
    out.push(
      `${plural(omitted, "more failing test")} not listed; the list is capped at ${MAX_TESTS}.`,
    );
  }

  const runErrors = Array.isArray(summary.errors)
    ? summary.errors.slice(0, MAX_RUN_ERRORS)
    : [];
  if (runErrors.length > 0) {
    out.push("Run-level errors:");
    for (const error of runErrors) {
      for (const line of messageLines(error)) out.push(`    ${line}`);
    }
  }

  // The repository root is a machine-specific path on every runner, so it is named rather than printed.
  return `${out.join("\n").split(repoRoot).join("<repo-root>")}\n`;
}

function passesLogsScreen(text) {
  const directory = mkdtempSync(path.join(os.tmpdir(), "e2e-failure-summary-"));
  try {
    const file = path.join(directory, "summary.txt");
    writeFileSync(file, text, { mode: 0o600 });
    const screen = spawnSync(
      "bash",
      [logsScreen, "--surface", "logs", "--file", file],
      { stdio: "ignore" },
    );
    return screen.status === 0;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function main(args) {
  if (args.length !== 1) {
    process.stderr.write(
      "usage: node scripts/e2e-failure-summary.mjs <path-to-json-summary>\n",
    );
    return 1;
  }
  const summary = readSummary(path.resolve(args[0]));
  if (summary === null) {
    process.stdout.write(`${NO_SUMMARY_LINE}\n`);
    return 0;
  }
  const text = buildText(summary);
  if (!passesLogsScreen(text)) {
    process.stderr.write(`${REFUSED_LINE}\n`);
    return 1;
  }
  process.stdout.write(text);
  return 0;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch {
  process.stderr.write(`${BROKEN_LINE}\n`);
  process.exitCode = 1;
}
