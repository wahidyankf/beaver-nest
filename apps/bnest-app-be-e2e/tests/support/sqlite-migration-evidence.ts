import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { runStorageCommand, type StorageScenario } from "./sqlite-storage";

// Evidence the CLI storage scenarios read from their own isolated database: the schema it
// holds, the committed migration set it was built from, and one source's ledger and record
// rows, plus the trigger that interrupts a record write the way a killed migration would.

const appDirectory = path.join(process.cwd(), "apps/bnest-app");

// Runs `body` in the scenario's application and returns the JSON it printed after `marker`.
function storageEvidence<T>(scenario: StorageScenario, body: string): T {
  const marker = "BNEST_E2E_STORAGE_EVIDENCE=";
  const expression = `
    alias BnestApp.Storage.Adapters.SqliteCoordinator
    alias BnestApp.SqliteRepo
    :ok = SqliteCoordinator.ensure_started!()
    evidence = (${body})
    IO.puts("${marker}" <> Jason.encode!(evidence))
  `;
  const result = runStorageCommand(scenario, "run", ["-e", expression]);
  if (result.status !== 0) {
    throw new Error(`storage evidence read failed: ${result.stderr}`);
  }

  const encoded = result.stdout
    .split("\n")
    .find((line) => line.startsWith(marker))
    ?.slice(marker.length);
  if (!encoded) throw new Error("storage evidence marker was absent");
  return JSON.parse(encoded) as T;
}

export type SchemaEvidence = {
  objects: [string, string, string | null][];
  versions: number[];
  runs: [string, string][];
};

// The schema objects, applied migration versions and migration runs the scenario's
// database holds.
export function inspectSchema(scenario: StorageScenario): SchemaEvidence {
  return storageEvidence<SchemaEvidence>(
    scenario,
    `%{
      objects: SqliteRepo.query!("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").rows,
      versions: SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version").rows |> List.flatten(),
      runs: SqliteRepo.query!("SELECT migration_id, ddl_checksum FROM bnest_migration_runs").rows
    }`,
  );
}

export type DeclaredMigrationSet = {
  checksum: string;
  versions: number[];
  indexes: string[];
};

// The committed migration files themselves: their joined digest, their versions, and the
// indexes they create.
export function declaredMigrationSet(): DeclaredMigrationSet {
  const directory = path.join(appDirectory, "priv/sqlite_repo/migrations");
  const files = readdirSync(directory)
    .filter((name) => name.endsWith(".exs"))
    .toSorted();
  const sources = files.map((name) =>
    readFileSync(path.join(directory, name), "utf8"),
  );
  return {
    checksum: createHash("sha256").update(sources.join("")).digest("hex"),
    versions: files.map((name) => Number(name.split("_")[0])),
    indexes: sources
      .flatMap((source) =>
        [...source.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+(\w+)/gu)].map(
          (match) => match[1] ?? "",
        ),
      )
      .toSorted(),
  };
}

// Applies the schema to the database the scenario's pointer resolves and makes every
// insert of the `recordKey` record fail, as a process killed before that write would.
export function interruptRecordWrite(
  scenario: StorageScenario,
  recordKey: string,
): void {
  storageEvidence<string>(
    scenario,
    `BnestApp.Storage.adapter(:database_lifecycle).migrate_schema!()
     SqliteRepo.query!("CREATE TRIGGER e2e_interrupt_record_write BEFORE INSERT ON bnest_records WHEN NEW.record_key = '${recordKey}' BEGIN SELECT RAISE(ABORT, 'interrupted migration'); END")
     "interrupting"`,
  );
}

export function resumeRecordWrites(scenario: StorageScenario): void {
  storageEvidence<string>(
    scenario,
    `SqliteRepo.query!("DROP TRIGGER e2e_interrupt_record_write")
     "resumed"`,
  );
}

export type MigrationRows = { item: unknown[][]; record: unknown[][] };

// The ledger item and migrated record rows, every column, for one theme source.
export function themeMigrationRows(
  scenario: StorageScenario,
  ownerId: string,
): MigrationRows {
  return storageEvidence<MigrationRows>(
    scenario,
    `%{
      item: SqliteRepo.query!("SELECT * FROM bnest_migration_items WHERE source_relative_path = ?", ["users/${ownerId}/preferences/theme.json"]).rows,
      record: SqliteRepo.query!("SELECT * FROM bnest_records WHERE record_type = 'theme-preference' AND record_key = ?", ["${ownerId}"]).rows
    }`,
  );
}
