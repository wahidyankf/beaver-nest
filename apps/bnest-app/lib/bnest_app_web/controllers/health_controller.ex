defmodule BnestAppWeb.HealthController do
  use BnestAppWeb, :controller

  alias BnestApp.Operations

  def live(conn, _params) do
    {:ok, health} = Operations.liveness()
    json(conn, health)
  end

  def ready(conn, _params) do
    case Operations.health() do
      {:ok, health} ->
        json(conn, health)

      {:error, _not_ready} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "not_ready"})
    end
  end
end
