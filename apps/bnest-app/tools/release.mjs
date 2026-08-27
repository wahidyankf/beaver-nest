import { execFileSync, spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statfsSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { cpus, freemem, tmpdir, totalmem } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { normalizeProductionOrigin } from "./production-origin.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../../..");
const applicationRoot = resolve(import.meta.dirname, "..");
const deploymentTool = join(import.meta.dirname, "deployment.mjs");
const liveViewProofTool = join(import.meta.dirname, "verify-liveview.mjs");
const resourceMonitorTool = join(import.meta.dirname, "resource-monitor.mjs");
const slots = { blue: 4000, green: 4001 };

export const gateManifest = [
  {
    id: "bnest-quick",
    arguments: [
      "run",
      "-p",
      "bnest-app",
      "-t",
      "test:quick",
      "--skip-nx-cache",
    ],
  },
  {
    id: "bnest-integration",
    arguments: [
      "run",
      "-p",
      "bnest-app",
      "-t",
      "test:integration",
      "--skip-nx-cache",
    ],
  },
  {
    id: "e2e-quick",
    arguments: [
      "run",
      "-p",
      "bnest-app-e2e",
      "-t",
      "test:release-quick",
      "--skip-nx-cache",
    ],
  },
  {
    id: "release-recovery-e2e",
    arguments: [
      "run",
      "-p",
      "bnest-app-e2e",
      "-t",
      "test:e2e",
      "--skip-nx-cache",
      "--",
      "--workers",
      "1",
      "--grep",
      "An automatic LiveView reconnect preserves",
    ],
  },
  {
    id: "release-load-e2e",
    arguments: [
      "run",
      "-p",
      "bnest-app-e2e",
      "-t",
      "test:e2e",
      "--skip-nx-cache",
      "--",
      "--workers",
      "1",
      "--project",
      "chromium",
      "--grep",
      "Ten synthetic visitors preserve recoverable state",
    ],
  },
  {
    id: "repository",
    arguments: [
      "run",
      "-p",
      "badakmini-cli",
      "-t",
      "test:repo",
      "--skip-nx-cache",
    ],
  },
];

export class ReleaseError extends Error {
  constructor(category, message, outcome = "failed") {
    super(message);
    this.category = category;
    this.outcome = outcome;
  }
}

export async function executeRelease(host, options = {}) {
  const startedAt = Date.now();
  const evidenceIds = [];
  let releaseRevision = null;
  let fromState = "preflight";
  let activated = false;
  let activationAttempted = false;
  let routed = false;
  let priorSlot = null;
  let candidateSlot = null;
  let migrationState = "not-required";

  try {
    const preflight = await host.preflight(options.revision);
    releaseRevision = preflight.revision;
    priorSlot = preflight.activeSlot;
    evidenceIds.push("preflight");

    if (preflight.alreadyActive) {
      fromState = "routed-proof";
      await host.proveRouted(releaseRevision);
      evidenceIds.push("coalesced-active", "routed-liveview");

      return result({
        releaseRevision,
        fromState,
        toState: "complete",
        outcome: "passed",
        evidenceIds,
        startedAt,
        nextTransition: "complete",
        errorCategory: null,
        migrationState,
      });
    }

    fromState = "pre-artifact-gates";
    await host.runGates(releaseRevision, gateManifest);
    evidenceIds.push(...gateManifest.map(({ id }) => id));

    fromState = "build";
    await host.build(releaseRevision, evidenceIds);
    evidenceIds.push("artifact-manifest");

    fromState = "migration-proof";
    migrationState = await host.proveMigration(releaseRevision);
    evidenceIds.push("migration-proof");

    candidateSlot = priorSlot === "blue" ? "green" : "blue";
    fromState = "candidate-proof";
    await host.prepareCandidate(candidateSlot, releaseRevision);
    evidenceIds.push("candidate-proof");

    fromState = "promote";
    activationAttempted = true;
    await host.activate(candidateSlot);
    activated = true;
    evidenceIds.push("promotion");

    fromState = "routed-proof";
    await host.proveRouted(releaseRevision);
    routed = true;
    evidenceIds.push("routed-liveview");

    fromState = "cleanup";
    await host.drainAndCleanup(priorSlot, releaseRevision, options.drainMs);
    evidenceIds.push("cleanup");

    return result({
      releaseRevision,
      fromState,
      toState: "complete",
      outcome: "passed",
      evidenceIds,
      startedAt,
      nextTransition: "complete",
      errorCategory: null,
      migrationState,
    });
  } catch (error) {
    const releaseError =
      error instanceof ReleaseError
        ? error
        : new ReleaseError("preflight", "Unexpected release failure");

    if (activationAttempted && !activated) {
      try {
        const recovery = await host.recoverActivation(priorSlot, candidateSlot);
        await host.discardArtifact(releaseRevision);
        evidenceIds.push(recovery, "artifact-cleanup");
        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: recovery === "rollback" ? "rolled-back" : "failed",
          evidenceIds,
          startedAt,
          nextTransition: "diagnose",
          errorCategory: releaseError.category,
          migrationState,
        });
      } catch {
        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: "failed",
          evidenceIds,
          startedAt,
          nextTransition: "recover-route",
          errorCategory: "rollback",
          migrationState,
        });
      }
    }

    if (!activated && candidateSlot && fromState === "candidate-proof") {
      try {
        await host.discardCandidate(candidateSlot);
        evidenceIds.push("candidate-cleanup");
      } catch {
        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: "failed",
          evidenceIds,
          startedAt,
          nextTransition: "cleanup",
          errorCategory: "cleanup",
          migrationState,
        });
      }
    }

    if (activated && !routed) {
      try {
        await host.rollback();
        await host.discardCandidate(candidateSlot);
        await host.discardArtifact(releaseRevision);
        evidenceIds.push("rollback");

        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: "rolled-back",
          evidenceIds,
          startedAt,
          nextTransition: "diagnose",
          errorCategory: releaseError.category,
          migrationState,
        });
      } catch {
        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: "failed",
          evidenceIds,
          startedAt,
          nextTransition: "recover-route",
          errorCategory: "rollback",
          migrationState,
        });
      }
    }

    if (routed) {
      if (["capacity", "continuity"].includes(releaseError.category)) {
        try {
          await host.rollback();
          await host.discardCandidate(candidateSlot);
          await host.discardArtifact(releaseRevision);
          evidenceIds.push("rollback");
          return result({
            releaseRevision,
            fromState,
            toState: "stopped",
            outcome: "rolled-back",
            evidenceIds,
            startedAt,
            nextTransition: "preflight",
            errorCategory: releaseError.category,
            migrationState,
          });
        } catch {
          return result({
            releaseRevision,
            fromState,
            toState: "stopped",
            outcome: "failed",
            evidenceIds,
            startedAt,
            nextTransition: "recover-route",
            errorCategory: "rollback",
            migrationState,
          });
        }
      }

      return result({
        releaseRevision,
        fromState,
        toState: "stopped",
        outcome: "failed",
        evidenceIds,
        startedAt,
        nextTransition: "cleanup",
        errorCategory: releaseError.category,
        migrationState,
      });
    }

    if (
      releaseRevision &&
      ["build", "migration-proof", "candidate-proof"].includes(fromState)
    ) {
      try {
        await host.discardArtifact(releaseRevision);
        evidenceIds.push("artifact-cleanup");
      } catch {
        return result({
          releaseRevision,
          fromState,
          toState: "stopped",
          outcome: "failed",
          evidenceIds,
          startedAt,
          nextTransition: "cleanup",
          errorCategory: "cleanup",
          migrationState,
        });
      }
    }

    return result({
      releaseRevision,
      fromState,
      toState: "stopped",
      outcome: releaseError.outcome,
      evidenceIds,
      startedAt,
      nextTransition: ["deferred", "queued"].includes(releaseError.outcome)
        ? "preflight"
        : "diagnose",
      errorCategory: releaseError.category,
      migrationState,
    });
  } finally {
    await host.releaseLock();
  }
}

function result(fields) {
  return {
    schemaVersion: 1,
    releaseRevision: fields.releaseRevision,
    fromState: fields.fromState,
    toState: fields.toState,
    outcome: fields.outcome,
    evidenceIds: [...new Set(fields.evidenceIds)],
    durationMs: Date.now() - fields.startedAt,
    nextTransition: fields.nextTransition,
    errorCategory: fields.errorCategory,
    migrationState: fields.migrationState,
  };
}

export class MachineHost {
  constructor(environment = process.env) {
    this.environment = environment;
    this.deploymentRoot = requiredPath(environment, "BNEST_DEPLOY_ROOT");
    this.productionOrigin = requiredOrigin(
      environment,
      "BNEST_PRODUCTION_ORIGIN",
    );
    this.lockPath = join(this.deploymentRoot, "release.lock");
    this.queuePath = join(this.deploymentRoot, "release-queue.json");
    this.logsPath = join(this.deploymentRoot, "logs");
    this.manifestsPath = join(this.deploymentRoot, "manifests");
    this.lockOwned = false;
    this.logPath = null;
    this.resourceMonitor = null;
    this.resourceSummaryPath = null;
    this.swapInsBaseline = null;
  }

  async preflight(requestedRevision) {
    const revision = this.assertReleaseSource();
    if (requestedRevision && requestedRevision !== revision)
      throw new ReleaseError(
        "preflight",
        "Requested revision is not current origin/main",
      );
    if (!/^[0-9a-f]{40}$/u.test(revision))
      throw new ReleaseError("preflight", "Release revision is invalid");

    if (!this.acquireLock(revision)) {
      writePrivateJson(this.queuePath, { schemaVersion: 1, revision });
      throw new ReleaseError(
        "concurrency",
        "A release already owns the host lock",
        "queued",
      );
    }
    rmSync(this.queuePath, { force: true });

    mkdirSync(this.logsPath, { recursive: true });
    this.logPath = join(this.logsPath, `release-${revision}.log`);
    writeFileSync(this.logPath, "", { encoding: "utf8", mode: 0o600 });

    this.assertCapacity();
    const statusResult = this.deployment("proxy:status");
    const proxyStatus = parseLastJson(statusResult.stdout, "proxy status");
    if (!proxyStatus.caddyReady)
      throw new ReleaseError("preflight", "Active Caddy route is not ready");

    this.assertPorts(proxyStatus.activeSlot);
    this.startResourceMonitor(revision);
    this.log("preflight passed");
    return {
      activeSlot: proxyStatus.activeSlot,
      alreadyActive: proxyStatus.activeRevision === revision,
      revision,
    };
  }

  async runGates(revision, manifest) {
    for (const gate of manifest) {
      this.assertReleaseSource(revision);
      this.run("npm", ["exec", "--", "nx", ...gate.arguments], {
        cwd: repositoryRoot,
        category: "gate",
        env: boundedReleaseEnvironment(this.environment),
      });
      this.assertReleaseSource(revision);
      this.log(`gate passed ${gate.id} ${revision}`);
      this.assertCapacity();
      this.assertActiveHealth();
    }
  }

  async build(revision, evidenceIds) {
    this.assertReleaseSource(revision);
    const worktree = mkdtempSync(join(tmpdir(), "bnest-release-"));
    let worktreeAdded = false;

    try {
      this.run("git", ["worktree", "add", "--detach", worktree, revision], {
        cwd: repositoryRoot,
        category: "artifact",
      });
      worktreeAdded = true;
      const build = this.deployment("release:build", [], {
        BNEST_DEPLOY_WORKTREE: worktree,
        ERL_FLAGS: "+S 4:4",
      });
      const builtRevision = build.stdout.trim().split(/\r?\n/u).at(-1);
      if (builtRevision !== revision)
        throw new ReleaseError(
          "artifact",
          "Built artifact revision does not match release revision",
        );
    } finally {
      if (worktreeAdded)
        this.run("git", ["worktree", "remove", "--force", worktree], {
          cwd: repositoryRoot,
          category: "cleanup",
        });
      else rmSync(worktree, { recursive: true });
    }

    const artifact = join(this.deploymentRoot, "releases", revision);
    if (!existsSync(artifact))
      throw new ReleaseError("artifact", "Release artifact is missing");

    mkdirSync(this.manifestsPath, { recursive: true });
    const manifest = {
      schemaVersion: 1,
      releaseRevision: revision,
      artifactDigest: digestDirectory(artifact),
      gateEvidenceIds: evidenceIds,
      compatibleSchemaRange: { minimum: 1, maximum: 1 },
      migrations: [],
      migrationSetChecksum: createHash("sha256").update("[]").digest("hex"),
      nodeVersion: process.version,
    };
    writePrivateJson(join(this.manifestsPath, `${revision}.json`), manifest);
    this.assertCapacity();
    this.log(`artifact recorded ${revision}`);
  }

  async proveMigration(revision) {
    const manifest = readPrivateJson(
      join(this.manifestsPath, `${revision}.json`),
    );
    const migrationState = verifyMigrationManifest(manifest);
    this.log(`migration not-required ${revision}`);
    return migrationState;
  }

  async prepareCandidate(slot, revision) {
    this.assertCapacity();
    this.deployment("deploy:prepare", ["--slot", slot, "--revision", revision]);
    const response = this.run(
      "curl",
      [
        "-fsS",
        "--max-time",
        "5",
        "-D",
        "-",
        "-o",
        "/dev/null",
        `http://127.0.0.1:${slots[slot]}/health/ready`,
      ],
      { category: "candidate" },
    );
    if (
      !response.stdout.toLowerCase().includes(`x-bnest-revision: ${revision}`)
    )
      throw new ReleaseError("candidate", "Candidate revision proof failed");
    this.log(`candidate passed ${slot} ${revision}`);
  }

  async activate(slot) {
    this.deployment("deploy:promote", ["--slot", slot]);
    this.log(`promoted ${slot}`);
  }

  async discardCandidate(slot) {
    this.deployment("deploy:retire", ["--slot", slot]);
    this.log(`candidate retired ${slot}`);
  }

  async discardArtifact(revision) {
    for (const root of ["build", "manifests", "releases"])
      rmSync(
        join(
          this.deploymentRoot,
          root,
          root === "manifests" ? `${revision}.json` : revision,
        ),
        {
          force: true,
          recursive: true,
        },
      );
    this.log(`artifact retired ${revision}`);
  }

  async recoverActivation(priorSlot, candidateSlot) {
    const state = parseLastJson(
      this.deployment("proxy:status").stdout,
      "proxy status",
    );
    if (state.activeSlot === candidateSlot) {
      await this.rollback();
      await this.discardCandidate(candidateSlot);
      return "rollback";
    }
    if (state.activeSlot === priorSlot) {
      await this.discardCandidate(candidateSlot);
      return "candidate-cleanup";
    }
    throw new ReleaseError(
      "rollback",
      "Active route is unknown after promotion failure",
    );
  }

  async proveRouted(revision) {
    const proxyStatus = parseLastJson(
      this.deployment("proxy:status").stdout,
      "proxy status",
    );
    if (!proxyStatus.caddyReady || proxyStatus.activeRevision !== revision)
      throw new ReleaseError("routed-proof", "Routed revision proof failed");
    this.run("node", [liveViewProofTool], {
      category: "routed-proof",
      env: {
        ...this.environment,
        BNEST_PRODUCTION_ORIGIN: this.productionOrigin,
      },
    });
    this.log(`routed LiveView passed ${revision}`);
  }

  async drainAndCleanup(priorSlot, revision, drainMs = 300_000) {
    if (!Number.isInteger(drainMs) || drainMs < 0)
      throw new ReleaseError(
        "cleanup",
        "Drain duration must be a nonnegative integer",
      );
    await new Promise((resolvePromise) => setTimeout(resolvePromise, drainMs));
    const resourceSummary = this.stopResourceMonitor(true);
    if (resourceSummary.healthFailures > 0)
      throw new ReleaseError(
        "continuity",
        "Caddy health failed during the release window",
      );
    if (
      resourceSummary.swapInsDelta > 0 ||
      resourceSummary.availableMemoryMinBytes < 2 * 1024 ** 3 ||
      resourceSummary.systemCpuP95Percent >
        Math.max(0, (resourceSummary.logicalCores - 2) * 100)
    )
      throw new ReleaseError(
        "capacity",
        "Release overlap exhausted resource headroom",
      );
    this.deployment("deploy:retire", ["--slot", priorSlot]);
    this.retainArtifacts(revision);
    this.log(`cleanup passed ${revision}`);
  }

  async rollback() {
    this.deployment("deploy:rollback");
    this.log("warm rollback passed");
  }

  async releaseLock() {
    if (!this.lockOwned) return;
    const marker = readPrivateJson(join(this.lockPath, "owner.json"));
    if (marker.pid !== process.pid)
      throw new ReleaseError(
        "concurrency",
        "Refusing to release another process's lock",
      );
    try {
      this.stopResourceMonitor();
    } finally {
      rmSync(this.lockPath, { recursive: true });
      this.lockOwned = false;
    }
  }

  startResourceMonitor(revision) {
    const metricsPath = join(this.deploymentRoot, "metrics");
    const identifier = `${revision}-${Date.now()}-${process.pid}`;
    const outputPath = join(metricsPath, `${identifier}.jsonl`);
    this.resourceSummaryPath = join(metricsPath, `${identifier}.summary.json`);
    this.resourceMonitor = spawn(
      process.execPath,
      [
        resourceMonitorTool,
        "--output",
        outputPath,
        "--summary",
        this.resourceSummaryPath,
        "--deployment-root",
        this.deploymentRoot,
      ],
      { stdio: "ignore" },
    );
  }

  stopResourceMonitor(required = false) {
    if (!this.resourceMonitor) return null;
    this.resourceMonitor.kill("SIGTERM");
    const deadline = Date.now() + 2_000;
    while (!existsSync(this.resourceSummaryPath) && Date.now() < deadline)
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    this.resourceMonitor = null;
    if (!existsSync(this.resourceSummaryPath)) {
      if (!required) {
        this.log("resource evidence summary missing");
        return null;
      }
      throw new ReleaseError("cleanup", "Resource evidence summary is missing");
    }

    let summary;
    try {
      summary = readPrivateJson(this.resourceSummaryPath);
    } catch (error) {
      if (required) throw error;
      this.log("resource evidence summary unreadable");
      return null;
    }
    if (!validResourceSummary(summary)) {
      if (required)
        throw new ReleaseError(
          "cleanup",
          "Resource evidence summary is invalid",
        );
      this.log("resource evidence summary invalid");
      return null;
    }
    this.log(`resource evidence ${basename(this.resourceSummaryPath)}`);
    return summary;
  }

  acquireLock(revision) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        mkdirSync(this.lockPath, { mode: 0o700 });
        this.lockOwned = true;
        try {
          writePrivateJson(join(this.lockPath, "owner.json"), {
            schemaVersion: 1,
            pid: process.pid,
            revision,
          });
        } catch (error) {
          rmSync(this.lockPath, { recursive: true });
          this.lockOwned = false;
          throw error;
        }
        return true;
      } catch (error) {
        if (error?.code !== "EEXIST" || attempt > 0) throw error;
        if (!staleProcessMarker(join(this.lockPath, "owner.json")))
          return false;
        rmSync(this.lockPath, { recursive: true });
      }
    }
    return false;
  }

  deployment(command, arguments_ = [], extraEnvironment = {}) {
    return this.run("node", [deploymentTool, command, ...arguments_], {
      cwd: applicationRoot,
      category: "configuration",
      env: { ...this.environment, ...extraEnvironment },
    });
  }

  run(command, arguments_, options = {}) {
    const result_ = spawnSync(command, arguments_, {
      cwd: options.cwd ?? applicationRoot,
      env: options.env ?? this.environment,
      encoding: "utf8",
      maxBuffer: 20 * 1024 * 1024,
    });
    this.log(
      `${command} ${arguments_.join(" ")}\n${result_.stdout ?? ""}\n${result_.stderr ?? ""}`,
    );
    if (result_.error) throw result_.error;
    if (result_.status !== 0)
      throw new ReleaseError(
        options.category ?? "preflight",
        `${command} failed`,
      );
    return result_;
  }

  log(message) {
    if (this.logPath) appendFileSync(this.logPath, `${message}\n`, "utf8");
  }

  assertCapacity() {
    const availableMemory = availableMemoryBytes();
    if (availableMemory < 9 * 1024 ** 3)
      throw new ReleaseError(
        "capacity",
        "Less than 9 GiB memory is available",
        "deferred",
      );
    const logicalCores = cpus().length;
    if (logicalCores < 8)
      throw new ReleaseError(
        "capacity",
        "Fewer than eight logical cores are available",
        "deferred",
      );
    if (systemCpuPercent() > Math.max(0, (logicalCores - 6) * 100))
      throw new ReleaseError(
        "capacity",
        "CPU use does not leave release and safety headroom",
        "deferred",
      );
    const disk = statfsSync(this.deploymentRoot);
    if (disk.bavail * disk.bsize < 13 * 1024 ** 3)
      throw new ReleaseError(
        "capacity",
        "Less than 13 GiB release disk is available",
        "deferred",
      );
    if (this.swapInsBaseline === null) {
      if (recentSwapIns() > 0)
        throw new ReleaseError(
          "capacity",
          "Swap-in activity is present",
          "deferred",
        );
      this.swapInsBaseline = swapInCount();
    } else if (swapInCount() > this.swapInsBaseline) {
      throw new ReleaseError(
        "capacity",
        "Swap-in activity occurred during release work",
        "deferred",
      );
    }
  }

  assertPorts(activeSlot) {
    const inactiveSlot = activeSlot === "blue" ? "green" : "blue";
    if (!listenerPids(slots[activeSlot]).length)
      throw new ReleaseError(
        "port",
        "The active production port has no listener",
      );
    if (listenerPids(slots[inactiveSlot]).length)
      throw new ReleaseError(
        "port",
        "The inactive production port is occupied",
      );
    if (!listenerPids(4100).length)
      throw new ReleaseError("port", "The stable Caddy port has no listener");
    if (listenerPids(4010).length)
      throw new ReleaseError("port", "The release E2E port is occupied");
  }

  assertActiveHealth() {
    const status = parseLastJson(
      this.deployment("proxy:status").stdout,
      "proxy status",
    );
    if (!status.caddyReady)
      throw new ReleaseError(
        "preflight",
        "Active route degraded during release gates",
      );
  }

  assertReleaseSource(expectedRevision) {
    const branch = output("git", ["branch", "--show-current"], repositoryRoot);
    const revision = output("git", ["rev-parse", "HEAD"], repositoryRoot);
    const remoteRevision = output(
      "git",
      ["rev-parse", "origin/main"],
      repositoryRoot,
    );
    const status = output("git", ["status", "--porcelain"], repositoryRoot);
    if (
      branch !== "main" ||
      status ||
      revision !== remoteRevision ||
      (expectedRevision && revision !== expectedRevision)
    )
      throw new ReleaseError(
        "preflight",
        "Release source must remain clean origin/main",
      );
    return revision;
  }

  retainArtifacts(activeRevision) {
    const state = parseLastJson(
      this.deployment("proxy:status").stdout,
      "proxy status",
    );
    const retained = new Set(
      [activeRevision, state.previousRevision].filter(Boolean),
    );
    for (const root of ["build", "releases"]) {
      const directory = join(this.deploymentRoot, root);
      if (!existsSync(directory)) continue;
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (!entry.isDirectory() || !/^[0-9a-f]{40}$/u.test(entry.name))
          continue;
        if (!retained.has(entry.name))
          rmSync(join(directory, entry.name), { recursive: true });
      }
    }
    if (existsSync(this.manifestsPath)) {
      for (const entry of readdirSync(this.manifestsPath, {
        withFileTypes: true,
      })) {
        const revision = entry.name.replace(/\.json$/u, "");
        if (
          entry.isFile() &&
          /^[0-9a-f]{40}\.json$/u.test(entry.name) &&
          !retained.has(revision)
        )
          rmSync(join(this.manifestsPath, entry.name));
      }
    }
  }
}

export function verifyMigrationManifest(manifest) {
  const checksum = createHash("sha256")
    .update(JSON.stringify(manifest.migrations))
    .digest("hex");
  if (checksum !== manifest.migrationSetChecksum)
    throw new ReleaseError(
      "migration",
      "Migration manifest checksum does not match",
    );
  if (manifest.migrations.length !== 0)
    throw new ReleaseError(
      "migration",
      "Concrete migrations require an approved migration adapter",
    );
  return "not-required";
}

function requiredValue(environment, name) {
  const value = environment[name];
  if (!value) throw new ReleaseError("configuration", `${name} is required`);
  return value;
}

function requiredPath(environment, name) {
  const value = resolve(requiredValue(environment, name));
  if (inside(repositoryRoot, value))
    throw new ReleaseError(
      "configuration",
      `${name} must be outside the repository`,
    );
  return value;
}

function requiredOrigin(environment, name) {
  try {
    return normalizeProductionOrigin(requiredValue(environment, name)).origin;
  } catch (error) {
    throw new ReleaseError("configuration", `${name}: ${error.message}`);
  }
}

function inside(parent, child) {
  const path = relative(parent, child);
  return path === "" || (!path.startsWith("..") && !path.startsWith("/"));
}

function output(command, arguments_, cwd) {
  return execFileSync(command, arguments_, { cwd, encoding: "utf8" }).trim();
}

function parseLastJson(output_, label) {
  for (const line of output_.trim().split(/\r?\n/u).reverse()) {
    try {
      return JSON.parse(line);
    } catch {
      // Deployment status is pretty-printed, so fall through to the full payload.
    }
  }
  try {
    return JSON.parse(output_);
  } catch {
    throw new ReleaseError("preflight", `${label} was not valid JSON`);
  }
}

function writePrivateJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
}

function staleProcessMarker(path) {
  try {
    const marker = readPrivateJson(path);
    if (marker.schemaVersion !== 1 || !Number.isInteger(marker.pid))
      return false;
    try {
      process.kill(marker.pid, 0);
      return false;
    } catch (error) {
      return error?.code === "ESRCH";
    }
  } catch {
    return false;
  }
}

function validResourceSummary(summary) {
  const numericFields = [
    "sampleCount",
    "logicalCores",
    "availableMemoryMinBytes",
    "systemCpuP95Percent",
    "serviceRssPeakBytes",
    "diskFreeMinBytes",
    "swapInsDelta",
    "caddyHealthLatencyP95Ms",
    "healthFailures",
  ];
  return (
    summary?.schemaVersion === 1 &&
    numericFields.every(
      (field) => Number.isFinite(summary[field]) && summary[field] >= 0,
    ) &&
    summary.sampleCount > 0
  );
}

function readPrivateJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    throw new ReleaseError(
      "artifact",
      `Manifest ${basename(path)} is unreadable`,
    );
  }
}

function digestDirectory(root) {
  const digest = createHash("sha256");

  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort(
      (a, b) => a.name.localeCompare(b.name),
    )) {
      const path = join(directory, entry.name);
      const relativePath = relative(root, path);
      if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) {
        const stats = statSync(path);
        digest.update(`${relativePath}\0${stats.mode}\0${stats.size}\0`);
        digest.update(readFileSync(path));
      }
    }
  };

  walk(root);
  return digest.digest("hex");
}

function availableMemoryBytes() {
  if (process.platform !== "darwin") return freemem();
  const result_ = spawnSync("memory_pressure", ["-Q"], { encoding: "utf8" });
  const matched = result_.stdout?.match(/free percentage:\s*(\d+)%/u);
  return matched ? (totalmem() * Number(matched[1])) / 100 : freemem();
}

function recentSwapIns() {
  if (process.platform !== "darwin") return 0;
  const before = swapInCount();
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 250);
  return Math.max(0, swapInCount() - before);
}

function swapInCount() {
  if (process.platform !== "darwin") return 0;
  const result_ = spawnSync("vm_stat", [], { encoding: "utf8" });
  return Number(result_.stdout?.match(/Swapins:\s+(\d+)\./u)?.[1] ?? 0);
}

function systemCpuPercent() {
  const result_ = spawnSync("ps", ["-A", "-o", "%cpu="], { encoding: "utf8" });
  if (result_.status !== 0) return Number.POSITIVE_INFINITY;
  return result_.stdout
    .trim()
    .split(/\s+/u)
    .reduce((total, value) => total + (Number(value) || 0), 0);
}

export function boundedReleaseEnvironment(environment) {
  const releaseEnvironment = { ...environment, ERL_FLAGS: "+S 4:4" };
  for (const name of [
    "BNEST_DEPLOY_ROOT",
    "BNEST_RUNTIME_ROOT",
    "BNEST_DEPLOY_COOKIE_FILE",
    "BNEST_DEPLOY_SECRET_KEY_BASE_FILE",
    "BNEST_DEPLOY_WORKTREE",
    "BNEST_PRODUCTION_ORIGIN",
    "RELEASE_COOKIE",
    "SECRET_KEY_BASE",
    "PHX_HOST",
    "PORT",
  ])
    delete releaseEnvironment[name];
  return releaseEnvironment;
}

function listenerPids(port) {
  const result_ = spawnSync(
    "lsof",
    ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-t"],
    { encoding: "utf8" },
  );
  if (result_.status !== 0) return [];
  return result_.stdout.trim().split(/\s+/u).filter(Boolean);
}

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  let outputResult;
  try {
    const revision = argumentValue("--revision");
    const host = new MachineHost();
    outputResult = await executeRelease(host, { revision });
  } catch (error) {
    const releaseError =
      error instanceof ReleaseError
        ? error
        : new ReleaseError("configuration", "Release initialization failed");
    outputResult = result({
      releaseRevision: null,
      fromState: "preflight",
      toState: "stopped",
      outcome: releaseError.outcome,
      evidenceIds: [],
      startedAt: Date.now(),
      nextTransition: "diagnose",
      errorCategory: releaseError.category,
      migrationState: "not-required",
    });
  }
  process.stdout.write(`${JSON.stringify(outputResult)}\n`);
  if (!["passed", "queued", "deferred"].includes(outputResult.outcome))
    process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  await main();
