defmodule BnestApp.TestInstance.Switch do
  @moduledoc false

  # The storage half of the switch protocol. `activate!/1` re-points the running server at an
  # instance under the exclusive storage lease; `migrate!/1` runs the release entry points
  # outside that lease, because they take the lease themselves. `snapshot/0` and `restore!/1`
  # hold everything a switch changes, so a drop or a rollback returns to the state before a spawn.
  #
  # Nothing here is production code: the Records store is replaced from test support. The store comes from
  # `FileRecordBackend.new!/1`, which accepts the flat instance root because spawn marks it with the run marker
  # that function reads.

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Release.Migrations
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Records
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Paths
  alias BnestApp.TestRuntimeRoot

  # The application settings a switch changes. `:family_chat_sqlite_path` is removed for an
  # instance, because Family Chat would otherwise re-point the shared repo at its own file, and the
  # instance has one database, as production does.
  #
  # `:storage_profile` changes for an unconfigured instance only (see `write_pointer/1`).
  @env_keys [:runtime_root, :backup_repository_root, :family_chat_sqlite_path, :storage_profile]

  @type original :: %{
          pointer: binary() | nil,
          env: %{atom() => {:ok, term()} | :error},
          records_store: term()
        }

  @spec snapshot() :: original()
  def snapshot do
    %{
      pointer: read_pointer(),
      env: Map.new(@env_keys, &{&1, Application.fetch_env(:bnest_app, &1)}),
      records_store: :sys.get_state(Records).store
    }
  end

  # Runs under the exclusive lease, which drains every `Records` operation holding a shared lease.
  # Family Chat, Push and Scheduler SQL does not take the lease, so the caller refuses a busy
  # Scheduler before it gets here.
  @spec activate!(map()) :: :ok
  def activate!(%{paths: paths, phase: phase} = instance) do
    Storage.with_exclusive_lock(fn ->
      :ok = Storage.stop()
      write_pointer(instance)
      Application.put_env(:bnest_app, :backup_repository_root, paths.backup_repository_directory)
      Application.delete_env(:bnest_app, :family_chat_sqlite_path)
      remove_file(paths.backup_config_path)

      if phase == :flat_primary do
        Application.put_env(:bnest_app, :runtime_root, paths.flat_instance_root)
        swap_records(FileRecordBackend.new!(paths.flat_instance_root))
      end

      :ok
    end)
  end

  # The release order: the migration of the storage authority first, then the release seeds and
  # their verification. Each takes its own lease, so nothing here nests one.
  @spec migrate!(map()) :: :ok | {:error, term()}
  def migrate!(%{paths: paths, phase: :sqlite_primary}) do
    case Storage.migrate(TestInstance.empty_flat_root(paths), true) do
      {:ok, :activated, _report} -> Migrations.apply_and_verify!()
      {:error, reason, _report} -> {:error, reason}
    end
  end

  # An unconfigured instance has no database to migrate: the administrator's choice of a location creates it.
  def migrate!(%{storage: :unconfigured}), do: :ok

  def migrate!(%{phase: :flat_primary}) do
    :ok = Storage.ensure_started!()
    :ok = SqliteCoordinator.migrate_schema!()
    Migrations.apply_and_verify!()
  end

  # Puts back what `snapshot/0` read: the pointer bytes (or no pointer), the settings, the Records
  # store, and no repository running. Stopping first keeps a stale repo off a removed file. It also
  # removes the instance's backup configuration, as `activate!/1` does, so a drop or a rollback
  # leaves no backup configuration behind.
  @spec restore!(original(), Paths.t()) :: :ok
  def restore!(original, paths) do
    Storage.with_exclusive_lock(fn ->
      :ok = Storage.stop()
      restore_pointer(original.pointer, paths.storage_pointer_path)
      Enum.each(original.env, fn {key, value} -> restore_env(key, value) end)
      swap_records(original.records_store)
      remove_file(paths.backup_config_path)
      :ok
    end)
  end

  # A fresh installation has chosen no location, so an unconfigured instance has no pointer. A pointer left in
  # the run base by an earlier owner is removed, so the first one is written by the choice under test.
  #
  # Anything that reads storage with no pointer (the storage page does) opens the storage profile's default
  # location, which is the run base. The profile is re-pointed at the instance's own `db/` directory, so that read
  # creates its file inside the instance and the run base stays data-free. The profile's id is a path below the
  # SQLite runs root, which `Location.test_data_directory/1` joins.
  defp write_pointer(%{storage: :unconfigured, paths: paths}) do
    remove_file(paths.storage_pointer_path)

    Application.put_env(
      :bnest_app,
      :storage_profile,
      {:test, Path.relative_to(paths.db_directory, TestRuntimeRoot.sqlite_runs_root())}
    )
  end

  defp write_pointer(%{paths: paths}),
    do: :ok = FileConfigStore.write!(Paths.storage_pointer(paths))

  defp swap_records(store) do
    :sys.replace_state(Records, fn state -> %{state | store: store} end)
    :ok
  end

  defp read_pointer do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
    end
  end

  # The path is the one the spawn checked (the run base's pointer), not `FileConfigStore.pointer_path/0`: a scenario
  # may shadow `BNEST_STORAGE_CONFIG` until its own teardown, and a restore through that shadow would leave the
  # run base pointing at the dropped instance.
  defp restore_pointer(nil, path), do: remove_file(path)

  defp restore_pointer(bytes, path) do
    File.write!(path, bytes)
    :ok
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:bnest_app, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:bnest_app, key)

  defp remove_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
    end
  end
end
