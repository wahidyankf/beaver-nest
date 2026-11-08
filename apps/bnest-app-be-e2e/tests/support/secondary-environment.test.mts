import assert from "node:assert/strict";
import test from "node:test";
import { browserEnvironment } from "./browser-environment.mts";
import {
  secondaryEnvironment,
  withoutControlSecret,
} from "./secondary-environment.mts";

const instanceId = "a1b2c3d4e5f6g7h8";
const secret = "b".repeat(64);

test("a secondary process gets its instance's paths and the test layer, and never the control secret", () => {
  const environment = secondaryEnvironment(
    {
      BNEST_RUNTIME_ROOT: "/stale/root",
      BNEST_TEST_CONTROL_SECRET: secret,
      PATH: "/usr/bin",
    },
    {
      BNEST_RUNTIME_ROOT: `/runs/run-1/instances/${instanceId}`,
      BNEST_STORAGE_CONFIG: "/runs/run-1/storage-config/storage.json",
      BNEST_TEST_INSTANCE_ID: instanceId,
    },
    { backupConfig: "/runs/run-1/storage-config/backup.json", runId: "run-1" },
  );

  assert.deepEqual(environment, {
    BNEST_BACKUP_CONFIG: "/runs/run-1/storage-config/backup.json",
    BNEST_RUNTIME_ROOT: `/runs/run-1/instances/${instanceId}`,
    BNEST_STORAGE_CONFIG: "/runs/run-1/storage-config/storage.json",
    BNEST_TEST_INSTANCE_ID: instanceId,
    BNEST_TEST_LAYER: "integration",
    BNEST_TEST_RUN_ID: "run-1",
    MIX_ENV: "test",
    PATH: "/usr/bin",
  });
});

test("the secondary filter agrees with the browser filter, and does not change its input", () => {
  const inherited = {
    BNEST_TEST_CONTROL_SECRET: secret,
    HOME: "/synthetic/e2e-runner",
    UNSET: undefined,
  };

  assert.deepEqual(
    withoutControlSecret(inherited),
    browserEnvironment(inherited),
  );
  assert.equal(inherited.BNEST_TEST_CONTROL_SECRET, secret);
});
