defmodule BnestApp.Test.DriftingLedgerCopy do
  @moduledoc """
  Test-only Storage `:maintenance` adapter for a ledger that keeps changing while it is
  copied. It opens each copy through the real scratch-copy adapter, then deletes as many
  verified backup runs from the copy as copies were opened before it, so no two copies hold
  the same ledger, as when a busy service writes between two copies.

  It implements only the two callbacks Storage calls to read a copy and declares no
  `Maintenance` behaviour on purpose. `install!/0` makes it the configured adapter for the
  rest of the calling OS process, which is how a standalone Mix subprocess uses it.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.ScratchCopy
  alias Exqlite.Sqlite3

  @opened :bnest_drifting_ledger_copies

  @spec install!() :: :ok
  def install! do
    settings = Application.fetch_env!(:bnest_app, Storage)
    Application.put_env(:bnest_app, Storage, Keyword.put(settings, :maintenance, __MODULE__))
  end

  @spec open_database_copy(String.t()) :: {:ok, map()} | {:error, :copy_failed}
  def open_database_copy(source) do
    with {:ok, copy} <- ScratchCopy.open(source) do
      opened = Process.get(@opened, 0)
      Process.put(@opened, opened + 1)
      remove_verified_runs!(copy.database_path, opened)
      {:ok, copy}
    end
  end

  @spec close_database_copy(map()) :: :ok
  def close_database_copy(copy), do: ScratchCopy.close(copy)

  defp remove_verified_runs!(database_path, count) do
    {:ok, connection} = Sqlite3.open(database_path)

    try do
      :ok =
        Sqlite3.execute(connection, """
        DELETE FROM bnest_schedule_runs WHERE run_id IN (
          SELECT run_id FROM bnest_schedule_runs WHERE state = 'verified'
          ORDER BY finished_at LIMIT #{count}
        )
        """)
    after
      :ok = Sqlite3.close(connection)
    end
  end
end
