#!/usr/bin/env node
// Tests for check-ui-class-coverage.mjs: the gate passes only when every used
// class is defined or allowed, and it names the exact missing list otherwise.
// A gate verified only on its passing cases would pass while flagging nothing,
// which is the way a coverage gate goes silently blind.
//
// Run: node --test scripts/check-ui-class-coverage.test.mjs
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, "check-ui-class-coverage.mjs");

let scratch;
beforeEach(() => {
  scratch = mkdtempSync(path.join(tmpdir(), "ui-class-coverage-"));
  mkdirSync(path.join(scratch, "templates", "live"), { recursive: true });
  mkdirSync(path.join(scratch, "css"), { recursive: true });
});
afterEach(() => rmSync(scratch, { recursive: true, force: true }));

const write = (name, content) => {
  const full = path.join(scratch, name);
  mkdirSync(path.dirname(full), { recursive: true });
  writeFileSync(full, content);
  return full;
};

const env = (overrides = {}) => ({
  ...process.env,
  UI_COVERAGE_TEMPLATES: path.join(scratch, "templates"),
  UI_COVERAGE_CSS: path.join(scratch, "css"),
  UI_COVERAGE_BUNDLE: path.join(scratch, "bundle.css"),
  UI_COVERAGE_ALLOWLIST: path.join(scratch, "allowlist.txt"),
  ...overrides,
});

const run = (overrides) => {
  try {
    const stdout = execFileSync(process.execPath, [script], {
      env: env(overrides),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { code: 0, stdout, stderr: "" };
  } catch (error) {
    return {
      code: error.status,
      stdout: error.stdout?.toString() ?? "",
      stderr: error.stderr?.toString() ?? "",
    };
  }
};

const seed = () => {
  write("templates/live/page.ex", `<div class="card card-title">hi</div>`);
  write(
    "css/base.css",
    `.card { color: red; }\n.card-title { color: blue; }\n`,
  );
  write("bundle.css", `.bundle-only { color: green; }\n`);
  write("allowlist.txt", `# seeded by each case\n`);
};

describe("check-ui-class-coverage", () => {
  it("passes when every class is defined in sources or the bundle", () => {
    seed();
    write(
      "templates/live/other.ex",
      `<span class={["bundle-only", @extra && "card"]}>x</span>`,
    );
    const result = run();
    assert.equal(result.code, 0);
    assert.match(result.stdout, /PASS: \d+ classes used/);
  });

  it("extracts string literals from multiline class={...} lists", () => {
    seed();
    write(
      "templates/live/multi.ex",
      `<button\n  class={[\n    "card",\n    @on && "bundle-only"\n  ]}\n>go</button>`,
    );
    const result = run();
    assert.equal(result.code, 0);
  });

  it("matches tailwind-escaped selectors back to the used token", () => {
    seed();
    write(
      "templates/live/page.ex",
      `<div class="card sm:px-6 mt-1.5">hi</div>`,
    );
    write(
      "bundle.css",
      `.sm\\:px-6 { padding: 1rem; }\n.mt-1\\.5 { margin: 1rem; }\n`,
    );
    const result = run();
    assert.equal(result.code, 0);
  });

  it("splits compound and pseudo selectors into their own classes", () => {
    seed();
    write("templates/live/page.ex", `<div class="card is-on">hi</div>`);
    write(
      "bundle.css",
      `.card.is-on { color: green; }\n.card:hover { color: red; }\n`,
    );
    const result = run();
    assert.equal(result.code, 0);
  });

  it("fails with the exact missing list and where each is used", () => {
    seed();
    write("templates/live/page.ex", `<div class="card ghost typo">hi</div>`);
    const result = run();
    assert.equal(result.code, 1);
    assert.match(result.stderr, /2 undefined class\(es\)/);
    assert.match(result.stderr, /- ghost \(used in .*page\.ex:1\)/);
    assert.match(result.stderr, /- typo \(used in .*page\.ex:1\)/);
  });

  it("allows exact and prefix entries, and rejects entries without a reason", () => {
    seed();
    write(
      "templates/live/page.ex",
      `<div class="card is-new is-old ghost">hi</div>`,
    );
    write(
      "allowlist.txt",
      `ghost # dynamic icon injected by the diagram renderer\nis-* # feedback-kind suffix interpolated at render\n`,
    );
    const passing = run();
    assert.equal(passing.code, 0);

    write("allowlist.txt", `ghost\n`);
    const result = run();
    assert.equal(result.code, 1);
    assert.match(result.stderr, /needs `name # reason`/);
  });

  it("fails when the built bundle is missing, with the rebuild command", () => {
    seed();
    const missing = path.join(scratch, "no-bundle.css");
    const result = run({ UI_COVERAGE_BUNDLE: missing });
    assert.equal(result.code, 1);
    assert.match(result.stderr, /bundle not found/);
    assert.match(result.stderr, /assets:build/);
  });
});
