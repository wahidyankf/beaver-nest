defmodule BnestApp.FamilyChatDeploymentBindingTest do
  @moduledoc """
  Integration bindings for the family chat scenarios that inspect the generated reverse-proxy configuration. The
  generator is the deployment tool's own Node module, run through `BnestApp.Test.CaddyConfigurationProbe`. No instance
  or database is needed, so each test runs without one.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.IntegrationFamilyChatDriver, as: Driver

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: The generated Caddy configuration rejects a nonzero stream-close delay
  test "the generated Caddy configuration rejects a nonzero stream-close delay" do
    context = Driver.perform_behaviour(%{}, :generate_caddy_configurations, [])

    assert Driver.behaviour_outcome?(context, :caddy_omits_stream_close_delay, [])
    assert Driver.behaviour_outcome?(context, :caddy_grace_period_present, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A replacement handshake routes only to the promoted slot while the prior slot stays warm
  test "a replacement handshake routes only to the promoted slot while the prior slot stays warm" do
    context = Driver.perform_behaviour(%{}, :generate_caddy_configurations, [])

    assert Driver.behaviour_outcome?(context, :handshake_routed_only_to_promoted, [])
    assert Driver.behaviour_outcome?(context, :no_handshake_reaches_prior_slot, [])
  end
end
