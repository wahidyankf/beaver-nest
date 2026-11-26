defmodule BnestApp.SchedulerRestartTest do
  # A saved daily schedule survives a process restart: the schedule lives in the SQLite
  # run database, so stopping the coordinator and starting it again on the same file —
  # what a restart does to every connection the server holds — must show the same time,
  # enabled flag, and next run. The schedules page reads this same record, so the page
  # shows the administrator's saved time after Bnest restarts.
  use ExUnit.Case, async: false

  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.TestRuntimeRoot

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    runtime = TestRuntimeRoot.create!("scheduler-restart")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    :ok = SqliteCoordinator.ensure_started!(database_path)
    :ok = PersistentSchedules.apply_and_verify!(@now)

    on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    {:ok, database_path: database_path}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: A saved daily schedule survives a restart
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A backup time the administrator chose survives a restart
  test "a saved daily backup time is still saved after the coordinator restarts", %{
    database_path: database_path
  } do
    key = "prod-sqlite-backup-daily"

    # The one-time convergence ran before the administrator's edit.
    assert {:ok, %{daily_at_utc: "18:00"}} = Scheduler.converge_backup_time!(key, "18:00")

    current = Scheduler.get_schedule(key)

    assert {:ok, saved} =
             Scheduler.update_daily(
               key,
               %{
                 "daily_time_wib" => "02:00",
                 "enabled" => "true",
                 "revision" => Integer.to_string(current.revision)
               },
               @now
             )

    assert saved.daily_at_utc == "19:00"
    assert saved.enabled == true

    :ok = SqliteCoordinator.stop()
    :ok = SqliteCoordinator.ensure_started!(database_path)

    reloaded = Scheduler.get_schedule(key)
    assert reloaded.daily_at_utc == saved.daily_at_utc
    assert reloaded.enabled == saved.enabled
    assert reloaded.revision == saved.revision
    assert reloaded.next_run_at == saved.next_run_at
  end
end
