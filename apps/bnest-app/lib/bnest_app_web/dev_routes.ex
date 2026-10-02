defmodule BnestAppWeb.DevRoutes do
  @moduledoc """
  Whether a build mounts the dev-only routes: LiveDashboard, the mailbox preview, and
  GraphiQL. `BnestAppWeb.Router` calls `mounted?/1` at compile time with the build's
  `:dev_routes` configuration value, which only `config/dev.exs` sets; test and production
  builds leave it unset, so neither compiles those routes (tech-doc 008).
  """

  @spec mounted?(term()) :: boolean()
  def mounted?(dev_routes_flag), do: dev_routes_flag not in [nil, false]
end
