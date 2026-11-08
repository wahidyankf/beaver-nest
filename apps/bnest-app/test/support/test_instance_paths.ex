defmodule BnestApp.TestInstance.Paths do
  @moduledoc false

  # Pure derivation of one test instance's paths from the two marked run roots and two identifiers.
  # Nothing here touches the filesystem: callers validate the roots and markers before they act.
  # `\A` and `\z` anchor the patterns, because `$` would also accept a trailing newline.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @instance_id_pattern ~r/\A[a-z0-9]{16}\z/
  @run_id_pattern ~r/\A[a-z0-9][a-z0-9_-]{0,127}\z/
  @marker_name ".bnest-test-instance.json"
  @database_file "bnest.sqlite3"

  @type t :: %{
          run_id: String.t(),
          instance_id: String.t(),
          short_id: String.t(),
          generation: String.t(),
          flat_run_root: String.t(),
          sqlite_run_root: String.t(),
          flat_instance_root: String.t(),
          sqlite_instance_root: String.t(),
          flat_marker_path: String.t(),
          sqlite_marker_path: String.t(),
          db_directory: String.t(),
          db_file: String.t(),
          backup_repository_directory: String.t(),
          storage_config_directory: String.t(),
          storage_pointer_path: String.t(),
          backup_config_path: String.t()
        }

  @spec derive(term(), term(), term(), term()) ::
          {:ok, t()} | {:error, :invalid_run_id | :invalid_instance_id | :invalid_root}
  def derive(flat_run_root, sqlite_run_root, run_id, instance_id) do
    with :ok <- check_run_id(run_id),
         :ok <- check_instance_id(instance_id),
         :ok <- check_root(flat_run_root, run_id),
         :ok <- check_root(sqlite_run_root, run_id) do
      {:ok, build(flat_run_root, sqlite_run_root, run_id, instance_id)}
    end
  end

  # The storage pointer a spawn writes. It starts as flat-primary, the state every release starts
  # in; the migration step then activates SQLite exactly as `mix bnest.storage.migrate --activate`.
  @spec storage_pointer(t()) :: map()
  def storage_pointer(paths) do
    %{
      "schemaVersion" => 1,
      "databaseDirectory" => paths.db_directory,
      "databaseFilename" => @database_file,
      "phase" => "flat_primary",
      "migrationId" => "flat-files-v1-to-sqlite-v1",
      "databaseGeneration" => paths.generation
    }
  end

  defp check_run_id(run_id) when is_binary(run_id) do
    if Regex.match?(@run_id_pattern, run_id), do: :ok, else: {:error, :invalid_run_id}
  end

  defp check_run_id(_run_id), do: {:error, :invalid_run_id}

  defp check_instance_id(instance_id) when is_binary(instance_id) do
    if Regex.match?(@instance_id_pattern, instance_id),
      do: :ok,
      else: {:error, :invalid_instance_id}
  end

  defp check_instance_id(_instance_id), do: {:error, :invalid_instance_id}

  # A root must be absolute, already normalised (no `..`, `.`, `//` or trailing slash) and named
  # exactly after its run, so the instance tree can never leave the run it was derived from.
  defp check_root(root, run_id) when is_binary(root) do
    if String.starts_with?(root, "/") and root == Path.expand(root) and
         Path.basename(root) == run_id,
       do: :ok,
       else: {:error, :invalid_root}
  end

  defp check_root(_root, _run_id), do: {:error, :invalid_root}

  defp build(flat_run_root, sqlite_run_root, run_id, instance_id) do
    flat_instance_root = Path.join([flat_run_root, "instances", instance_id])
    sqlite_instance_root = Path.join([sqlite_run_root, "instances", instance_id])
    db_directory = Path.join(sqlite_instance_root, "db")
    storage_config_directory = Path.join(sqlite_run_root, "storage-config")

    %{
      run_id: run_id,
      instance_id: instance_id,
      short_id: String.slice(instance_id, 0, 8),
      generation: "test-" <> instance_id,
      flat_run_root: flat_run_root,
      sqlite_run_root: sqlite_run_root,
      flat_instance_root: flat_instance_root,
      sqlite_instance_root: sqlite_instance_root,
      flat_marker_path: Path.join(flat_instance_root, @marker_name),
      sqlite_marker_path: Path.join(sqlite_instance_root, @marker_name),
      db_directory: db_directory,
      db_file: Path.join(db_directory, @database_file),
      backup_repository_directory: Path.join(sqlite_instance_root, "backup-repository"),
      storage_config_directory: storage_config_directory,
      storage_pointer_path: Path.join(storage_config_directory, "storage.json"),
      backup_config_path: Path.join(storage_config_directory, "backup.json")
    }
  end
end
