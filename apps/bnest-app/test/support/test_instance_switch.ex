defmodule BnestApp.TestInstance.Switch do
  @moduledoc false

  # The storage half of the switch protocol. `activate!/1` re-points the running server at an
  # instance under the exclusive storage lease; `migrate!/1` runs the release entry points
  # outside that lease, because they take the lease themselves. `snapshot/0` and `restore!/1`
  # hold everything a switch changes, so a drop or a rollback returns to the state before a spawn.
  #
  # Nothing here is production code: the Records store is replaced from test support, and the
  # store is built as the `FileRecordBackend` struct, since `FileRecordBackend.new!/1` refuses
  # an instance root (it wants a run marker there, not an instance marker).

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Release.Migrations
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Records
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Paths

  # The application settings a switch changes. `:family_chat_sqlite_path` is removed for an
  # instance, because Family Chat would otherwise re-point the shared repo at its own file, and the
  # instance has one database, as production does.
  @env_keys [:runtime_root, :backup_repository_root, :family_chat_sqlite_path]

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
  def activate!(%{paths: paths, phase: phase}) do
    Storage.with_exclusive_lock(fn ->
      :ok = Storage.stop()
      :ok = FileConfigStore.write!(Paths.storage_pointer(paths))
      Application.put_env(:bnest_app, :backup_repository_root, paths.backup_repository_directory)
      Application.delete_env(:bnest_app, :family_chat_sqlite_path)
      remove_file(paths.backup_config_path)

      if phase == :flat_primary do
        Application.put_env(:bnest_app, :runtime_root, paths.flat_instance_root)
        swap_records(flat_store(paths.flat_instance_root))
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
      restore_pointer(original.pointer)
      Enum.each(original.env, fn {key, value} -> restore_env(key, value) end)
      swap_records(original.records_store)
      remove_file(paths.backup_config_path)
      :ok
    end)
  end

  defp swap_records(store) do
    :sys.replace_state(Records, fn state -> %{state | store: store} end)
    :ok
  end

  # `FileRecordBackend.new!/1` validates a run marker, so the struct it would return is built here.
  defp flat_store(root), do: %{backend: FileRecordBackend, root: root, replace: &File.rename/2}

  defp read_pointer do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
    end
  end

  defp restore_pointer(nil), do: remove_file(FileConfigStore.pointer_path())

  defp restore_pointer(bytes) do
    File.write!(FileConfigStore.pointer_path(), bytes)
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
