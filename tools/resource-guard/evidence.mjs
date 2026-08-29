import {
  appendFileSync,
  chmodSync,
  mkdirSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, join } from "node:path";

import { percentile } from "./policy.mjs";

const dayMs = 24 * 60 * 60 * 1000;
const maximumEvidenceBytes = 50 * 1024 ** 2;

export function cleanupEvidence(root, options = {}) {
  const now = options.now ?? Date.now();
  const preserve = new Set(options.preserve ?? []);
  mkdirSync(root, { recursive: true, mode: 0o700 });
  chmodSync(root, 0o700);
  const entries = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const path = join(root, entry.name);
      return { name: entry.name, path, stats: statSync(path) };
    });
  for (const entry of entries) {
    const age = now - entry.stats.mtimeMs;
    const retention = entry.name.endsWith(".summary.json")
      ? 30 * dayMs
      : 7 * dayMs;
    if (age > retention && !preserve.has(entry.path)) rmSync(entry.path);
  }
  const retained = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const path = join(root, entry.name);
      return { path, stats: statSync(path) };
    })
    .toSorted((left, right) => left.stats.mtimeMs - right.stats.mtimeMs);
  let total = retained.reduce((sum, entry) => sum + entry.stats.size, 0);
  for (const entry of retained) {
    if (total <= maximumEvidenceBytes) break;
    if (preserve.has(entry.path)) continue;
    rmSync(entry.path);
    total -= entry.stats.size;
  }
}

export class EvidenceWriter {
  constructor(root, identifier) {
    mkdirSync(root, { recursive: true, mode: 0o700 });
    chmodSync(root, 0o700);
    this.outputPath = join(root, `${identifier}.jsonl`);
    this.summaryPath = join(root, `${identifier}.summary.json`);
    this.samples = [];
    writeFileSync(this.outputPath, "", {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
  }

  append(sample) {
    this.samples.push(sample);
    appendFileSync(this.outputPath, `${JSON.stringify(sample)}\n`, "utf8");
  }

  finalize({ taskClass, outcome, healthFailures = 0 }) {
    const samples = this.samples;
    const numeric = (field) =>
      samples.map((sample) => sample[field]).filter(Number.isFinite);
    const minimum = (field) => {
      const values = numeric(field);
      return values.length > 0 ? Math.min(...values) : null;
    };
    const maximum = (field) => {
      const values = numeric(field);
      return values.length > 0 ? Math.max(...values) : null;
    };
    const first = samples[0] ?? {};
    const last = samples.at(-1) ?? {};
    const summary = {
      schemaVersion: 2,
      sampleCount: samples.length,
      taskClass,
      outcome,
      availableParallelism: first.availableParallelism ?? 0,
      availableNonCompressedEstimateMinBytes: minimum(
        "availableNonCompressedEstimateBytes",
      ),
      memoryPressureLevelMax: maximum("memoryPressureLevel"),
      compressorAvailableAll: samples.every(
        ({ compressorAvailable }) => compressorAvailable === true,
      ),
      compressorPayloadPeakBytes: maximum("compressorPayloadBytes"),
      cpuUtilizationP95Percent:
        percentile(numeric("cpuUtilizationPercent"), 0.95) ?? 0,
      diskFreeMinBytes:
        numeric("diskFreeBytes").length > 0 ? minimum("diskFreeBytes") : null,
      swapInsDelta:
        Number.isFinite(first.swapIns) && Number.isFinite(last.swapIns)
          ? Math.max(0, last.swapIns - first.swapIns)
          : 0,
      swapOutsDelta:
        Number.isFinite(first.swapOuts) && Number.isFinite(last.swapOuts)
          ? Math.max(0, last.swapOuts - first.swapOuts)
          : 0,
      swapFreeMinBytes:
        numeric("swapFreeBytes").length > 0 ? minimum("swapFreeBytes") : null,
      healthFailures,
    };
    writeFileSync(this.summaryPath, `${JSON.stringify(summary, null, 2)}\n`, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    return summary;
  }
}

export function evidenceIdentifier(
  prefix,
  now = Date.now(),
  pid = process.pid,
) {
  return `${prefix}-${now}-${pid}`.replaceAll(/[^a-zA-Z0-9._-]/gu, "-");
}

export function safeEvidenceName(path) {
  return basename(path);
}
