defmodule BnestApp.Behaviour.RuntimeConfigurationSteps do
  @moduledoc """
  Bindings for runtime_configuration.feature.

  Each step delegates to the layer adapter. A Given or When records what it
  observed, and a Then asserts that recorded evidence.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.IntegrationHomePageDriver
  alias BnestApp.Behaviour.RuntimeConfiguration.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.RuntimeConfiguration.UnitAdapter, as: Unit

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  defp runtime(context) do
    if Map.has_key?(context, :runtime), do: context, else: adapter(context).install(context)
  end

  step(
    "PORT is {string} and PHX_SERVER is {string}",
    %{args: [port_value, server_value]} = context
  ) do
    context = runtime(context)
    adapter(context).port_env(context, port_value, server_value)
  end

  step("the runtime settings are derived", context) do
    context = runtime(context)
    adapter(context).derive_runtime(context)
  end

  step("the HTTP port is {int} and the server is {string}", %{args: [port, server]} = context) do
    context = runtime(context)
    adapter(context).assert_port_server(context, port, server)
  end

  step(
    "SECRET_KEY_BASE is {string} and PHX_HOST is {string}",
    %{args: [secret, host]} = context
  ) do
    context = runtime(context)
    adapter(context).prod_env(context, secret, host)
  end

  step("the production endpoint is derived", context) do
    context = runtime(context)
    adapter(context).derive_prod(context)
  end

  step(
    "the production boot is {string} with URL host {string} on 443 and loopback bind",
    %{args: [boot, url_host]} = context
  ) do
    context = runtime(context)
    adapter(context).assert_prod(context, boot, url_host)
  end

  step("BNEST_RUNTIME_ROOT is {string}", %{args: [raw]} = context) do
    context = runtime(context)
    adapter(context).root_env(context, raw)
  end

  step("the runtime root is derived with {string}", %{args: [cwd]} = context) do
    context = runtime(context)
    adapter(context).derive_root(context, cwd)
  end

  step("the runtime root is {string}", %{args: [resolved]} = context) do
    context = runtime(context)
    adapter(context).assert_root(context, resolved)
  end

  step(
    "BNEST_CODEX_WORKING_DIRECTORY is {string} and BNEST_CODEX_HOME is {string}",
    %{args: [working_raw, home_raw]} = context
  ) do
    context = runtime(context)
    adapter(context).codex_env(context, working_raw, home_raw)
  end

  step("the Codex directories are derived", context) do
    context = runtime(context)
    adapter(context).derive_codex(context)
  end

  step(
    "the working directory is {string} and the Codex home is {string} and repo images come from the working directory and generated images from the home",
    %{args: [working, home]} = context
  ) do
    context = runtime(context)
    adapter(context).assert_codex(context, working, home)
  end

  step(
    "BNEST_CODEX_RUNNER is {string} and BNEST_CODEX_MODELS_RUNNER is {string}",
    %{args: [runner, models_runner]} = context
  ) do
    context = runtime(context)
    adapter(context).runner_env(context, runner, models_runner)
  end

  step("the Codex runners are derived", context) do
    context = runtime(context)
    adapter(context).derive_runners(context)
  end

  step(
    "the chat runner is {string} and the models runner is {string} and the test profile selects {string}",
    %{args: [chat, models, session]} = context
  ) do
    context = runtime(context)
    adapter(context).assert_runners(context, chat, models, session)
  end

  step("boolean setting {string} is {string}", %{args: [name, value]} = context) do
    context = runtime(context)
    adapter(context).boolean_env(context, name, value)
  end

  step("the boolean setting is derived", context) do
    context = runtime(context)
    adapter(context).derive_boolean(context)
  end

  step("the boolean outcome is {string}", %{args: [outcome]} = context) do
    context = runtime(context)
    adapter(context).assert_boolean(context, outcome)
  end
end
