defmodule BnestApp.EndpointPolicyTest do
  use ExUnit.Case, async: true

  test "the Phoenix endpoint server stays disabled in integration tests" do
    endpoint_config = Application.fetch_env!(:bnest_app, BnestAppWeb.Endpoint)

    assert endpoint_config[:server] == false
  end
end
