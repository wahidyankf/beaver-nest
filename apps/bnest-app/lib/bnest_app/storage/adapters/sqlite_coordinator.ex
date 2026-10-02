defmodule BnestApp.Storage.Adapters.SqliteCoordinator do
  @moduledoc """
  Owns the `BnestApp.SqliteRepo` process: starts it against the configured database path,
  restarts it when the path changed, stops it, and applies its schema migrations and names
  their committed sources.
  """

  @behaviour BnestApp.Storage.Ports.DatabaseLifecycle

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteRecordBackend
  alias Exqlite.Sqlite3

  @database_startup_timeout_ms 5_000
  @repo_shutdown_timeout_ms 5_000

  @impl true
  def record_backend, do: {SqliteRecordBackend, SqliteRecordBackend.new(SqliteRepo)}

  @impl true
  def migrate_schema! do
    Ecto.Migrator.run(SqliteRepo, migrations_path(), :up, all: true)
    :ok
  end

  @impl true
  def schema_sources do
    migrations_path()
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&File.read!/1)
  end

  @impl true
  def ensure_started!, do: ensure_started!(FileConfigStore.resolved_database_path())

  # The active record backend is resolved concurrently by any number of request
  # processes (it runs inside the shared storage lease, which allows
  # multiple simultaneous shared holders). Without this lock, two concurrent
  # callers can each decide the repo needs restarting and race: one stops
  # the repo pid the other is already mid-query against, which crashes that
  # query with an `Ecto.Repo.Registry` lookup failure on the now-dead pid.
  # `:global.trans/2` makes the whole check-and-maybe-restart decision one
  # atomic step, so a concurrent caller either sees the fully-restarted repo
  # or waits for the in-flight restart to finish before deciding anything.
  @impl true
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

  @impl true
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

  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
end
