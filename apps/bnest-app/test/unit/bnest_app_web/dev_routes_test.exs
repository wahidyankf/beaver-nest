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

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A production endpoint does not serve GraphiQL
  test "the compiled router mounts GraphiQL exactly when the seam says this build does" do
    graphiql_routes =
      Enum.filter(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))

    assert DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes)) ==
             (graphiql_routes != [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A production endpoint does not serve GraphiQL
  test "a build without dev routes compiles no GraphiQL route" do
    refute DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes))

    assert Enum.filter(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql")) ==
             []
  end
end
