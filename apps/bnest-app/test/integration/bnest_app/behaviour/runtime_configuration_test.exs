defmodule BnestApp.Behaviour.RuntimeConfigurationIntegrationTest do
  @moduledoc """
  Integration tests for the runtime_configuration.feature adapter.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.RuntimeConfiguration.IntegrationAdapter, as: Adapter

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: PORT sets the HTTP port and PHX_SERVER makes the release serve
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: PHX_SERVER makes the release serve
  test "port and server come back from the real runtime config" do
    for {port_value, server_value, port, server} <- [
          {"(unset)", "(unset)", 4000, "off"},
          {"4101", "(unset)", 4101, "off"},
          {"(unset)", "true", 4000, "on"},
          {"4101", "true", 4101, "on"}
        ] do
      context()
      |> Adapter.port_env(port_value, server_value)
      |> Adapter.derive_runtime()
      |> Adapter.assert_port_server(port, server)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: Production boot needs SECRET_KEY_BASE and PHX_HOST names the host
  test "production boot names its secret and host from the real runtime config" do
    for {secret, host, boot, url_host} <- [
          {"(unset)", "(unset)", "environment variable SECRET_KEY_BASE is missing.",
           "example.com"},
          {"secret-1", "family.example", "ok", "family.example"},
          {"secret-1", "(unset)", "ok", "example.com"}
        ] do
      context()
      |> Adapter.prod_env(secret, host)
      |> Adapter.derive_prod()
      |> Adapter.assert_prod(boot, url_host)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: BNEST_RUNTIME_ROOT moves the flat-file runtime root
  test "runtime root moves and holds a record" do
    for {raw, cwd, resolved} <- [
          {"(unset)", "/srv/bnest", "(default)"},
          {"/data/other", "/srv/bnest", "/data/other"},
          {"relative", "/srv/bnest", "/srv/bnest/relative"}
        ] do
      context()
      |> Adapter.root_env(raw)
      |> Adapter.derive_root(cwd)
      |> Adapter.assert_root(resolved)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: The Codex working directory and Codex home follow BNEST_CODEX_WORKING_DIRECTORY and BNEST_CODEX_HOME
  test "codex dirs serve repo and generated images from a temp dir" do
    for {working_raw, home_raw, working, home} <- [
          {"(unset)", "(unset)", "(default)", "(default)"},
          {"/repo/other", "/home/other", "/repo/other", "/home/other"}
        ] do
      context()
      |> Adapter.codex_env(working_raw, home_raw)
      |> Adapter.derive_codex()
      |> Adapter.assert_codex(working, home)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: BNEST_CODEX_RUNNER and BNEST_CODEX_MODELS_RUNNER choose the chat and model-discovery runners
  test "runners resolve and discovery runs the fixture" do
    for {runner, models_runner, chat, models, session} <- [
          {"(unset)", "(unset)", "(bundled)", "(bundled)", "fixture"},
          {"/bin/other", "/bin/models-other", "/bin/other", "/bin/models-other", "fixture"},
          {"(fixture)", "(fixture)", "(fixture)", "(fixture)", "real"}
        ] do
      context()
      |> Adapter.runner_env(runner, models_runner)
      |> Adapter.derive_runners()
      |> Adapter.assert_runners(chat, models, session)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: A boolean setting accepts only true or false and otherwise stops the boot
  test "boolean settings stop the boot from the real runtime config" do
    for {name, value, outcome} <- [
          {"BNEST_IDENTITY_CUTOVER", "true", "true"},
          {"BNEST_IDENTITY_CUTOVER", "false", "false"},
          {"BNEST_IDENTITY_CUTOVER", "(unset)", "false"},
          {"BNEST_IDENTITY_CUTOVER", "yes", "BNEST_IDENTITY_CUTOVER must be true or false"},
          {"BNEST_COOKIE_SECURE", "true", "true"},
          {"BNEST_COOKIE_SECURE", "false", "false"},
          {"BNEST_COOKIE_SECURE", "(unset)", "false"},
          {"BNEST_COOKIE_SECURE", "yes", "BNEST_COOKIE_SECURE must be true or false"}
        ] do
      context()
      |> Adapter.boolean_env(name, value)
      |> Adapter.derive_boolean()
      |> Adapter.assert_boolean(outcome)
    end
  end
end
