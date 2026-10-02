defmodule BnestApp.Backup.Adapters.DfCapacityProbe do
  @moduledoc """
  `BnestApp.Backup.Ports.CapacityProbe` over `df` and the live SQLite database: the
  destination's free bytes from `df -Pk`, and the source's `page_count`, `page_size` and
  WAL file size, read on a read-only connection of its own.
  """

  @behaviour BnestApp.Backup.Ports.CapacityProbe

  @impl true
  def new, do: %{adapter: __MODULE__}

  # A capacity preflight that cannot even measure (destination or source unreadable) must
  # fail closed, never raise past the caller's retryable-failure contract.
  @impl true
  def measure(_probe, directory) do
    available_bytes = available_bytes(directory)
    source = BnestApp.SqliteRepo.main_database_path()
    {page_count, page_size} = page_geometry(source)

    {:ok,
     %{
       available_bytes: available_bytes,
       page_count: page_count,
       page_size: page_size,
       wal_bytes: wal_bytes(source)
     }}
  rescue
    _error -> {:error, :unmeasurable}
  end

  defp wal_bytes(source) do
    case File.stat(source <> "-wal") do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _enoent_or_unreadable} -> 0
    end
  end

  defp page_geometry(source) do
    {:ok, connection} = Exqlite.Sqlite3.open(source, mode: :readonly)

    try do
      {pragma_integer(connection, "page_count"), pragma_integer(connection, "page_size")}
    after
      :ok = Exqlite.Sqlite3.close(connection)
    end
  end

  defp pragma_integer(connection, pragma) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(connection, "PRAGMA " <> pragma)

    try do
      {:row, [value]} = Exqlite.Sqlite3.step(connection, statement)
      value
    after
      :ok = Exqlite.Sqlite3.release(connection, statement)
    end
  end

  defp available_bytes(directory) do
    {output, 0} = System.cmd("df", ["-Pk", directory], stderr_to_stdout: true)

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.at(3)
    |> String.to_integer()
    |> Kernel.*(1024)
  end
end
