// Record types and response guards for the testing control client (ADR 001, section 2).
// The guards accept only the documented shapes. Nested seed payloads are typed but not deeply checked,
// because the server validates them and answers seed_invalid.

export type TestingPhase = "sqlite_primary" | "flat_primary";

// `unconfigured` is a flat-primary instance with no storage pointer and no database, as a fresh installation is
// before an administrator chooses the database location. The server refuses it for any other phase.
export type TestingStorage = "configured" | "unconfigured";

export type TestingInstanceSummary = {
  instanceId: string;
  label: string;
  phase: TestingPhase;
  generation: string;
  createdAt: string;
};

export type TestingState = {
  schemaVersion: 1;
  runId: string;
  instance: TestingInstanceSummary | null;
};

export type SpawnedTestAccount = {
  username: string;
  userId: string;
  roles: string[];
};

export type TestingEnvironment = {
  BNEST_TEST_INSTANCE_ID: string;
  BNEST_RUNTIME_ROOT: string;
  BNEST_STORAGE_CONFIG: string;
};

export type SpawnedInstance = {
  instanceId: string;
  label: string;
  phase: TestingPhase;
  generation: string;
  accounts: SpawnedTestAccount[];
  environment: TestingEnvironment;
};

export type SeedAccount = {
  username: string;
  password: string;
  roles: string[];
};

export type SeedMessage = {
  sender: string;
  body: string;
  idempotencyKey: string;
};

export type SeedPushSubscription = {
  owner: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

export type SeedRecord = {
  owner: string;
  kind:
    | "sifatAllahProgress"
    | "codexChatTranscript"
    | "themePreference"
    | "browserImportInterrupted";
  value: Record<string, unknown>;
};

export type TestingSeed = {
  accounts?: SeedAccount[];
  familyChat?: { messages: SeedMessage[] };
  pushSubscriptions?: SeedPushSubscription[];
  records?: SeedRecord[];
};

// `instanceId` is optional. When a caller chooses it, it must be 16 lowercase letters or digits, and the
// client checks that before sending. Without it the server generates the id.
export type SpawnRequest = {
  runId: string;
  label: string;
  instanceId?: string;
  phase?: TestingPhase;
  storage?: TestingStorage;
  seed?: TestingSeed;
};

export type SeedRequest = {
  seedKey: string;
  seed: TestingSeed;
};

export type SeedResult = {
  seedKey: string;
  applied: boolean;
};

export function parseState(value: unknown): TestingState | undefined {
  if (!isRecord(value)) return undefined;
  const schemaVersion = value["schemaVersion"];
  const runId = value["runId"];
  const instance = value["instance"];

  if (schemaVersion !== 1 || typeof runId !== "string") return undefined;
  if (instance === null) return { schemaVersion: 1, runId, instance: null };

  const summary = parseInstanceSummary(instance);
  return summary === undefined
    ? undefined
    : { schemaVersion: 1, runId, instance: summary };
}

export function parseSpawned(value: unknown): SpawnedInstance | undefined {
  if (!isRecord(value)) return undefined;
  const instanceId = value["instanceId"];
  const label = value["label"];
  const phase = value["phase"];
  const generation = value["generation"];
  const accounts = value["accounts"];
  const environment = value["environment"];

  if (
    typeof instanceId !== "string" ||
    typeof label !== "string" ||
    !isPhase(phase) ||
    typeof generation !== "string" ||
    !Array.isArray(accounts) ||
    !accounts.every((account) => isSpawnedAccount(account)) ||
    !isEnvironment(environment)
  ) {
    return undefined;
  }
  return { instanceId, label, phase, generation, accounts, environment };
}

export function parseSeedResult(value: unknown): SeedResult | undefined {
  if (!isRecord(value)) return undefined;
  const seedKey = value["seedKey"];
  const applied = value["applied"];
  if (typeof seedKey !== "string" || typeof applied !== "boolean") {
    return undefined;
  }
  return { seedKey, applied };
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseInstanceSummary(
  value: unknown,
): TestingInstanceSummary | undefined {
  if (!isRecord(value)) return undefined;
  const instanceId = value["instanceId"];
  const label = value["label"];
  const phase = value["phase"];
  const generation = value["generation"];
  const createdAt = value["createdAt"];

  if (
    typeof instanceId !== "string" ||
    typeof label !== "string" ||
    !isPhase(phase) ||
    typeof generation !== "string" ||
    typeof createdAt !== "string"
  ) {
    return undefined;
  }
  return { instanceId, label, phase, generation, createdAt };
}

function isSpawnedAccount(value: unknown): value is SpawnedTestAccount {
  if (!isRecord(value)) return false;
  const roles = value["roles"];
  return (
    typeof value["username"] === "string" &&
    typeof value["userId"] === "string" &&
    Array.isArray(roles) &&
    roles.every((role) => typeof role === "string")
  );
}

function isEnvironment(value: unknown): value is TestingEnvironment {
  return (
    isRecord(value) &&
    typeof value["BNEST_TEST_INSTANCE_ID"] === "string" &&
    typeof value["BNEST_RUNTIME_ROOT"] === "string" &&
    typeof value["BNEST_STORAGE_CONFIG"] === "string"
  );
}

function isPhase(value: unknown): value is TestingPhase {
  return value === "sqlite_primary" || value === "flat_primary";
}
