defmodule BnestAppWeb.TestingRoutesRouterTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Router

  # The four testing-control routes, as route patterns below `/__bnest_testing/v1`.
  @routes [
    {:get, "/state"},
    {:post, "/instances"},
    {:post, "/instances/:id/seed"},
    {:delete, "/instances/:id"}
  ]

  test "the test build compiles exactly the four testing-control routes" do
    compiled =
      for %{verb: verb, path: "/__bnest_testing/v1" <> pattern} <- Router.__routes__(),
          do: {verb, pattern}

    assert Enum.sort(compiled) == Enum.sort(@routes)
  end

  # The guard refuses an unguarded request by raising the error a missing route raises, so the
  # endpoint renders the same stock not-found response for both. This unit layer has no endpoint, so
  # it checks the raise itself; the integration layer compares the rendered responses. A pipeline
  # wraps an error it raises, so the guard's error arrives as the wrapper's reason.
  test "an unguarded request to each testing route raises the missing-route error" do
    for {verb, pattern} <- @routes do
      request_path = "/__bnest_testing/v1" <> String.replace(pattern, ":id", "0123456789abcdef")

      assert_guard_refusal(fn ->
        Router.call(Plug.Test.conn(verb, request_path), Router.init([]))
      end)
    end
  end

  test "a missing route under the same prefix raises the same error" do
    assert_raise Phoenix.Router.NoRouteError, fn ->
      Router.call(Plug.Test.conn(:get, "/__bnest_testing/v1/no-such-route"), Router.init([]))
    end
  end

  defp assert_guard_refusal(fun) do
    wrapper = assert_raise Plug.Conn.WrapperError, fun
    assert %Phoenix.Router.NoRouteError{} = wrapper.reason
  end
end
