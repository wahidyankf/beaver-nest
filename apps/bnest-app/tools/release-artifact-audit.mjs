// Audits a built production release for test-only code (ADR 001 section 7).
// Pure Node: it reads the BEAM chunks directly, so no Erlang or Elixir tool runs.
//
// Usage: node tools/release-artifact-audit.mjs <release-directory>
// Exit codes: 0 passed, 1 violations found, 2 bad usage.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

// Every module whose name starts with one of these is test-only. The first
// prefix covers BnestApp.TestInstance* and BnestApp.Test*.
const testingModulePrefixes = [
  "Elixir.BnestApp.Test",
  "Elixir.BnestAppWeb.TestingControl",
];
const routerBeam = "Elixir.BnestAppWeb.Router.beam";
// The router must name neither the testing path nor a testing module. The raw
// bytes are searched, and so is the literal table when it is zlib-compressed.
const routerNeedles = ["__bnest_testing", ...testingModulePrefixes];

export class ReleaseArtifactAuditError extends Error {
  constructor(violations) {
    super(
      [
        "Release artifact audit failed:",
        ...violations.map((violation) => `- ${violation}`),
      ].join("\n"),
    );
    this.name = "ReleaseArtifactAuditError";
    this.violations = violations;
  }
}

// Returns { ebins, beams } when the release is clean. Throws
// ReleaseArtifactAuditError listing every violation otherwise.
export function auditReleaseArtifact(releaseDirectory) {
  try {
    return auditTree(resolve(releaseDirectory));
  } catch (error) {
    if (error instanceof ReleaseArtifactAuditError) throw error;
    throw new ReleaseArtifactAuditError([
      `release cannot be read: ${error.message}`,
    ]);
  }
}

function auditTree(root) {
  if (!existsSync(root))
    throw new ReleaseArtifactAuditError([`${root} does not exist`]);

  const violations = [];
  const ebins = [];
  findEbins(root, root, ebins, violations);
  if (ebins.length === 0)
    violations.push("no ebin directory under the release");

  let beams = 0;
  let routerFound = false;
  for (const ebin of ebins) {
    for (const name of readdirSync(ebin).sort()) {
      if (!name.endsWith(".beam")) continue;
      beams += 1;
      const label = relative(root, join(ebin, name));
      if (testingModulePrefixes.some((prefix) => name.startsWith(prefix)))
        violations.push(`${label}: test-only module`);
      if (name === routerBeam) {
        routerFound = true;
        violations.push(
          ...routerViolations(label, readFileSync(join(ebin, name))),
        );
      }
    }
  }
  if (ebins.length > 0 && !routerFound)
    violations.push(`${routerBeam} is missing from the release`);

  if (violations.length > 0) throw new ReleaseArtifactAuditError(violations);
  return { ebins: ebins.length, beams };
}

// The walk cannot see through a symbolic link, so a link named `ebin` or one
// that leads to a directory is a violation, not a silent skip.
function findEbins(root, directory, found, violations) {
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort(
    (left, right) => left.name.localeCompare(right.name),
  )) {
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      if (entry.name === "ebin" || isDirectory(path))
        violations.push(
          `${relative(root, path)}: symbolic link in the release`,
        );
      continue;
    }
    if (entry.name === "ebin") {
      if (entry.isDirectory()) found.push(path);
      continue;
    }
    if (entry.isDirectory()) findEbins(root, path, found, violations);
  }
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function routerViolations(label, bytes) {
  let literals;
  try {
    literals = compressedLiterals(bytes);
  } catch (error) {
    return [`${label}: unreadable BEAM file (${error.message})`];
  }
  return routerNeedles
    .filter((needle) => bytes.includes(needle) || literals.includes(needle))
    .map((needle) => `${label}: names ${needle}`);
}

// A BEAM file is an IFF form: "FOR1", a size, "BEAM", then chunks, each with
// an id, a size and padding to 4 bytes. Returns the inflated literal table
// when LitT is zlib-compressed (older OTP), or an empty buffer otherwise.
function compressedLiterals(bytes) {
  if (
    bytes.length < 12 ||
    bytes.toString("latin1", 0, 4) !== "FOR1" ||
    bytes.toString("latin1", 8, 12) !== "BEAM"
  )
    throw new Error("missing FOR1/BEAM header");

  let offset = 12;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) throw new Error("truncated chunk header");
    const id = bytes.toString("latin1", offset, offset + 4);
    const size = bytes.readUInt32BE(offset + 4);
    const start = offset + 8;
    if (start + size > bytes.length) throw new Error("truncated chunk");
    if (id === "LitT")
      return inflatedLiteralTable(bytes.subarray(start + 4, start + size));
    offset = start + size + ((4 - (size % 4)) % 4);
  }
  return Buffer.alloc(0);
}

// A plain (uncompressed) table fails to inflate. The raw scan of the whole file
// already searches those bytes, so the failure only means "nothing extra here".
function inflatedLiteralTable(table) {
  try {
    return inflateSync(table);
  } catch {
    return Buffer.alloc(0);
  }
}

function main(argv) {
  if (argv.length !== 1) {
    process.stderr.write(
      "usage: node tools/release-artifact-audit.mjs <release-directory>\n",
    );
    return 2;
  }
  try {
    const summary = auditReleaseArtifact(argv[0]);
    process.stdout.write(
      `artifact audit passed: ${summary.beams} beams in ${summary.ebins} ebin directories\n`,
    );
    return 0;
  } catch (error) {
    if (!(error instanceof ReleaseArtifactAuditError)) throw error;
    process.stderr.write(`${error.message}\n`);
    return 1;
  }
}

if (fileURLToPath(import.meta.url) === resolve(process.argv[1] ?? ""))
  process.exitCode = main(process.argv.slice(2));
