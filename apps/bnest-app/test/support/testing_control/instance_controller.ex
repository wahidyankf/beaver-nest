defmodule BnestAppWeb.TestingControl.InstanceController do
  @moduledoc """
  The testing-control routes for instance state, spawn, seed and teardown.

  The router mounts these routes only in the test build (see `BnestAppWeb.TestingRoutes`), and this
  module lives in `test/support`, so a production beam never contains it. This first version answers
  the stock not-found response for every action, the same response a missing route gets. No guard
  passes yet and no instance is created. The guards and the handlers replace these bodies.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
  use BnestAppWeb, :controller

  def state(conn, _params), do: not_found(conn)
  def create(conn, _params), do: not_found(conn)
  def seed(conn, _params), do: not_found(conn)
  def delete(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(json: BnestAppWeb.ErrorJSON)
    |> render(:"404")
  end
end
