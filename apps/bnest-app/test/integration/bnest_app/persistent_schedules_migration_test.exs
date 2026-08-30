defmodule BnestApp.PersistentSchedulesMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.SqliteRepo
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("persistent-schedules-migration")
    :ok = StorageCoordinator.ensure_started!(Path.join(runtime.sqlite_path, "bnest.sqlite3"))

    on_exit(fn ->
      StorageCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    :ok
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

  defp schema do
    SqliteRepo.query!(
      "SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'bnest_schedule%' ORDER BY name"
    ).rows
  end
end
