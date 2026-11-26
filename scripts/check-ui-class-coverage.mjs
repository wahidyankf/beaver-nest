#!/usr/bin/env node
// check-ui-class-coverage.mjs — every static class a LiveView template uses must
// be defined by a shipped stylesheet.
//
// Usage: scripts/check-ui-class-coverage.mjs
//
// Bound (documented, deliberate):
//   templates: apps/bnest-app/lib/bnest_app_web/live/**/*.ex(.heex) and
//     apps/bnest-app/lib/bnest_app_web/components/**/*.ex(.heex). Other
//     templates (layouts outside components/, emails) are out of scope.
//   definitions: apps/bnest-app/assets/css/*.css (the committed sources) plus
//     the built bundle the tailwind rule in apps/bnest-app/config/config.exs
//     writes (priv/static/assets/css/app.css). The bundle is required: Tailwind
//     generates utilities into it from @source scans, so without it every
//     utility would read as missing. Build it with `nx run bnest-app:assets:build`.
//   extraction: `class="..."` literals, plus string literals inside
//     `class={...}` (HEEx list/map forms). Interpolated fragments
//     (`is-#{kind}`) and `@assign` passthroughs are dynamic by construction:
//     they are skipped here, so a new dynamic kind still needs a human to
//     check its style. The allowlist is only for literal tokens with no
//     stylesheet definition: style-less behavior hooks read by scripts, or
//     utilities the extractors cannot spell.
//   allowlist: scripts/ui-class-coverage-allowlist.txt, one entry per line as
//     `name # reason`. A trailing `*` is a prefix (for dynamic families like
//     `is-*`). An entry without a `# reason` fails the gate.
//
// Exit codes: 0 every used class is defined or allowed; 1 the exact missing
// list is printed, the allowlist is malformed, or the bundle is missing.
// Dynamic class families that only exist at runtime (JS-added, LiveView-added)
// are invisible here: nothing references them in templates, so nothing fails.
//
// Test overrides (used by check-ui-class-coverage.test.mjs, never in CI):
//   UI_COVERAGE_TEMPLATES, UI_COVERAGE_CSS — path.delimiter-separated lists of
//   files or directories (directories are scanned for *.ex/.heex and *.css).
//   UI_COVERAGE_BUNDLE is one path, UI_COVERAGE_ALLOWLIST one file.
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const rel = (p) => path.relative(root, p);

const splitPaths = (value) =>
  value
    .split(path.delimiter)
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

const defaultTemplates = [
  "apps/bnest-app/lib/bnest_app_web/live",
  "apps/bnest-app/lib/bnest_app_web/components",
].map((p) => path.join(root, p));

const defaultCss = [path.join(root, "apps/bnest-app/assets/css")];

const templates = process.env["UI_COVERAGE_TEMPLATES"]
  ? splitPaths(process.env["UI_COVERAGE_TEMPLATES"]).map((p) =>
      path.resolve(root, p),
    )
  : defaultTemplates;
const cssFiles = process.env["UI_COVERAGE_CSS"]
  ? splitPaths(process.env["UI_COVERAGE_CSS"]).map((p) => path.resolve(root, p))
  : defaultCss;
const bundle = process.env["UI_COVERAGE_BUNDLE"]
  ? path.resolve(root, process.env["UI_COVERAGE_BUNDLE"])
  : path.join(root, "apps/bnest-app/priv/static/assets/css/app.css");
const allowlistPath = process.env["UI_COVERAGE_ALLOWLIST"]
  ? path.resolve(root, process.env["UI_COVERAGE_ALLOWLIST"])
  : path.join(root, "scripts/ui-class-coverage-allowlist.txt");

const fail = (message) => {
  process.stderr.write(`[ui-class-coverage] FAIL: ${message}\n`);
  process.exitCode = 1;
};

const collectFiles = (dir, extensions, out = []) => {
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) collectFiles(full, extensions, out);
    else if (extensions.some((ext) => name.endsWith(ext))) out.push(full);
  }
  return out.sort();
};

// A token is dynamic when it carries interpolation or binding syntax; those
// families are allowlisted whole, never matched literally.
const isDynamicToken = (token) => /[#{}()@!<>]/.test(token);

const usedByClass = new Map();
const recordUse = (file, line, token) => {
  if (token.length === 0 || isDynamicToken(token)) return;
  if (!usedByClass.has(token)) usedByClass.set(token, []);
  const spots = usedByClass.get(token);
  if (spots.length < 4) spots.push(`${rel(file)}:${line}`);
};

const lineOf = (content, index) => content.slice(0, index).split("\n").length;

for (const dir of templates) {
  if (!existsSync(dir)) fail(`template directory not found: ${rel(dir)}`);
  if (process.exitCode) process.exit(process.exitCode);
  for (const file of collectFiles(dir, [".ex", ".heex"])) {
    const content = readFileSync(file, "utf8");
    for (const match of content.matchAll(/class="([^"]*)"/g)) {
      const line = lineOf(content, match.index);
      for (const token of match[1].split(/\s+/)) recordUse(file, line, token);
    }
    for (const attr of content.matchAll(/class=\{([\s\S]*?)\}/g)) {
      const line = lineOf(content, attr.index);
      for (const literal of attr[1].matchAll(/"([^"]*)"/g)) {
        for (const token of literal[1].split(/\s+/))
          recordUse(file, line, token);
      }
    }
  }
}

const stripCssNoise = (content) =>
  content
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/url\([^)]*\)/g, "")
    .replace(/@import[^;]+;/g, "");

// Tailwind escapes variant separators and dots in selectors (`\:`, `\/`,
// `\.`); the escape groups below rejoin them, so `.group-hover\:opacity-70`
// reads as the used token. Bare `.` (`.a.b`), `:hover`, and `(…)` still split,
// because each compound part names its own defined class.
const unescapeSelector = (name) => name.replace(/\\(.)/g, "$1");

const defined = new Set();
const readDefinitions = (file) => {
  const names =
    stripCssNoise(readFileSync(file, "utf8")).match(
      /\.[A-Za-z_][A-Za-z0-9_-]*(?:\\.[A-Za-z0-9_-]*)*/g,
    ) ?? [];
  for (const name of names) defined.add(unescapeSelector(name.slice(1)));
};

// A CSS entry is one file or a directory of `*.css` files; the default is the
// assets/css directory itself.
const expandCss = (entry) => {
  if (!existsSync(entry)) return null;
  if (statSync(entry).isDirectory()) {
    return readdirSync(entry)
      .filter((name) => name.endsWith(".css"))
      .sort()
      .map((name) => path.join(entry, name));
  }
  return [entry];
};

for (const entry of cssFiles) {
  const expanded = expandCss(entry);
  if (expanded === null) fail(`stylesheet not found: ${rel(entry)}`);
  else for (const file of expanded) readDefinitions(file);
}
if (process.exitCode) process.exit(process.exitCode);

if (!existsSync(bundle)) {
  fail(
    `bundle not found: ${rel(bundle)} (the tailwind rule in apps/bnest-app/config/config.exs writes it); ` +
      `build it with \`nx run bnest-app:assets:build\` and re-run`,
  );
} else {
  readDefinitions(bundle);
}
if (process.exitCode) process.exit(process.exitCode);

const allowedExact = new Set();
const allowedPrefixes = [];
if (!existsSync(allowlistPath)) {
  fail(`allowlist not found: ${rel(allowlistPath)}`);
} else {
  const lines = readFileSync(allowlistPath, "utf8").split("\n");
  lines.forEach((raw, index) => {
    const line = raw.trim();
    if (line.length === 0 || line.startsWith("#")) return;
    const hash = line.indexOf("#");
    const name = (hash === -1 ? line : line.slice(0, hash)).trim();
    const reason = hash === -1 ? "" : line.slice(hash + 1).trim();
    if (name.length === 0 || reason.length === 0) {
      fail(
        `${rel(allowlistPath)}:${index + 1} needs \`name # reason\` — every entry carries its reason`,
      );
      return;
    }
    if (name.endsWith("*")) allowedPrefixes.push(name.slice(0, -1));
    else allowedExact.add(name);
  });
}
if (process.exitCode) process.exit(process.exitCode);

const isAllowed = (token) =>
  allowedExact.has(token) ||
  allowedPrefixes.some(
    (prefix) => prefix.length > 0 && token.startsWith(prefix),
  );

const missing = [...usedByClass.keys()]
  .filter((token) => !defined.has(token) && !isAllowed(token))
  .sort();

if (missing.length > 0) {
  const detail = missing
    .map(
      (token) => `  - ${token} (used in ${usedByClass.get(token).join(", ")})`,
    )
    .join("\n");
  fail(`${missing.length} undefined class(es):\n${detail}`);
} else {
  process.stdout.write(
    `[ui-class-coverage] PASS: ${usedByClass.size} classes used, all defined or allowed\n`,
  );
}
