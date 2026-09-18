defmodule BnestApp.Backup.Capacity do
  @moduledoc """
  Measured backup-destination capacity guard (Phase 5). Replaces the earlier
  `source_bytes * 2 + 256MiB` naive doubling: a `VACUUM INTO` output is
  bounded by the source's live logical size (`page_count * page_size`) plus
  whatever is still resident in the WAL file (pages not yet checkpointed
  into the main file, which a consistent read still has to account for) --
  never twice the whole source file, which over-rejects destinations that
  are in fact large enough.
  """

  @reserve_bytes 256 * 1024 * 1024

  @spec sufficient?(String.t()) :: boolean()
  def sufficient?(directory) do
    available_bytes(directory) >= required_bytes()
  rescue
    # A capacity PREFLIGHT that cannot even measure (destination or source
    # unreadable) must fail closed as "insufficient", not raise past the
    # caller's retryable-failure contract.
    _error -> false
  end

  @doc false
  @spec required_bytes() :: non_neg_integer()
  def required_bytes do
    source = BnestApp.SqliteRepo.main_database_path()
    {page_count, page_size} = page_geometry(source)
    page_count * page_size + wal_bytes(source) + @reserve_bytes
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
