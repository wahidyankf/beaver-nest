defmodule BnestApp.Behaviour.OperatorConfigurationIntegrationTest do
  @moduledoc """
  Integration tests for the bound operator_configuration.feature scenario.
  Exempt scenarios need no marker here; their tags are the proof.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.OperatorConfiguration.IntegrationAdapter, as: Adapter

  defp context, do: Adapter.install(%{})

  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: Readiness fails closed while the named peer slot does not answer
  test "readiness fails closed while the peer does not answer" do
    for {peer, reachable, live, ready, health} <- [
          {"(unset)", "(n/a)", "live", "ready", "200 ready"},
          {"test-peer@test-host", "no", "live", "not_ready", "503 not_ready"}
        ] do
      context()
      |> Adapter.peer_env(peer, reachable)
      |> Adapter.check_readiness()
      |> Adapter.assert_readiness(live, ready, health)
    end
  end
end
