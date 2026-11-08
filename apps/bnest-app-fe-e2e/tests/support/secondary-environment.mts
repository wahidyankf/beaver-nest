// The environments of the secondary processes that step code starts: `mix run -e` reads, storage CLI runs, and rollout
// candidates (ADR 001, section 2, least privilege). None of them calls the control routes, so none starts with the
// test-control secret. Only the Playwright process and the primary `mix phx.server` keep it.
//
// This module must stay out of the Playwright config's import graph. A module the config imports cannot be loaded by
// step code through CommonJS, so the filter below repeats `browserEnvironment` from browser-environment.mts, and the
// unit test keeps the two equal.

const testControlSecretName = "BNEST_TEST_CONTROL_SECRET";

// Every variable of the environment except the test-control secret, with unset values dropped. The input is not changed.
export function withoutControlSecret(
  environment: NodeJS.ProcessEnv,
): Record<string, string> {
  const filtered: Record<string, string> = {};

  for (const [name, value] of Object.entries(environment)) {
    if (name !== testControlSecretName && value !== undefined) {
      filtered[name] = value;
    }
  }

  return filtered;
}

// The environment of a secondary process that reads one instance. It takes the instance's paths from the spawn
// response, the run's backup configuration, and the test layer. It starts from the inherited environment without the
// secret, and the instance's own variables win over any inherited ones.
export function secondaryEnvironment(
  base: NodeJS.ProcessEnv,
  instance: Record<string, string>,
  options: { backupConfig: string; runId: string },
): Record<string, string> {
  return {
    ...withoutControlSecret(base),
    ...instance,
    BNEST_BACKUP_CONFIG: options.backupConfig,
    BNEST_TEST_LAYER: "integration",
    BNEST_TEST_RUN_ID: options.runId,
    MIX_ENV: "test",
  };
}
