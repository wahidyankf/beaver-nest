defmodule BnestAppWeb.TestingRoutes do
  @moduledoc """
  Whether a build mounts the test-only testing-control routes under `/__bnest_testing/v1`.

  `BnestAppWeb.Router` calls `mounted?/2` at compile time with the build environment and the
  `:testing_control` configuration value, which only `config/test.exs` sets. Only the test
  environment with that flag set true mounts the routes. Development and production builds
  compile them out, so the decision fails closed on every other input.
  """

  @spec mounted?(atom(), term()) :: boolean()
  def mounted?(env, testing_control_flag), do: env == :test and testing_control_flag === true
end
