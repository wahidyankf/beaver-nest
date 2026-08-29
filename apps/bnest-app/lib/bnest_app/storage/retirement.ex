defmodule BnestApp.Storage.Retirement do
  @moduledoc false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias BnestApp.Storage.Lock
  alias BnestApp.Storage.Migration

  @placeholder ".gitkeep"

  @spec run(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def run(flat_root, expected_generation) do
    Lock.with_exclusive(fn -> retire(flat_root, expected_generation) end)
  end

  @spec verify(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def verify(flat_root, expected_generation) do
    Lock.with_exclusive(fn ->
      with {:ok, %{files: files}} <- verification(flat_root, expected_generation) do
        {:ok, length(files)}
      end
    end)
  end

  defp retire(flat_root, expected_generation) do
    with {:ok, %{config: config, directories: directories, files: files}} <-
           verification(flat_root, expected_generation) do
      Enum.each(files, &File.rm!/1)
      prune_empty_directories(directories)
      retire_legacy_database(config)
      {:ok, Config.mark_legacy_retired!()}
    end
  end

  defp verification(flat_root, expected_generation) do
    with {:ok, config} <- Config.read(),
         true <- config["phase"] == "sqlite_primary" || {:error, :not_sqlite_primary},
         true <-
           config["databaseGeneration"] == expected_generation ||
             {:error, :generation_mismatch},
         :ok <- verify_authoritative_database(),
         {:ok, files, directories} <- verified_flat_files(flat_root) do
      {:ok, %{config: config, directories: directories, files: files}}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :verification_failed}
    end
  end

  defp verify_authoritative_database do
    StorageCoordinator.ensure_started!()

    with %{rows: [["ok"]]} <- SqliteRepo.query!("PRAGMA quick_check"),
         true <-
           SqliteRepo.query!(
             "SELECT state FROM bnest_migration_runs WHERE migration_id = ?",
             [Migration.migration_id()]
           ).rows == [["verified"]] do
      :ok
    else
      _failed -> {:error, :database_not_verified}
    end
  end

  defp verified_flat_files(flat_root) do
    evidence =
      SqliteRepo.query!(
        "SELECT source_relative_path, source_sha256 FROM bnest_migration_items WHERE migration_id = ? AND outcome = 'accepted'",
        [Migration.migration_id()]
      ).rows
      |> Map.new(fn [relative, checksum] -> {relative, checksum} end)

    with {:ok, files, directories} <- runtime_files(flat_root) do
      if Enum.all?(files, &verified_file?(&1, flat_root, evidence)) do
        {:ok, files, directories}
      else
        {:error, :unverified_flat_source}
      end
    end
  end

  defp verified_file?(path, flat_root, evidence) do
    relative = Path.relative_to(path, flat_root)

    case evidence[relative] do
      nil -> false
      checksum -> sha256(File.read!(path)) == checksum
    end
  end

  defp runtime_files(root) do
    case File.lstat(root) do
      {:ok, %File.Stat{type: :directory}} ->
        with {:ok, files, directories} <- walk(root) do
          {:ok, files, List.delete(directories, root)}
        end

      {:error, :enoent} ->
        {:ok, [], []}

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :unsafe_symlink}

      {:ok, _stat} ->
        {:error, :unsafe_flat_root}

      {:error, _reason} ->
        {:error, :unreadable_flat_root}
    end
  end

  defp walk(directory) do
    directory
    |> File.ls!()
    |> Enum.reduce_while({:ok, [], [directory]}, fn entry, {:ok, files, directories} ->
      walk_entry(Path.join(directory, entry), files, directories)
    end)
  end

  defp walk_entry(path, files, directories) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> walk_directory(path, files, directories)
      {:ok, %File.Stat{type: :regular}} -> walk_file(path, files, directories)
      {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :unsafe_symlink}}
      {:ok, _stat} -> {:halt, {:error, :unsafe_flat_entry}}
      {:error, _reason} -> {:halt, {:error, :unreadable_flat_root}}
    end
  end

  defp walk_directory(path, files, directories) do
    case walk(path) do
      {:ok, child_files, child_directories} ->
        {:cont, {:ok, child_files ++ files, child_directories ++ directories}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp walk_file(path, files, directories) do
    if Path.basename(path) == @placeholder do
      {:cont, {:ok, files, directories}}
    else
      {:cont, {:ok, [path | files], directories}}
    end
  end

  defp prune_empty_directories(directories) do
    directories
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.each(fn directory ->
      if File.ls!(directory) == [], do: File.rmdir!(directory)
    end)
  end

  defp retire_legacy_database(%{"legacyDatabaseDirectory" => directory} = config) do
    filename = config["databaseFilename"]
    database = Path.join(directory, filename)

    Enum.each([database, database <> "-wal", database <> "-shm"], fn path ->
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> raise File.Error, reason: reason, action: "remove", path: path
      end
    end)
  end

  defp retire_legacy_database(_config), do: :ok

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
