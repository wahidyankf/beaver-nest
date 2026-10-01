import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, renameSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { TestInfo } from "@playwright/test";
import { chatPayload, learningPayload } from "./centralized-data";
import { runStorageCommand, type StorageScenario } from "./sqlite-storage";
import {
  cleanupTestRuntime,
  createTestRuntime,
  type TestRuntime,
} from "./test-runtime.mts";

// The application runs over the marked runtime root, while the flat source
// being migrated and retired is `flat-source` inside the paired marked SQLite
// root. Retirement removes every verified file under the root it is given, so
// that root never holds a run marker, the database, or the application's own
// flat root.
export type IdentityStorageScenario = StorageScenario & {
  pairedRuntime: TestRuntime;
};

export type SyntheticIdentity = { username: string; password: string };

type EvalResult = { status: number; stdout: string; stderr: string };
type StoredRecord = Record<string, unknown>;

export type JourneyEvidence = {
  userId: string;
  chat: StoredRecord;
  learning: StoredRecord;
  theme: StoredRecord;
};

export type FutureWriteEvidence = {
  routed: { session: StoredRecord; theme: StoredRecord };
  sqlite: { session: StoredRecord; theme: StoredRecord };
  flatBeforeRollback: { session: string; theme: string };
  rollback: { session: StoredRecord; theme: StoredRecord };
};

export type RestartEvidence = {
  setupStatus: string;
  userId: string;
  chat: StoredRecord;
  learning: StoredRecord;
  theme: string;
  afterLogout: string;
};

export type RetirementEvidence = {
  retired: StoredRecord;
  presentBefore: string[];
  presentAfter: string[];
};

const repositoryRoot = process.cwd();
const appDirectory = path.join(repositoryRoot, "apps/bnest-app");
const evidenceMarker = "BNEST_E2E_IDENTITY_EVIDENCE=";
const flatSourceName = "flat-source";
const identitySources = [
  "system/bootstrap.json",
  "system/accounts",
  "system/usernames",
];

export function isolatedIdentityStorageScenario(
  testInfo: TestInfo,
  label: string,
): IdentityStorageScenario {
  const digest = createHash("sha256")
    .update(
      `${testInfo.project.name}:${testInfo.file}:${testInfo.title}:${label}`,
    )
    .digest("hex")
    .slice(0, 12);
  const runtime = createTestRuntime(`sqlite-identity-${digest}`);
  const pointerDirectory = path.join(runtime.path, "storage-config");
  mkdirSync(pointerDirectory, { recursive: true });
  const flatRoot = path.join(runtime.sqlitePath, flatSourceName);
  mkdirSync(flatRoot);

  return {
    flatRoot,
    pointerPath: path.join(pointerDirectory, "storage.json"),
    homeDirectory: os.homedir(),
    runId: runtime.runId,
    pairedRuntime: runtime,
  };
}

export function cleanupIdentityStorageScenario(
  scenario: IdentityStorageScenario,
): void {
  cleanupTestRuntime(scenario.pairedRuntime);
}

// The production bootstrap and record writes run against the application's
// marked flat root; the files they produce then move, unchanged and at the
// same relative paths, into the scenario's flat source.
export function seedFlatIdentityJourney(
  scenario: IdentityStorageScenario,
  identity: SyntheticIdentity,
): JourneyEvidence {
  const evidence = runStorageEvidence<JourneyEvidence>(
    scenario,
    `
    alias BnestApp.Storage.Domain.Normalizer
    alias BnestApp.Storage.Records
    {:ok, [%{"userId" => user_id}]} = BnestApp.Identity.bootstrap([%{"username" => ${elixirString(identity.username)}, "password" => ${elixirString(identity.password)}, "roles" => ["admin"]}])
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    sources = [chat: {"sessionStorage", "bnest.chat.v1", ${elixirString(chatPayload)}}, learning: {"localStorage", "bnest.sifat-allah.v1", ${elixirString(learningPayload)}}]
    records = Map.new(sources, fn {label, {area, key, payload}} ->
      {:ok, type, candidate} = Normalizer.normalize(area, key, payload, "import-journey-fixture", now, BnestApp.Storage.record_kinds())
      {:ok, record} = Records.write(type, user_id, nil, Map.put(candidate, "ownerId", user_id))
      {label, record}
    end)
    :ok = BnestApp.Preferences.put_theme(user_id, "light", DateTime.utc_now())
    {:ok, theme} = Records.read(:theme, user_id)
    IO.puts(${elixirString(evidenceMarker)} <> Jason.encode!(Map.merge(records, %{userId: user_id, theme: theme})))
    `,
  );

  const sources = [...identitySources, path.join("users", evidence.userId)];
  for (const relative of sources) {
    const target = path.join(scenario.flatRoot, relative);
    mkdirSync(path.dirname(target), { recursive: true });
    renameSync(path.join(scenario.pairedRuntime.path, relative), target);
  }

  return evidence;
}

// After the switch, a login writes a session and the Preferences facade
// writes a theme, both through the routed repository. Each is read back from
// the routed repository and from SQLite directly, looked up in the flat root
// a rollback would fall back to, then handed to that flat reader.
export function writeAfterSwitch(
  scenario: IdentityStorageScenario,
  identity: SyntheticIdentity,
  userId: string,
  theme: string,
): FutureWriteEvidence {
  return runStorageEvidence<FutureWriteEvidence>(
    scenario,
    `
    alias BnestApp.Storage.Adapters.{FileRecordBackend, SqliteCoordinator, SqliteRecordBackend}
    alias BnestApp.Storage.Records
    user_id = ${elixirString(userId)}
    {:ok, token} = BnestApp.Identity.login(${elixirString(identity.username)}, ${elixirString(identity.password)})
    :ok = BnestApp.Preferences.put_theme(user_id, ${elixirString(theme)}, DateTime.utc_now())
    :ok = SqliteCoordinator.ensure_started!()
    sqlite = SqliteRecordBackend.new(BnestApp.SqliteRepo)
    reader = FileRecordBackend.new!(${elixirString(scenario.pairedRuntime.path)})
    keys = [session: BnestApp.Identity.session_digest(token), theme: user_id]
    outcome = fn
      {:ok, _record} -> "present"
      {:error, reason} -> Atom.to_string(reason)
    end
    routed = Map.new(keys, fn {type, key} -> {:ok, record} = Records.read(type, key); {type, record} end)
    stored = Map.new(keys, fn {type, key} -> {:ok, record} = SqliteRecordBackend.read(sqlite, type, key); {type, record} end)
    flat = Map.new(keys, fn {type, key} -> {type, outcome.(FileRecordBackend.read(reader, type, key))} end)
    rollback = Map.new(keys, fn {type, key} ->
      {:ok, _accepted} = FileRecordBackend.put_new(reader, type, key, routed[type])
      {:ok, record} = FileRecordBackend.read(reader, type, key)
      {type, record}
    end)
    :ok = BnestApp.Identity.logout(token)
    IO.puts(${elixirString(evidenceMarker)} <> Jason.encode!(%{routed: routed, sqlite: stored, flatBeforeRollback: flat, rollback: rollback}))
    `,
  );
}

// Production retirement (`BnestApp.Storage.retire/3`, which
// `mix bnest.storage.retire` calls) for the pointer's own database generation,
// given only the scenario's flat source and run the way that task runs: the
// configuration loaded, the application itself not started. The task cannot
// be used here because it insists on a `--generation` value, and a pointer
// activated in place, never relocated, records none.
export function retireFlatIdentitySources(
  scenario: IdentityStorageScenario,
): RetirementEvidence {
  const flatRoot = scenario.flatRoot;
  if (
    flatRoot !== path.join(scenario.pairedRuntime.sqlitePath, flatSourceName) ||
    lstatSync(flatRoot).isSymbolicLink()
  ) {
    throw new Error("Identity retirement requires its scoped flat source");
  }

  const present = () =>
    identitySources.filter((relative) =>
      existsSync(path.join(flatRoot, relative)),
    );
  const presentBefore = present();
  const evidence = parseEvidence<{ retired: StoredRecord }>(
    runStorageCommand(scenario, "run", [
      "--no-start",
      "-e",
      `
      {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
      {:ok, _apps} = Application.ensure_all_started(:exqlite)
      retired = case BnestApp.Storage.retire(${elixirString(flatRoot)}, BnestApp.Storage.database_generation(), false) do
        {:ok, config} -> config
        {:error, reason} -> %{"error" => Atom.to_string(reason)}
      end
      IO.puts(${elixirString(evidenceMarker)} <> Jason.encode!(%{retired: retired}))
      `,
    ]),
  );

  return { retired: evidence.retired, presentBefore, presentAfter: present() };
}

// A fresh application process over the switched storage.
export function restartJourney(
  scenario: IdentityStorageScenario,
  identity: SyntheticIdentity,
): RestartEvidence {
  return runStorageEvidence<RestartEvidence>(
    scenario,
    `
    alias BnestApp.Storage.Records
    setup_status = inspect(BnestApp.Identity.setup_status())
    {:ok, token} = BnestApp.Identity.login(${elixirString(identity.username)}, ${elixirString(identity.password)})
    {:ok, %{"userId" => user_id}} = BnestApp.Identity.current_user(token)
    {:ok, chat} = Records.read(:chat, user_id)
    {:ok, learning} = Records.read(:sifat_allah, user_id)
    theme = BnestApp.Preferences.theme(user_id)
    :ok = BnestApp.Identity.logout(token)
    after_logout = inspect(BnestApp.Identity.current_user(token))
    IO.puts(${elixirString(evidenceMarker)} <> Jason.encode!(%{setupStatus: setup_status, userId: user_id, chat: chat, learning: learning, theme: theme, afterLogout: after_logout}))
    `,
  );
}

export function runStorageEval(
  scenario: IdentityStorageScenario,
  expression: string,
): EvalResult {
  const realHome = os.homedir();
  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: appDirectory,
    env: {
      ...process.env,
      MIX_ENV: "test",
      HOME: realHome,
      BNEST_IDENTITY_CUTOVER: "true",
      BNEST_RUNTIME_ROOT: scenario.pairedRuntime.path,
      BNEST_STORAGE_CONFIG: scenario.pointerPath,
      BNEST_TEST_LAYER: "integration",
      BNEST_TEST_RUN_ID: scenario.runId,
      ASDF_DIR: process.env["ASDF_DIR"] ?? path.join(realHome, ".asdf"),
      ASDF_DATA_DIR:
        process.env["ASDF_DATA_DIR"] ?? path.join(realHome, ".asdf"),
    },
    encoding: "utf8",
  });

  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

function runStorageEvidence<T>(
  scenario: IdentityStorageScenario,
  expression: string,
): T {
  return parseEvidence<T>(runStorageEval(scenario, expression));
}

function parseEvidence<T>(result: EvalResult): T {
  if (result.status !== 0) {
    throw new Error(`storage evaluation failed: ${result.stderr}`);
  }

  const encoded = result.stdout
    .split("\n")
    .find((line) => line.startsWith(evidenceMarker))
    ?.slice(evidenceMarker.length);
  if (!encoded) throw new Error("storage evaluation printed no evidence");

  return JSON.parse(encoded) as T;
}

// A JSON string literal is also a valid Elixir string literal for the
// printable, `#`-free values used here; anything else is refused.
function elixirString(value: string): string {
  if (!/^[ -~]*$/u.test(value) || value.includes("#")) {
    throw new Error(
      "Refusing to embed an unsafe value in an Elixir expression",
    );
  }
  return JSON.stringify(value);
}
