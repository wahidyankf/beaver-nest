defmodule BnestApp.Behaviour.ProxySteps do
  @moduledoc """
  Bindings for the BN-CLI-05 proxy scenarios in
  `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  Each step delegates to the adapter the layer installed
  (`Proxy.UnitAdapter` for the unit layer, `Proxy.IntegrationAdapter` for
  the integration layer). A Given prepares the scenario's deploy root, a
  When runs the proxy command, and a Then asserts the recorded evidence, so
  no step is a placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.IntegrationHomePageDriver
  alias BnestApp.Behaviour.Proxy.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.Proxy.UnitAdapter, as: Unit

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  # The hooks install the web drivers, not the proxy adapter: the first
  # proxy step of a scenario installs it, later steps reuse the state.
  defp proxy(context) do
    if Map.has_key?(context, :proxy), do: context, else: adapter(context).install(context)
  end

  # proxy:install writes a validated Caddy configuration for the active slot
  # and installs its service (BN-CLI-05).

  step("the deployment state routes the {string} slot", %{args: [slot]} = context) do
    context = proxy(context)
    adapter(context).route_slot(context, slot)
  end

  step("proxy:install runs with its doubles", context) do
    context = proxy(context)
    adapter(context).run_install(context)
  end

  step(
    "it writes the Caddy configuration for the active slot, validates it, and installs its service",
    context
  ) do
    context = proxy(context)
    adapter(context).assert_install(context)
  end

  step("it leaves {string} on standard output", %{args: [line]} = context) do
    context = proxy(context)
    adapter(context).assert_line(context, line)
  end

  # proxy:status prints the routed slot and revision and exits 1 when Caddy
  # is not ready (BN-CLI-05).

  step(
    "the deployment state routes the {string} slot at the revision",
    %{args: [slot]} = context
  ) do
    context = proxy(context)
    adapter(context).route_slot_at_revision(context, slot)
  end

  step("proxy:status runs against a silent Caddy port", context) do
    context = proxy(context)
    adapter(context).run_status(context)
  end

  step("it prints the routed slot and revision with caddyReady false and exits 1", context) do
    context = proxy(context)
    adapter(context).assert_status(context)
  end
end
