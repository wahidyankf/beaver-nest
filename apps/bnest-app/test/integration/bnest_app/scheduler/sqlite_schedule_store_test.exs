defmodule BnestApp.Scheduler.SqliteScheduleStoreTest do
  # Not async: the SQLite repository is one named process, repointed for each test.
  use BnestApp.Test.Contracts.ScheduleStoreContract, async: false

  alias BnestApp.Scheduler.Adapters.SqliteScheduleStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestRuntimeRoot

  # Each test gets its own database under an isolated test-run root, migrated to the
  # current schema with no schedule seeded: the release seeds come from
  # `PersistentSchedules` and Family Chat, which the contract replaces with its own.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-schedule-store")
    :ok = SqliteCoordinator.ensure_started!(Path.join(runtime.sqlite_path, "bnest.sqlite3"))

    on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    migrations = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
    _versions = Ecto.Migrator.run(SqliteRepo, migrations, :up, all: true, log: false)
    SqliteScheduleStore.new()
  end

  defp put_schedule(_store, schedule), do: :ok = Schedules.put_schedule!(schedule)
end
