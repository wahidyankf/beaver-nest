defmodule BnestAppWeb.DevRoutesTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.DevRoutes

  # The router's compile-time branch asks this function whether a build mounts the
  # dev-only routes (LiveDashboard, the mailbox preview and GraphiQL), passing the
  # build's `:dev_routes` configuration value. Only `config/dev.exs` sets it.
  test "a build mounts the dev-only routes only when its configuration enables them" do
    assert DevRoutes.mounted?(true)
    refute DevRoutes.mounted?(nil)
    refute DevRoutes.mounted?(false)
  end

  test "the compiled router mounts GraphiQL exactly when the seam says this build does" do
    graphiql_routes =
      Enum.filter(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))

    assert DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes)) ==
             (graphiql_routes != [])
  end
end
