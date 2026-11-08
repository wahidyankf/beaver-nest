defmodule BnestAppWeb.TestingRoutesTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Router
  alias BnestAppWeb.TestingRoutes

  # The router takes this decision at compile time for the build's environment and its
  # `:testing_control` value. Only `config/test.exs` sets that value, and only the test
  # environment may mount the testing routes, whatever the flag says.
  @flags [true, false, nil]

  test "a production build mounts no testing route whatever the flag says" do
    for flag <- @flags do
      refute TestingRoutes.mounted?(:prod, flag)
    end
  end

  test "a development build mounts no testing route whatever the flag says" do
    for flag <- @flags do
      refute TestingRoutes.mounted?(:dev, flag)
    end
  end

  test "a test build mounts the testing routes only when the flag is true" do
    assert TestingRoutes.mounted?(:test, true)
    refute TestingRoutes.mounted?(:test, false)
    refute TestingRoutes.mounted?(:test, nil)
  end

  test "only the exact boolean true enables the testing routes in a test build" do
    refute TestingRoutes.mounted?(:test, "true")
    refute TestingRoutes.mounted?(:test, 1)
  end

  test "the compiled router mounts the testing routes exactly when this build's seam says so" do
    assert Router.testing_routes_enabled?() ==
             TestingRoutes.mounted?(Mix.env(), Application.get_env(:bnest_app, :testing_control))
  end
end
