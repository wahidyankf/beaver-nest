defmodule BnestAppWeb.HealthController do
  use BnestAppWeb, :controller

  alias BnestApp.Deployment

  def live(conn, _params) do
    {:ok, health} = Deployment.liveness()
    json(conn, health)
  end

  def ready(conn, _params) do
    case Deployment.readiness() do
      {:ok, health} ->
        json(conn, health)

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "not_ready"})
    end
  end
end
