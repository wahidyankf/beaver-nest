defmodule BnestApp.DataRepository.StorageCoordinator do
  @moduledoc false

  alias BnestApp.DataRepository.SqliteStore
  alias BnestApp.DataRepository.Store
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config

  @repo_shutdown_timeout_ms 5_000

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
      case File.chmod(path, 0o600) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          raise File.Error, reason: reason, action: "change mode for", path: path
      end
    end)
  end

  @spec stop() :: :ok
  def stop do
    case Process.whereis(SqliteRepo) do
      nil ->
        :ok

      pid ->
        Process.unlink(pid)
        Supervisor.stop(pid, :normal, @repo_shutdown_timeout_ms)
    end
  catch
    :exit, {:noproc, _details} ->
      # Another lifecycle owner completed the same stop between lookup and shutdown.
      :ok
  end
end
