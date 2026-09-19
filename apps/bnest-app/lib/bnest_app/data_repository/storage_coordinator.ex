defmodule BnestApp.DataRepository.StorageCoordinator do
  @moduledoc false

  alias BnestApp.DataRepository.SqliteStore
  alias BnestApp.DataRepository.Store
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias Exqlite.Sqlite3

  @database_startup_timeout_ms 5_000
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

  # `active_backend/1` can be called concurrently by any number of request
  # processes (it runs inside `Storage.Lock.with_shared/1`, which allows
  # multiple simultaneous shared holders). Without this lock, two concurrent
  # callers can each decide the repo needs restarting and race: one stops
  # the repo pid the other is already mid-query against, which crashes that
  # query with an `Ecto.Repo.Registry` lookup failure on the now-dead pid.
  # `:global.trans/2` makes the whole check-and-maybe-restart decision one
  # atomic step, so a concurrent caller either sees the fully-restarted repo
  # or waits for the in-flight restart to finish before deciding anything.
  @spec ensure_started!(String.t()) :: :ok
  def ensure_started!(database_path) do
    :global.trans({__MODULE__, self()}, fn -> ensure_started_locked!(database_path) end)
    :ok
  end

  defp ensure_started_locked!(database_path) do
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
    prepare_journal!(database_path)
    protect_database_files(database_path)

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

  defp prepare_journal!(database_path) do
    {:ok, database} = Sqlite3.open(database_path)

    try do
      :ok = Sqlite3.set_busy_timeout(database, @database_startup_timeout_ms)
      :ok = Sqlite3.execute(database, "PRAGMA journal_mode=WAL")
    after
      :ok = Sqlite3.close(database)
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
