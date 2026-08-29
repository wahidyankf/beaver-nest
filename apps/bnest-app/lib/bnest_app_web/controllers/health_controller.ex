defmodule BnestAppWeb.HealthController do
  use BnestAppWeb, :controller

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Deployment
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig

  def live(conn, _params) do
    {:ok, health} = Deployment.liveness()
    json(conn, health)
  end

  def ready(conn, _params) do
    with {:ok, health} <- Deployment.readiness(),
         :ok <- storage_ready() do
      json(conn, Map.put(health, :sqliteReady, sqlite_primary?()))
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
      StorageCoordinator.ensure_started!()

      case SqliteRepo.query("SELECT 1") do
        {:ok, _result} -> :ok
        _error -> {:error, :sqlite_not_ready}
      end
    else
      :ok
    end
  rescue
    _error -> {:error, :sqlite_not_ready}
  end

  defp sqlite_primary?, do: StorageConfig.phase() == :sqlite_primary
end
