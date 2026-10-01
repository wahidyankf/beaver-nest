defmodule BnestApp.Storage.SqliteRecordBackendTest do
  # Not async: the SQLite repository is one named process.
  use BnestApp.Test.Contracts.RecordBackendContract, async: false

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Adapters.SqliteRecordBackend
  alias BnestApp.TestRuntimeRoot

  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-record-backend")
    :ok = SqliteCoordinator.ensure_started!(Path.join(runtime.sqlite_path, "bnest.sqlite3"))
    :ok = SqliteCoordinator.migrate_schema!()

    on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    SqliteRecordBackend.new(SqliteRepo)
  end
end
