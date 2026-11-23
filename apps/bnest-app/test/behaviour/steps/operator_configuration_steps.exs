defmodule BnestApp.Behaviour.OperatorConfigurationSteps do
  @moduledoc """
  Bindings for operator_configuration.feature.

  Each step delegates to the layer adapter. A Given prepares the scenario
  state, a When runs the derivation, and a Then asserts the evidence.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.IntegrationHomePageDriver
  alias BnestApp.Behaviour.OperatorConfiguration.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.OperatorConfiguration.UnitAdapter, as: Unit

  defp operator(context) do
    if Map.has_key?(context, :operator_config),
      do: context,
      else: adapter(context).install(context)
  end

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  step(
    "the push env has public key file {string} and private key file {string} and subject {string}",
    %{args: [public_file, private_file, subject]} = context
  ) do
    context = operator(context)
    adapter(context).push_env(context, public_file, private_file, subject)
  end

  step("the push configuration is derived", context) do
    context = operator(context)
    adapter(context).derive_push(context)
  end

  step("the push boot is {string}", %{args: [boot]} = context) do
    context = operator(context)
    adapter(context).assert_push(context, boot)
  end

  step("BNEST_STABLE is {string}", %{args: [stable]} = context) do
    context = operator(context)
    adapter(context).stable_env(context, stable)
  end

  step("the dev configuration is derived", context) do
    context = operator(context)
    adapter(context).derive_dev(context)
  end

  step(
    "code reload is {string} and the watchers are {string}",
    %{args: [reload, watchers]} = context
  ) do
    context = operator(context)
    adapter(context).assert_dev(context, reload, watchers)
  end

  step("the deploy peer is {string} and it is {string}", %{args: [peer, reachable]} = context) do
    context = operator(context)
    adapter(context).peer_env(context, peer, reachable)
  end

  step("readiness is checked", context) do
    context = operator(context)
    adapter(context).check_readiness(context)
  end

  step(
    "liveness is {string} and readiness is {string} and health ready answers {string}",
    %{args: [live, ready, health]} = context
  ) do
    context = operator(context)
    adapter(context).assert_readiness(context, live, ready, health)
  end

  step(
    "the deploy env misses {string} and the production origin is {string}",
    %{args: [missing, origin]} = context
  ) do
    context = operator(context)
    adapter(context).deploy_env(context, missing, origin)
  end

  step("deploy prepare is attempted", context) do
    context = operator(context)
    adapter(context).attempt_prepare(context)
  end

  step(
    "it exits 1 with {string} and writes no service definition and a prepared slot carries RELEASE_DISTRIBUTION none with the cookie from file",
    %{args: [message]} = context
  ) do
    context = operator(context)
    adapter(context).assert_prepare(context, message)
  end

  step("DNS_CLUSTER_QUERY is {string}", %{args: [query]} = context) do
    context = operator(context)
    adapter(context).cluster_env(context, query)
  end

  step("the cluster child spec is derived", context) do
    context = operator(context)
    adapter(context).derive_cluster(context)
  end

  step("the endpoint carries {string}", %{args: [cluster]} = context) do
    context = operator(context)
    adapter(context).assert_cluster(context, cluster)
  end

  step("the request host is {string} over {string}", %{args: [host, scheme]} = context) do
    context = operator(context)
    adapter(context).transport_env(context, host, scheme)
  end

  step("the production transport is derived", context) do
    context = operator(context)
    adapter(context).derive_transport(context)
  end

  step("it binds {string} and answers {string}", %{args: [bind, answer]} = context) do
    context = operator(context)
    adapter(context).assert_transport(context, bind, answer)
  end
end
