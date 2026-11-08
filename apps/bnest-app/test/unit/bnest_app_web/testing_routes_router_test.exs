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

  # No guard passes yet, so every request gets the stock not-found response a missing route gets.
  test "an unguarded request to each testing route gets the stock not-found response" do
    for {verb, pattern} <- @routes do
      request_path = "/__bnest_testing/v1" <> String.replace(pattern, ":id", "abc123")
      conn = Router.call(Plug.Test.conn(verb, request_path), Router.init([]))

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"errors" => %{"detail" => "Not Found"}}
    end
  end
end
