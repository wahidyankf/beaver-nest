defmodule BnestAppWeb.ScenarioCase do
  @moduledoc """
  The ExUnit case template of an integration ExBdd scenario (ADR 001, sections 1 and 3).

  It gives a scenario the connection conveniences of `BnestAppWeb.ConnCase`, and no setup. The scenario's fresh
  instance is spawned by the ExBdd `before_scenario` hook in `test/behaviour/support/integration.exs` and dropped by
  its `after_scenario` hook. A ConnCase setup here would spawn a second instance for the same scenario, which the
  switch refuses.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BnestAppWeb.Endpoint

      use BnestAppWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import BnestAppWeb.ConnCase
    end
  end
end
