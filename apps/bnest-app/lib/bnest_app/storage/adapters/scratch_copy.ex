defmodule BnestApp.Storage.Adapters.ScratchCopy do
  @moduledoc """
  A private scratch copy of the authoritative SQLite database, so a read-only tool can read
  what the service has written without opening the live file: opening a database creates or
  touches the `-shm` and `-wal` sidecars the service owns.

  `open/1` copies the database and its write-ahead log, which SQLite finds by appending
  `-wal` to the database file name, into a fresh private directory, each keeping its name.
  It reads the two files as plain bytes and opens neither. It then writes a storage pointer
  beside the copy and makes `BNEST_STORAGE_CONFIG`, which the pointer lookup honours before
  every other setting, name it, so that everything that resolves the database resolves the
  copy and nothing can start the repository on the live file. `close/1` puts the pointer
  setting back and removes the directory.
  """

  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Domain.FlatMigration

  @pointer_variable "BNEST_STORAGE_CONFIG"

  @spec open(String.t()) :: {:ok, map()} | {:error, :copy_failed}
  def open(source) do
    directory = Path.join(System.tmp_dir!(), "bnest-scratch-" <> random_id())
    copy = %{database_path: Path.join(directory, Path.basename(source))}
    handle = Map.merge(copy, %{directory: directory, previous_pointer: pointer_setting()})

    try do
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)
      copy_file!(source, copy.database_path)
      copy_log(source <> "-wal", copy.database_path <> "-wal")
      point_at!(handle)
      {:ok, handle}
    rescue
      _error in [File.Error, File.CopyError] ->
        :ok = close(handle)
        {:error, :copy_failed}
    end
  end

  @spec close(map()) :: :ok
  def close(%{directory: directory, previous_pointer: previous}) do
    put_pointer_setting(previous)
    File.rm_rf!(directory)
    :ok
  end

  # The log is absent when the service checkpointed it away, which a copy of the database
  # alone then reflects.
  defp copy_log(source, copy) do
    case File.cp(source, copy) do
      :ok ->
        File.chmod!(copy, 0o600)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise File.CopyError, source: source, destination: copy, reason: reason, action: "copy"
    end
  end

  defp copy_file!(source, copy) do
    File.cp!(source, copy)
    File.chmod!(copy, 0o600)
  end

  defp point_at!(%{directory: directory, database_path: database_path}) do
    System.put_env(@pointer_variable, Path.join(directory, "storage.json"))

    FileConfigStore.write!(%{
      "schemaVersion" => 1,
      "databaseDirectory" => directory,
      "databaseFilename" => Path.basename(database_path),
      "phase" => "sqlite_primary",
      "migrationId" => FlatMigration.migration_id()
    })
  end

  defp pointer_setting, do: System.get_env(@pointer_variable)

  defp put_pointer_setting(nil), do: System.delete_env(@pointer_variable)
  defp put_pointer_setting(path), do: System.put_env(@pointer_variable, path)

  defp random_id, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
