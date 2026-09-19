import path from "node:path";
import { routedStorageConfigPath } from "./storage-authority";

// Shared config/env constants for the routed-rollout candidate infrastructure
// -- split out of `routed-rollout.ts` purely to stay under this project's
// max-lines lint budget; both `routed-rollout.ts` and `candidate-pool.ts`
// import from here instead of from each other.

export const repositoryRoot = process.cwd();
export const appDirectory = path.join(repositoryRoot, "apps/bnest-app");
export const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
export const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
export const publicPort = optionalPort("BNEST_E2E_PORT", 4010);
export const primaryPort = optionalPort(
  "BNEST_E2E_BACKEND_PORT",
  publicPort + 100,
);
export const candidatePort = primaryPort + 1;
export const adminPort = optionalPort(
  "BNEST_E2E_CADDY_ADMIN_PORT",
  publicPort + 200,
);
export const caddyBinary = process.env["BNEST_E2E_CADDY_BIN"] ?? "caddy";

const revisions = new Map<number, string>([
  [primaryPort, "e2e-blue"],
  [candidatePort, "e2e-green"],
  [candidatePort + 1, "e2e-yellow"],
]);

export function requiredRevision(port: number): string {
  const revision = revisions.get(port);
  if (revision === undefined) throw new Error(`unknown rollout port ${port}`);
  return revision;
}

export function routedEnvironment(): NodeJS.ProcessEnv {
  return {
    ...process.env,
    BNEST_BACKUP_CONFIG: path.join(
      runtimeRoot,
      "storage-config",
      "backup.json",
    ),
    BNEST_RUNTIME_ROOT: runtimeRoot,
    BNEST_STORAGE_CONFIG: routedStorageConfigPath(),
    BNEST_TEST_LAYER: "integration",
    BNEST_TEST_RUN_ID: runId,
    MIX_ENV: "test",
  };
}

export function optionalPort(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(value) || value < 1 || value > 65_535) {
    throw new Error(`${name} must be a valid TCP port`);
  }
  return value;
}
