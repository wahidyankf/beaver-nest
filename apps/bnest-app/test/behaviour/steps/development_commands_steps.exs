defmodule BnestApp.Behaviour.DevelopmentCommandsSteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-be/behaviours/development_commands.feature`.

  Each step delegates to the adapter the layer installed
  (`DevelopmentCommands.UnitAdapter` for the unit layer,
  `DevelopmentCommands.IntegrationAdapter` for the integration layer). A
  Given or When records what it observed, and a Then asserts that recorded
  evidence, so no step is a placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.DevelopmentCommands.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.DevelopmentCommands.UnitAdapter, as: Unit
  alias BnestApp.Behaviour.IntegrationHomePageDriver

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  # The hooks install the web drivers, not the commands adapter: the first
  # commands step of a scenario installs it, later steps reuse the state.
  defp commands(context) do
    if Map.has_key?(context, :commands), do: context, else: adapter(context).install(context)
  end

  # Each server keeps to its own loopback port range (BN-DOC-05).

  step(
    "the {string} server is allocated loopback ports {int} to {int}",
    %{args: [server, first, last]} = context
  ) do
    context = commands(context)
    adapter(context).allocate_server(context, server, first, last)
  end

  step("the configured port for {string} is {int}", %{args: [server, port]} = context) do
    context = commands(context)
    adapter(context).configured_port(context, server, port)
  end

  step("the port stays inside its range and the server binds loopback", context) do
    context = commands(context)
    adapter(context).assert_port_binding(context)
  end

  # npm start serves the development app on its loopback port (BN-CLI-01,
  # BN-CFG-02).

  step("BNEST_DEV_PORT is {string}", %{args: [value]} = context) do
    context = commands(context)
    adapter(context).dev_port(context, value)
  end

  step("the start command is rendered", context) do
    context = commands(context)
    adapter(context).render_start(context)
  end

  step(
    "the HIPPO lease requests port {int} for owner development from {int} to {int}",
    %{args: [port, min, max]} = context
  ) do
    context = commands(context)
    adapter(context).assert_lease(context, port, min, max)
  end

  step("the dev endpoint binds {string} on port {int}", %{args: [bind, port]} = context) do
    context = commands(context)
    adapter(context).assert_endpoint(context, port, bind)
  end

  # Each npm test command runs its Nx target under a HIPPO admission
  # (BN-CLI-02, BN-CLI-03).

  step("the root script {string} runs the chain {string}", %{args: [script, chain]} = context) do
    context = commands(context)
    adapter(context).test_chain(context, script, chain)
  end

  step("the chain runs with {string} failing", %{args: [failing]} = context) do
    context = commands(context)
    adapter(context).run_chain_with(context, failing)
  end

  step("the targets after the failure never run", context) do
    context = commands(context)
    adapter(context).assert_chain(context)
  end

  step("the {string} script admits {string}", %{args: [script, admission]} = context) do
    context = commands(context)
    adapter(context).assert_admission(context, script, admission)
  end

  # The tailnet commands drive Tailscale Serve for the Caddy port (BN-CLI-04).

  step("the bnest-app target {string} declares {string}", %{args: [target, command]} = context) do
    context = commands(context)
    adapter(context).declare_tailnet(context, target, command)
  end

  step("the target runs with a recording tailscale double", context) do
    context = commands(context)
    adapter(context).run_tailnet(context)
  end

  step(
    "the double records {string} and the target exits with the double",
    %{args: [command]} = context
  ) do
    context = commands(context)
    adapter(context).assert_tailnet(context, command)
  end

  # Each Nx target runs the checks it names, in order (BN-CLI-27, BN-GATE-08).

  step(
    "the bnest-app target {string} declares {string} with dependsOn {string} and parallel {string}",
    %{args: [target, commands, depends, parallel]} = context
  ) do
    context = commands(context)
    adapter(context).declare_target(context, target, commands, depends, parallel)
  end

  step("the target definition is read back", context) do
    context = commands(context)
    adapter(context).read_target(context)
  end

  step("it runs its commands in order", context) do
    context = commands(context)
    adapter(context).assert_order(context)
  end
end
