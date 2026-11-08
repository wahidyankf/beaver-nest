defmodule BnestApp.SqliteRepoTest do
  # The main database path is read from the pool's own connection (`PRAGMA database_list`). A connection that also
  # has a temp schema lists that too, and the main file must still be found. Both statements run on one checked-out
  # connection, so the temp schema is the one the lookup sees.
  use BnestApp.FreshDatabaseCase, async: false

  alias BnestApp.SqliteRepo
  alias BnestApp.TestInstance

  test "reads the main database path when the connection also lists a temp database" do
    SqliteRepo.checkout(fn ->
      SqliteRepo.query!("CREATE TEMP TABLE scratch_rows (value INTEGER)")

      listed = SqliteRepo.query!("PRAGMA database_list").rows
      assert Enum.any?(listed, &match?([_seq, "temp", _file], &1))

      assert SqliteRepo.main_database_path() == TestInstance.state().paths.db_file
    end)
  end

  # The integrity check is the statement that leaves the temp schema on the connection in production code, so it is
  # the real trigger of the lookup failing.
  test "reads the main database path after PRAGMA quick_check on the same connection" do
    SqliteRepo.checkout(fn ->
      assert %{rows: [["ok"]]} = SqliteRepo.query!("PRAGMA quick_check")

      listed = SqliteRepo.query!("PRAGMA database_list").rows
      assert Enum.any?(listed, &match?([_seq, "temp", _file], &1))

      assert SqliteRepo.main_database_path() == TestInstance.state().paths.db_file
    end)
  end
end
