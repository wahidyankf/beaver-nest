defmodule BnestAppWeb.HealthController do
  use BnestAppWeb, :controller

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Deployment
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.Storage.Lock, as: StorageLock

  def live(conn, _params) do
    {:ok, health} = Deployment.liveness()
    json(conn, health)
  end

  def ready(conn, _params) do
    with {:ok, health} <- Deployment.readiness(),
         :ok <- storage_ready() do
      json(
        conn,
        health
        |> Map.put(:sqliteReady, sqlite_primary?())
        |> Map.put(:schedulerReady, scheduler_ready?())
        |> Map.put(:storageGeneration, StorageConfig.database_generation())
      )
    else
      _not_ready ->
        conn |> put_status(:service_unavailable) |> json(%{status: "not_ready"})
    end
  end

  # The SQLite phase is optional-timing and decoupled from ordinary releases
  # (see BnestApp.Storage.Migration): readiness only requires a reachable
  # database once the phase pointer has switched storage authority to it.
  defp storage_ready do
    if sqlite_primary?() do
      StorageLock.with_shared(fn ->
        StorageCoordinator.ensure_started!()
        storage_query_ready()
      end)
    else
      :ok
    end
  rescue
    _error -> {:error, :sqlite_not_ready}
  end

  defp storage_query_ready do
    case SqliteRepo.query("""
         SELECT COUNT(*) FROM bnest_schedules
         WHERE schedule_key = 'prod-sqlite-backup-daily'
           AND handler_key = 'prod_sqlite_backup'
           AND expiration_kind = 'never'
         """) do
      {:ok, %{rows: [[1]]}} ->
        if scheduler_ready?(), do: :ok, else: {:error, :scheduler_not_ready}

      _error ->
        {:error, :sqlite_not_ready}
    end
  end

  defp scheduler_ready?, do: BnestApp.Scheduler.ready?()
  defp sqlite_primary?, do: StorageConfig.phase() == :sqlite_primary
end
