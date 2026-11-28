// Plain Vitest unit coverage for the `proxy:install` and `proxy:status`
// deployment commands (`tools/deployment.mjs`). Each scenario runs the real
// tool module in a child Node process through a small inline driver: the
// driver calls `createDeploymentTool` with stub doubles for the service
// manager and the child processes, while the deploy root, the state file,
// and the written Caddyfile stay real files in a temporary directory. No
// Caddy binary runs and no system service is installed. The driver boundary
// also keeps the untyped tool sources out of this file's module graph, so
// the assets typecheck never loads them.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, inject, it } from "vitest";

declare module "vitest" {
  export interface ProvidedContext {
    nodeBinary: string;
  }
}

const revision = "0123456789abcdef0123456789abcdef01234567";
const toolUrl = new URL("../../../tools/deployment.mjs", import.meta.url).href;

interface InstallEvidence {
  serviceCalls: string[];
  runCalls: string[][];
  printed: string;
  config: string;
}

interface StatusEvidence {
  activeSlot: string;
  activeRevision: string;
  caddyReady: boolean;
  httpStatus: string | null;
}

function runDriver(script: string, args: string[], deployRoot: string) {
  // env replaces the child's PATH, so the Node binary comes from the vitest config
  // (inject), not from PATH.
  const result = spawnSync(
    inject("nodeBinary"),
    ["--input-type=module", "-e", script, ...args],
    {
      encoding: "utf8",
      env: { BNEST_DEPLOY_ROOT: deployRoot },
    },
  );
  return {
    status: result.status,
    stdout: String(result.stdout ?? ""),
    stderr: String(result.stderr ?? ""),
  };
}

describe("proxy deployment commands", () => {
  // @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: proxy:install writes a validated Caddy configuration for the active slot and installs its service
  it("writes the active slot Caddyfile, validates it, and installs its service", () => {
    const root = mkdtempSync(join(tmpdir(), "bnest-proxy-install-"));
    try {
      writeFileSync(
        join(root, "state.json"),
        JSON.stringify({ activeSlot: "blue", activeRevision: revision }),
      );
      const script = [
        "import { readFileSync } from 'node:fs';",
        "import { join } from 'node:path';",
        "const toolPath = process.argv[1];",
        "process.argv[1] = 'proxy-driver';",
        "const toolModule = await import(toolPath);",
        "const serviceCalls = [];",
        "const runCalls = [];",
        "const printed = [];",
        "const originalWrite = process.stdout.write.bind(process.stdout);",
        "process.stdout.write = (chunk) => { printed.push(String(chunk)); return true; };",
        "const tool = toolModule.createDeploymentTool({",
        "  service: {",
        "    caddyBinary: () => 'caddy',",
        "    ensureCaddy: () => { serviceCalls.push('ensure-caddy'); },",
        "    installCaddyService: () => { serviceCalls.push('install-caddy-service'); },",
        "  },",
        "  run: (command, args) => { runCalls.push([command].concat(args)); },",
        "});",
        "tool.installProxy();",
        "process.stdout.write = originalWrite;",
        "const config = readFileSync(join(process.argv[2], 'caddy', 'Caddyfile'), 'utf8');",
        "const evidence = { serviceCalls, runCalls, printed: printed.join(''), config };",
        "process.stdout.write(JSON.stringify(evidence) + '\\n');",
      ].join("\n");
      const run = runDriver(script, [toolUrl, root], root);
      expect(run.stderr).toBe("");
      expect(run.status).toBe(0);
      const evidence = JSON.parse(run.stdout) as InstallEvidence;
      expect(evidence.serviceCalls).toEqual([
        "ensure-caddy",
        "install-caddy-service",
      ]);
      expect(evidence.runCalls.map((call) => call[0])).toEqual([
        "caddy",
        "caddy",
      ]);
      expect(evidence.runCalls[0]?.slice(1, 3)).toEqual(["fmt", "--overwrite"]);
      expect(evidence.runCalls[1]?.slice(1, 3)).toEqual([
        "validate",
        "--config",
      ]);
      expect(evidence.config).toMatch(/reverse_proxy 127\.0\.0\.1:4000/u);
      expect(evidence.printed).toContain(
        "Caddy is managed at 127.0.0.1:4100 for blue.",
      );
      const written = readFileSync(join(root, "caddy", "Caddyfile"), "utf8");
      expect(written).toBe(evidence.config);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  // @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: proxy:status prints the routed slot and revision and exits 1 when Caddy is not ready
  it("prints the routed slot and revision and exits 1 when Caddy is not ready", () => {
    const root = mkdtempSync(join(tmpdir(), "bnest-proxy-status-"));
    try {
      writeFileSync(
        join(root, "state.json"),
        JSON.stringify({
          activeSlot: "green",
          activeRevision: revision,
          previousSlot: "blue",
          previousRevision: "fedcba9876543210fedcba9876543210fedcba98",
        }),
      );
      const script = [
        "const toolPath = process.argv[1];",
        "process.argv[1] = 'proxy-driver';",
        "const toolModule = await import(toolPath);",
        "const probe = JSON.parse(process.argv[2]);",
        "const tool = toolModule.createDeploymentTool({",
        "  service: { caddyBinary: () => 'caddy' },",
        "  spawnSync: () => probe,",
        "});",
        "tool.printStatus();",
        "process.exit(process.exitCode || 0);",
      ].join("\n");
      const route = (probe: { status: number | null; stdout: string }) => {
        const run = runDriver(script, [toolUrl, JSON.stringify(probe)], root);
        expect(run.stderr).toBe("");
        return {
          status: run.status,
          evidence: JSON.parse(run.stdout) as StatusEvidence,
        };
      };

      const ready = route({ status: 0, stdout: "200\n" });
      expect(ready.status).toBe(0);
      expect(ready.evidence).toMatchObject({
        activeSlot: "green",
        activeRevision: revision,
        caddyReady: true,
        httpStatus: "200",
      });

      const notReady = route({ status: 7, stdout: "" });
      expect(notReady.status).toBe(1);
      expect(notReady.evidence).toMatchObject({
        activeSlot: "green",
        activeRevision: revision,
        caddyReady: false,
      });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
