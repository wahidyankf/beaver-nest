defmodule BnestApp.PersistentSchedulesMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.SqliteRepo
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("persistent-schedules-migration")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    :ok = StorageCoordinator.ensure_started!(database_path)

    on_exit(fn ->
      StorageCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    {:ok, database_path: database_path, runtime: runtime}
  end

  test "starts database dependencies and owns the repo in a release eval", %{
    database_path: database_path,
    runtime: runtime
  } do
    storage_config_path = Path.join(runtime.path, "release-storage.json")

    File.write!(
      storage_config_path,
      JSON.encode!(%{
        "schemaVersion" => 1,
        "databaseDirectory" => runtime.sqlite_path,
        "databaseFilename" => "bnest.sqlite3",
        "phase" => "sqlite_primary",
        "migrationId" => "flat-files-v1-to-sqlite-v1"
      })
    )

    :ok = StorageCoordinator.stop()

    expression = """
    :ok = BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
    if Process.whereis(BnestApp.SqliteRepo), do: raise("standalone migration retained repo")
    """

    {_output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", "-e", expression],
        cd: Path.expand("../../..", __DIR__),
        env: [
          {"MIX_ENV", "test"},
          {"BNEST_TEST_LAYER", "unit"},
          {"BNEST_STORAGE_CONFIG", storage_config_path}
        ],
        stderr_to_stdout: true
      )

    assert status == 0
    :ok = StorageCoordinator.ensure_started!(database_path)

    assert %{rows: [[20_260_830_000_000]]} =
             SqliteRepo.query!(
               "SELECT version FROM schema_migrations WHERE version = ?",
               [20_260_830_000_000]
             )
  end

  test "expands and verifies the schedule schema idempotently" do
    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
    before = schema()
    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
    assert schema() == before

    assert %{rows: [["prod-sqlite-backup-daily", "19:00", "never", 1]]} =
             SqliteRepo.query!(
               "SELECT schedule_key, daily_at_utc, expiration_kind, revision FROM bnest_schedules"
             )
  end

  test "refuses destructive reversal while schedule records exist" do
    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
    assert_raise RuntimeError, ~r/refuses to reverse/, &PersistentSchedules.rollback!/0
  end

  test "repeat reconciliation rejects an incompatible existing seed" do
    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])

    BnestApp.SqliteRepo.query!(
      "UPDATE bnest_schedules SET handler_key = 'fixture' WHERE schedule_key = 'prod-sqlite-backup-daily'"
    )

    assert_raise RuntimeError, ~r/seed policy is incompatible/, fn ->
      PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
    end
  end

  test "repeat reconciliation accepts a valid configured schedule revision" do
    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])

    BnestApp.SqliteRepo.query!(
      "UPDATE bnest_schedules SET revision = 2 WHERE schedule_key = 'prod-sqlite-backup-daily'"
    )

    assert :ok = PersistentSchedules.apply_and_verify!(~U[2026-08-30 10:00:00Z])
  end

  defp schema do
    SqliteRepo.query!(
      "SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'bnest_schedule%' ORDER BY name"
    ).rows
  end
end
