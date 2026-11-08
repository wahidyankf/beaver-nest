defmodule BnestApp.TestInstance do
  @moduledoc false

  # One test instance at a time: its directories and markers, and the switch that points the running
  # server at its database. Creation and removal of directories never touch storage; the switch
  # (`Switch`) owns the pointer, the Repo, the Records store and the settings.
  #
  # Creation writes each root's marker before any child directory exists. Removal validates both run
  # markers, the instance's derivation and every marker and entry under the instance, and refuses
  # symlinks and unknown entries, before it deletes anything.
  #
  # `spawn!/2` and `drop!/1` run under one in-process lock. The current instance and the state it
  # replaced live in the application environment, so any test process sees the same current
  # instance. Unlike `:persistent_term`, a change there does not trigger a global garbage collection.

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.TestInstance.Error
  alias BnestApp.TestInstance.Paths
  alias BnestApp.TestInstance.Seed
  alias BnestApp.TestInstance.Switch
  alias BnestApp.TestRuntimeRoot

  @marker_name ".bnest-test-instance.json"
  @boot_marker_name ".bnest-test-run.json"
  @owner "bnest-test-harness"
  @phases [:sqlite_primary, :flat_primary]
  @empty_flat_name "flat-empty"
  @lock {__MODULE__, :lock}
  @current_key :test_instance_current

  @type phase :: :sqlite_primary | :flat_primary
  @type instance :: %{
          run_id: String.t(),
          instance_id: String.t(),
          phase: phase(),
          paths: Paths.t()
        }

  @doc "The run base the application is configured with: its flat root and its SQLite root."
  @spec application_run!() :: TestRuntimeRoot.t()
  def application_run! do
    sqlite_path =
      Application.get_env(:bnest_app, :test_sqlite_root) ||
        raise "the application was not started with an integration test run"

    run_id = Path.basename(sqlite_path)

    %{
      path: Path.join(TestRuntimeRoot.runs_root(), run_id),
      sqlite_path: sqlite_path,
      run_id: run_id
    }
  end

  @doc """
  Spawns one test instance and points the running server at it. Options: `:phase` (default
  `:sqlite_primary`), `:instance_id` (default random), `:seed` (after migration: a one-argument
  function run with the instance, or `{seed_key, seed_map}` applied through
  `BnestApp.TestInstance.Seed`), `:fail_after` (a step name: that step does its work and then
  fails, which tests the rollback), and `:label` (a diagnostic name the wire answers; default
  `"unlabeled"`). Raises `BnestApp.TestInstance.Error`.
  """
  @spec spawn!(TestRuntimeRoot.t(), keyword()) :: instance()
  def spawn!(run, opts \\ []) do
    with_lock(fn -> do_spawn(run, opts) end)
  end

  @doc """
  Restores an application setting saved with `Application.fetch_env/2`: a value that was set is put back, and
  one that was unset is deleted again. Tests use it for settings the integration layer leaves unset (ADR 001,
  section 1).
  """
  @spec restore_app_env(atom(), {:ok, term()} | :error) :: :ok
  def restore_app_env(key, {:ok, value}), do: Application.put_env(:bnest_app, key, value)
  def restore_app_env(key, :error), do: Application.delete_env(:bnest_app, key)

  @doc "The current instance, or nil."
  @spec state() :: instance() | nil
  def state do
    case current() do
      nil -> nil
      %{instance: instance} -> instance
    end
  end

  @doc """
  The current instance with the label and creation time its spawn recorded, or nil. The wire's
  `GET /state` answers these.
  """
  @spec info() :: %{instance: instance(), label: String.t(), created_at: String.t()} | nil
  def info do
    case current() do
      nil ->
        nil

      %{instance: instance, label: label, created_at: created_at} ->
        %{instance: instance, label: label, created_at: created_at}
    end
  end

  @doc """
  Applies a seed to the current instance when `instance_id` is its id, under the switch lock, so a
  concurrent spawn or delete cannot change the database under the write. Another id answers
  `{:error, :not_current}`. A lock that another caller holds raises `BnestApp.TestInstance.Error`
  with reason `:instance_active`.
  """
  @spec seed_current(String.t(), term(), term()) :: {:ok, map()} | {:error, term()}
  def seed_current(instance_id, seed_key, seed) do
    with_lock(fn ->
      case current() do
        %{instance: %{instance_id: ^instance_id} = instance} ->
          Seed.apply(instance, seed_key, seed)

        _other ->
          {:error, :not_current}
      end
    end)
  end

  @doc """
  The seed registry of `instance`: the seed keys applied to it and the accounts they created. It
  lives in the instance state, so `drop!/1` clears it. `{:error, :not_current}` when `instance` is
  not the current instance.
  """
  @spec seed_registry(instance()) :: {:ok, map()} | {:error, :not_current}
  def seed_registry(instance) do
    case current() do
      %{instance: ^instance} = state -> {:ok, Map.get(state, :seeds, %{})}
      _other -> {:error, :not_current}
    end
  end

  @doc "Stores `registry` as the seed registry of `instance`, which must be the current instance."
  @spec put_seed_registry(instance(), map()) :: :ok | {:error, :not_current}
  def put_seed_registry(instance, registry) do
    case current() do
      %{instance: ^instance} = state -> store_current(Map.put(state, :seeds, registry))
      _other -> {:error, :not_current}
    end
  end

  @doc """
  Removes the current instance. It validates the markers first, then stops the repo, restores the
  storage pointer, settings and Records store to their state before the spawn, and removes the
  instance directories. Raises `BnestApp.TestInstance.Error`.
  """
  @spec drop!(instance()) :: :ok
  def drop!(instance) do
    with_lock(fn -> do_drop(instance) end)
  end

  @doc "The instance directories still present under both run roots of the application's run."
  @spec audit() :: %{count: non_neg_integer(), directories: [String.t()]}
  def audit do
    run = application_run!()
    directories = instance_directories(run.path) ++ instance_directories(run.sqlite_path)
    %{count: length(directories), directories: directories}
  end

  @doc """
  `:ok` when the base is data-free: no account or user files under the flat base, and no SQLite
  database or sidecar file outside an instance directory under either base. Otherwise the
  offending paths.
  """
  @spec base_audit() :: :ok | {:error, [String.t()]}
  def base_audit do
    run = application_run!()

    violations =
      non_empty_directory(Path.join(run.path, "users")) ++
        non_empty_directory(Path.join(run.path, "system/accounts")) ++
        database_files(run.path) ++
        database_files(run.sqlite_path)

    case violations do
      [] -> :ok
      paths -> {:error, paths}
    end
  end

  @doc """
  The flat root a SQLite instance migrates from. It is an empty child of the instance, so the
  migration imports nothing from the shared run base, whatever earlier tests left there. It is not
  part of `Paths`, whose output is the contract the TypeScript path mirrors check.
  """
  @spec empty_flat_root(Paths.t()) :: String.t()
  def empty_flat_root(paths), do: Path.join(paths.sqlite_instance_root, @empty_flat_name)

  @doc "Whether an instance's directories and markers validate, with no change on disk."
  @spec validate_dirs(instance()) :: :ok | {:error, atom()}
  def validate_dirs(%{run_id: run_id, instance_id: instance_id, phase: phase, paths: paths}) do
    case check_instance(run_id, instance_id, phase, paths) do
      {:ok, _roots} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

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

  # Spawn. Every refusal happens before the first change, so a refused spawn leaves no trace.

  defp do_spawn(run, opts) do
    phase = Keyword.get(opts, :phase, :sqlite_primary)
    instance_id = Keyword.get_lazy(opts, :instance_id, &random_instance_id/0)
    preflight!(run, instance_id)
    original = Switch.snapshot()

    instance = create!(run, instance_id, phase, original, opts)
    run_step!(instance, original, :activate, opts, fn -> Switch.activate!(instance) end)
    run_step!(instance, original, :migrate, opts, fn -> Switch.migrate!(instance) end)

    # The instance is current before its seed runs, so the seed keeps its registry in the state.
    # A seed that fails clears the state again in `rollback/2`. The label and creation time are kept
    # only for the wire's state answer; nothing on disk depends on them.
    store_current(%{
      instance: instance,
      original: original,
      seeds: %{},
      label: Keyword.get(opts, :label, "unlabeled"),
      created_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })

    run_step!(instance, original, :seed, opts, fn -> run_seed(opts, instance) end)
    instance
  end

  defp preflight!(run, instance_id) do
    if state() != nil, do: refuse!(:instance_active)
    if busy?(), do: refuse!(:instance_busy)

    if Map.take(run, [:path, :sqlite_path, :run_id]) != application_run!(),
      do: refuse!(:run_mismatch)

    case Paths.derive(run.path, run.sqlite_path, run.run_id, instance_id) do
      {:ok, paths} ->
        if FileConfigStore.pointer_path() != paths.storage_pointer_path,
          do: refuse!(:pointer_mismatch)

        # A client-chosen id whose directories exist is refused here, before anything changes.
        if not absent_roots?(paths), do: refuse!(:instance_exists)

        :ok

      {:error, reason} ->
        raise Error, reason: :invalid_instance, detail: reason
    end
  end

  defp create!(run, instance_id, phase, original, opts) do
    case create_dirs(run, instance_id, phase) do
      {:ok, instance} ->
        if opts[:fail_after] == :create,
          do: fail!(instance, original, :create, {:injected, :create}),
          else: instance

      {:error, reason} ->
        fail!(nil, original, :create, reason)
    end
  end

  # A step's work either returns `:ok`, or `{:error, reason}`, or raises. The `:fail_after` option
  # turns a successful step into a failure, after its work is done, so the rollback has real work
  # to undo.
  defp run_step!(instance, original, step, opts, work) do
    result =
      try do
        work.()
      rescue
        error -> {:error, Exception.message(error)}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    injected? = opts[:fail_after] == step

    case result do
      :ok when injected? -> fail!(instance, original, step, {:injected, step})
      :ok -> :ok
      {:error, reason} -> fail!(instance, original, step, reason)
    end
  end

  defp run_seed(opts, instance) do
    case Keyword.get(opts, :seed) do
      nil -> :ok
      seed when is_function(seed, 1) -> seed.(instance)
      {seed_key, seed_map} -> seed_result(Seed.apply(instance, seed_key, seed_map))
    end
  end

  defp seed_result({:ok, _result}), do: :ok
  defp seed_result({:error, reason}), do: {:error, reason}

  # Rolls back, then raises. A rollback whose removal fails names the retained path instead, since
  # that leftover fails the run.
  defp fail!(instance, original, step, detail) do
    case rollback(instance, original) do
      :ok ->
        raise Error, reason: :spawn_failed, step: step, detail: detail

      {:error, {:cleanup_failed, reason, path}} ->
        raise Error, reason: :cleanup_failed, step: step, path: path, detail: reason
    end
  end

  # A failed create has switched nothing, so there is nothing to restore.
  defp rollback(nil, _original), do: :ok

  # A seed that failed may have been the current instance, so its state is cleared with the switch.
  defp rollback(instance, original) do
    :ok = Switch.restore!(original, instance.paths)
    clear_current()
    rollback_directories(instance)
  end

  defp rollback_directories(instance) do
    case drop_dirs(instance) do
      :ok ->
        :ok

      {:error, {:refused, reason}} ->
        {:error, {:cleanup_failed, reason, instance.paths.sqlite_instance_root}}

      {:error, {:cleanup_failed, _reason, _path} = failed} ->
        {:error, failed}
    end
  end

  # Drop

  # A refusal (busy, or a failed directory check) happens before anything changes, so the instance
  # stays current. Once the switch is restored, the instance is no longer current even if removing
  # its directories then fails; that failure is reported with the retained path.
  defp do_drop(instance) do
    case current() do
      %{instance: ^instance, original: original} ->
        if busy?(), do: refuse!(:instance_busy)
        check_before_removal!(instance)
        :ok = Switch.restore!(original, instance.paths)
        clear_current()
        remove_directories!(instance)

      _other ->
        refuse!(:not_current)
    end
  end

  defp check_before_removal!(instance) do
    case validate_dirs(instance) do
      :ok ->
        :ok

      {:error, reason} ->
        raise Error,
          reason: :refused,
          path: instance.paths.sqlite_instance_root,
          detail: reason
    end
  end

  defp remove_directories!(instance) do
    case drop_dirs(instance) do
      :ok ->
        :ok

      {:error, {:cleanup_failed, reason, path}} ->
        raise Error, reason: :cleanup_failed, path: path, detail: reason

      {:error, {:refused, reason}} ->
        raise Error,
          reason: :refused,
          path: instance.paths.sqlite_instance_root,
          detail: reason
    end
  end

  # The lock is a non-blocking `:global` lock held by the calling process for the whole call. A
  # second caller that finds it taken is refused as `:instance_active`: another switch is already
  # changing the current instance.
  defp with_lock(fun) do
    case :global.trans({@lock, self()}, fun, [node()], 0) do
      :aborted -> refuse!(:instance_active)
      result -> result
    end
  end

  defp refuse!(reason), do: raise(Error, reason: reason)

  defp current, do: Application.get_env(:bnest_app, @current_key)

  defp store_current(value), do: Application.put_env(:bnest_app, @current_key, value)

  defp clear_current, do: Application.delete_env(:bnest_app, @current_key)

  # Scheduler tasks run under this supervisor; a switch would change the database under them.
  defp busy? do
    case Process.whereis(BnestApp.Scheduler.Tasks) do
      nil -> false
      _supervisor -> Task.Supervisor.children(BnestApp.Scheduler.Tasks) != []
    end
  end

  defp random_instance_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

  defp instance_directories(root) do
    case File.ls(Path.join(root, "instances")) do
      {:ok, names} -> names |> Enum.sort() |> Enum.map(&Path.join([root, "instances", &1]))
      {:error, _reason} -> []
    end
  end

  defp non_empty_directory(directory) do
    case File.ls(directory) do
      {:ok, names} -> names |> Enum.sort() |> Enum.map(&Path.join(directory, &1))
      {:error, _reason} -> []
    end
  end

  defp database_files(root) do
    Path.wildcard(Path.join(root, "**/*.sqlite3*"))
    |> Enum.reject(&String.contains?(&1, "/instances/"))
    |> Enum.sort()
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
    if absent_roots?(paths), do: :ok, else: {:error, :instance_exists}
  end

  defp absent_roots?(paths),
    do: Enum.all?([paths.sqlite_instance_root, paths.flat_instance_root], &absent?/1)

  # `lstat` never follows a link, so a dangling or foreign link at the path counts as present.
  defp absent?(path), do: match?({:error, :enoent}, File.lstat(path))

  defp create_roots(paths, marker, phase) do
    with :ok <-
           make_root(
             paths.sqlite_instance_root,
             ["db", "backup-repository", @empty_flat_name],
             [{paths.sqlite_marker_path, marker}]
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
      make_root(paths.flat_instance_root, [], [
        {paths.flat_marker_path, marker},
        {Path.join(paths.flat_instance_root, @boot_marker_name), boot_marker(paths.instance_id)}
      ])
    end
  end

  defp create_flat_root(_paths, _marker, :sqlite_primary), do: :ok

  # The root is created alone, then its marker, then its children. A later failure removes only
  # this root, which this call has just created, so nothing unmarked survives it.
  defp make_root(root, children, markers) do
    with :ok <- File.mkdir(root) do
      case populate(root, children, markers) do
        :ok ->
          :ok

        {:error, reason} ->
          File.rm_rf(root)
          {:error, reason}
      end
    end
  end

  defp populate(root, children, markers) do
    with :ok <- write_markers(markers) do
      Enum.reduce_while(children, :ok, &make_child(root, &1, &2))
    end
  end

  defp write_markers(markers) do
    Enum.reduce_while(markers, :ok, fn {path, marker}, :ok ->
      case File.write(path, Jason.encode!(marker)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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

  # The application start validates a test runtime root with `FileRecordBackend.new!/1`, which reads a
  # `bnest-test-run` marker named `.bnest-test-run.json` whose `runId` is the root's own basename. A
  # secondary BEAM boots on the flat instance root, so that root carries this boot marker beside its
  # instance marker; lib validation stays as it is. The instance marker alone proves ownership.
  defp boot_marker(instance_id) do
    %{
      "schemaVersion" => 1,
      "recordType" => "bnest-test-run",
      "runId" => instance_id,
      "createdAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "owner" => @owner
    }
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
  #
  # An entry that vanishes during the walk is already gone, not a refusal: SQLite deletes its
  # write-ahead and shared-memory files when its last connection closes. `lstat` still reports a
  # dangling link as a symlink, so a planted link is refused either way.
  defp check_entries(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, %File.Stat{type: :directory}} -> check_directory(path)
      {:ok, %File.Stat{type: :symlink}} -> {:error, :symlink}
      {:ok, _other} -> {:error, :unsupported_entry}
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_directory(path) do
    case File.ls(path) do
      {:ok, names} -> check_children(path, names)
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
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
