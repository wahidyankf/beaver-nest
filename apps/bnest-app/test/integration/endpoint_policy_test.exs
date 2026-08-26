defmodule BnestApp.EndpointPolicyTest do
  use ExUnit.Case, async: true

  test "the Phoenix endpoint server stays disabled in integration tests" do
    endpoint_config = Application.fetch_env!(:bnest_app, BnestAppWeb.Endpoint)

    assert endpoint_config[:server] == false
  end

  test "exposes liveness and readiness contracts without starting an HTTP server" do
    assert {:ok, %{status: "live", revision: revision}} = BnestApp.Deployment.liveness()
    assert is_binary(revision)

    assert {:ok, %{status: "ready", revision: ^revision}} = BnestApp.Deployment.readiness()
  end
end
