// Shared fakes for the lifecycle unit tests. They stand in for the testing control client, so the state machine runs
// without a server. Not a test file itself: the two `*.test.mts` files import it.

import type { BeginOptions, LifecycleClient } from "./test-instance-lifecycle.mts";
import type { AccountPlan } from "./test-instance-accounts.mts";
import type { SpawnedInstance, SpawnRequest } from "./testing-control-records.mts";

export const instanceId = "a1b2c3d4e5f6g7h8";
export const otherId = "zz99yy88xx77ww66";

export function spawnedFor(id: string, request: SpawnRequest): SpawnedInstance {
  return {
    instanceId: id,
    label: request.label,
    phase: request.phase ?? "sqlite_primary",
    generation: `test-${id}`,
    accounts: (request.seed?.accounts ?? []).map((account) => ({
      username: account.username,
      userId: `user-${account.username}`,
      roles: account.roles,
    })),
    environment: {
      BNEST_TEST_INSTANCE_ID: id,
      BNEST_RUNTIME_ROOT: "/data/test/runs/run-1",
      BNEST_STORAGE_CONFIG: "/synthetic/x/bnest/data/test/runs/run-1/storage-config/storage.json",
    },
  };
}

export type FakeCalls = {
  spawns: SpawnRequest[];
  seeds: { id: string; seedKey: string }[];
  deletes: string[];
};

// Each failure is a rejected promise, so the fake never needs an `async` body without an `await`.
export function fakeClient(
  options: {
    nextId?: string;
    spawnFails?: boolean;
    deleteFails?: boolean;
    returnId?: string;
  } = {},
): { client: LifecycleClient; calls: FakeCalls } {
  const calls: FakeCalls = { spawns: [], seeds: [], deletes: [] };
  const client: LifecycleClient = {
    spawnInstance: (request) => {
      calls.spawns.push(request);
      if (options.spawnFails === true) {
        return Promise.reject(new Error("spawn refused"));
      }
      const id = options.returnId ?? request.instanceId ?? options.nextId ?? instanceId;
      return Promise.resolve(spawnedFor(id, request));
    },
    seedInstance: (id, request) => {
      calls.seeds.push({ id, seedKey: request.seedKey });
      return Promise.resolve({ seedKey: request.seedKey, applied: true });
    },
    deleteInstance: (id) => {
      calls.deletes.push(id);
      if (options.deleteFails === true) {
        return Promise.reject(new Error("delete refused"));
      }
      return Promise.resolve();
    },
  };
  return { client, calls };
}

export function beginWith(
  accounts: (id: string) => readonly AccountPlan[],
): BeginOptions {
  return { label: "scenario", phase: "sqlite_primary", accounts };
}
