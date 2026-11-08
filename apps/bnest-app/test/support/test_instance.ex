defmodule BnestApp.TestInstance do
  @moduledoc false

  # Creates and removes one test instance's directories and markers. It never touches storage: the
  # database file, the storage pointer and the Repo belong to the switch protocol.
  #
  # Creation writes each root's marker before any child directory exists. Removal validates both run
  # markers, the instance's derivation and every marker and entry under the instance, and refuses
  # symlinks and unknown entries, before it deletes anything.

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.TestInstance.Paths
  alias BnestApp.TestRuntimeRoot

  @marker_name ".bnest-test-instance.json"
  @owner "bnest-test-harness"
  @phases [:sqlite_primary, :flat_primary]

  @type phase :: :sqlite_primary | :flat_primary
  @type instance :: %{
          run_id: String.t(),
          instance_id: String.t(),
          phase: phase(),
          paths: Paths.t()
        }

  @spec create_dirs(TestRuntimeRoot.t(), String.t(), phase()) ::
          {:ok, instance()} | {:error, atom()}
  def create_dirs(%{path: flat, sqlite_path: sqlite, run_id: run_id}, instance_id, phase)
      when phase in @phases do
    with {:ok, paths} <- Paths.derive(flat, sqlite, run_id, instance_id),
         :ok <- validate_run_roots(flat, sqlite, run_id),
         :ok <- ensure_absent(paths),
         :ok <- ensure_directory(Path.dirname(paths.sqlite_instance_root)),
         :ok <- create_roots(paths, marker(run_id, instance_id), phase) do
      {:ok, %{run_id: run_id, instance_id: instance_id, phase: phase, paths: paths}}
    end
  end

  @spec drop_dirs(instance()) ::
          :ok
          | {:error, {:refused, atom()}}
          | {:error, {:cleanup_failed, atom(), String.t()}}
  def drop_dirs(%{run_id: run_id, instance_id: instance_id, phase: phase, paths: paths}) do
    case check_instance(run_id, instance_id, phase, paths) do
      {:ok, roots} ->
        with :ok <- remove_roots(roots), do: remove_empty_instances_directories(paths)

      {:error, reason} ->
        {:error, {:refused, reason}}
    end
  end

  defp validate_run_roots(flat, sqlite, run_id) do
    with :ok <- run_root_check(TestRuntimeRoot.validate(flat), run_id) do
      run_root_check(TestRuntimeRoot.validate_sqlite(sqlite), run_id)
    end
  end

  defp run_root_check({:ok, %{run_id: run_id}}, run_id), do: :ok
  defp run_root_check({:ok, _other}, _run_id), do: {:error, :run_id_mismatch}
  defp run_root_check(:ok, _run_id), do: {:error, :run_root_missing}
  defp run_root_check({:error, reason}, _run_id), do: {:error, reason}

  defp ensure_absent(paths) do
    if Enum.all?([paths.sqlite_instance_root, paths.flat_instance_root], &absent?/1),
      do: :ok,
      else: {:error, :instance_exists}
  end

  # `lstat` never follows a link, so a dangling or foreign link at the path counts as present.
  defp absent?(path), do: match?({:error, :enoent}, File.lstat(path))

  defp create_roots(paths, marker, phase) do
    with :ok <-
           make_root(
             paths.sqlite_instance_root,
             ["db", "backup-repository"],
             paths.sqlite_marker_path,
             marker
           ) do
      case create_flat_root(paths, marker, phase) do
        :ok ->
          :ok

        {:error, reason} ->
          File.rm_rf(paths.sqlite_instance_root)
          {:error, reason}
      end
    end
  end

  defp create_flat_root(paths, marker, :flat_primary) do
    with :ok <- ensure_directory(Path.dirname(paths.flat_instance_root)) do
      make_root(paths.flat_instance_root, [], paths.flat_marker_path, marker)
    end
  end

  defp create_flat_root(_paths, _marker, :sqlite_primary), do: :ok

  # The root is created alone, then its marker, then its children. A later failure removes only
  # this root, which this call has just created, so nothing unmarked survives it.
  defp make_root(root, children, marker_path, marker) do
    with :ok <- File.mkdir(root) do
      case populate(root, children, marker_path, marker) do
        :ok ->
          :ok

        {:error, reason} ->
          File.rm_rf(root)
          {:error, reason}
      end
    end
  end

  defp populate(root, children, marker_path, marker) do
    with :ok <- File.write(marker_path, Jason.encode!(marker)) do
      Enum.reduce_while(children, :ok, &make_child(root, &1, &2))
    end
  end

  defp make_child(root, child, :ok) do
    case File.mkdir(Path.join(root, child)) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp ensure_directory(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, %File.Stat{type: :symlink}} -> {:error, :symlink}
      {:ok, _other} -> {:error, :not_directory}
      {:error, :enoent} -> File.mkdir(path)
      {:error, reason} -> {:error, reason}
    end
  end

  defp marker(run_id, instance_id) do
    %{
      "schemaVersion" => 1,
      "recordType" => "bnest-test-instance",
      "runId" => run_id,
      "instanceId" => instance_id,
      "owner" => @owner,
      "createdAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  # Every check runs before the first removal. A refusal names its reason and deletes nothing.
  defp check_instance(run_id, instance_id, phase, paths) do
    with :ok <- check_derivation(run_id, instance_id, paths),
         :ok <- validate_run_roots(paths.flat_run_root, paths.sqlite_run_root, run_id),
         :ok <- check_tree(paths.sqlite_instance_root, run_id, instance_id),
         {:ok, flat_roots} <- flat_roots(phase, paths, run_id, instance_id) do
      {:ok, [paths.sqlite_instance_root | flat_roots]}
    end
  end

  # The paths must be exactly what the instance id derives from the run roots, and the instance
  # must sit directly under its run's `instances/`. A struct edited to point elsewhere is refused.
  defp check_derivation(run_id, instance_id, paths) do
    if Path.dirname(paths.sqlite_instance_root) != Path.join(paths.sqlite_run_root, "instances") do
      {:error, :outside_run}
    else
      case Paths.derive(paths.flat_run_root, paths.sqlite_run_root, run_id, instance_id) do
        {:ok, ^paths} -> :ok
        {:ok, _other} -> {:error, :path_mismatch}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp flat_roots(:flat_primary, paths, run_id, instance_id) do
    with :ok <- check_tree(paths.flat_instance_root, run_id, instance_id) do
      {:ok, [paths.flat_instance_root]}
    end
  end

  defp flat_roots(:sqlite_primary, paths, _run_id, _instance_id) do
    if absent?(paths.flat_instance_root),
      do: {:ok, []},
      else: {:error, :unexpected_flat_root}
  end

  defp flat_roots(_phase, _paths, _run_id, _instance_id), do: {:error, :invalid_phase}

  defp check_tree(root, run_id, instance_id) do
    with :ok <- directory_entry(Path.dirname(root)),
         :ok <- directory_entry(root),
         :ok <- check_marker(root, run_id, instance_id) do
      check_entries(root)
    end
  end

  defp directory_entry(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, %File.Stat{type: :symlink}} -> {:error, :symlink}
      {:ok, _other} -> {:error, :not_directory}
      {:error, :enoent} -> {:error, :missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_marker(root, run_id, instance_id) do
    marker_path = Path.join(root, @marker_name)

    case File.lstat(marker_path) do
      {:ok, %File.Stat{type: :regular}} ->
        if valid_marker?(marker_path, run_id, instance_id),
          do: :ok,
          else: {:error, :invalid_marker}

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :symlink}

      {:error, :enoent} ->
        {:error, :unmarked}

      {:ok, _other} ->
        {:error, :invalid_marker}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_marker?(marker_path, run_id, instance_id) do
    with {:ok, bytes} <- File.read(marker_path),
         {:ok,
          %{
            "schemaVersion" => 1,
            "recordType" => "bnest-test-instance",
            "runId" => ^run_id,
            "instanceId" => ^instance_id,
            "owner" => @owner,
            "createdAt" => created_at
          }} <- Jason.decode(bytes) do
      match?({:ok, _datetime, 0}, DateTime.from_iso8601(created_at))
    else
      _invalid -> false
    end
  end

  # Walks the whole instance tree without following links. Only directories and regular files may
  # appear, so a link planted inside an instance can never redirect a removal.
  defp check_entries(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok

      {:ok, %File.Stat{type: :directory}} ->
        with {:ok, names} <- File.ls(path), do: check_children(path, names)

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :symlink}

      {:ok, _other} ->
        {:error, :unsupported_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_children(path, names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case check_entries(Path.join(path, name)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp remove_roots(roots) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      case remove_root(root) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:cleanup_failed, reason, root}}}
      end
    end)
  end

  defp remove_root(root) do
    case File.rm_rf(root) do
      {:ok, _removed} ->
        case File.lstat(root) do
          {:error, :enoent} -> :ok
          _still_present -> {:error, :still_present}
        end

      {:error, reason, _file} ->
        {:error, reason}
    end
  end

  # `rmdir` removes only an empty directory, so a sibling instance that is still present keeps its
  # `instances/` directory.
  defp remove_empty_instances_directories(paths) do
    File.rmdir(Path.join(paths.sqlite_run_root, "instances"))
    File.rmdir(Path.join(paths.flat_run_root, "instances"))
    :ok
  end
end
