defmodule BnestApp.DataRepository.StorageCoordinator do
  @moduledoc false

  alias BnestApp.DataRepository.SqliteStore
  alias BnestApp.DataRepository.Store
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config

  @spec active_backend(Store.t()) :: {module(), term()}
  def active_backend(flat_store) do
    case Config.phase() do
      :sqlite_primary ->
        ensure_started!()
        {SqliteStore, SqliteStore.new(SqliteRepo)}

      :flat_primary ->
        {Store, flat_store}
    end
  end

  @spec ensure_started!() :: :ok
  def ensure_started!, do: ensure_started!(Config.resolved_database_path())

  @spec ensure_started!(String.t()) :: :ok
  def ensure_started!(database_path) do
    current = Application.get_env(:bnest_app, SqliteRepo, [])[:database]

    case Process.whereis(SqliteRepo) do
      nil ->
        start!(database_path)

      _pid when current == database_path ->
        :ok

      _pid ->
        stop()
        start!(database_path)
    end
  end

  defp start!(database_path) do
    directory = Path.dirname(database_path)
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)

    Application.put_env(
      :bnest_app,
      SqliteRepo,
      Keyword.merge(Application.get_env(:bnest_app, SqliteRepo, []), database: database_path)
    )

    case SqliteRepo.start_link() do
      {:ok, pid} ->
        Process.unlink(pid)
        protect_database_files(database_path)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok
    end
  end

  defp protect_database_files(database_path) do
    Enum.each([database_path, database_path <> "-wal", database_path <> "-shm"], fn path ->
      if File.exists?(path), do: File.chmod!(path, 0o600)
    end)
  end

  @spec stop() :: :ok
  def stop do
    case Process.whereis(SqliteRepo) do
      nil ->
        :ok

      pid ->
        reference = Process.monitor(pid)
        Process.unlink(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
        after
          2_000 -> :ok
        end
    end
  end
end
