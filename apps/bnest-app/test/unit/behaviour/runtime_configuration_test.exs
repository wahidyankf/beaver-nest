defmodule BnestApp.Behaviour.RuntimeConfigurationTest do
  @moduledoc """
  Unit tests for the runtime_configuration.feature model and adapter.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.RuntimeConfiguration.UnitAdapter, as: Adapter
  alias BnestApp.Behaviour.RuntimeConfigurationModel, as: Model
  alias BnestApp.RuntimeSettings

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: PORT sets the HTTP port and PHX_SERVER makes the release serve
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: PHX_SERVER makes the release serve
  test "port and server flag come from the environment" do
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

    assert RuntimeSettings.http_port(%{}) == 4000
    assert RuntimeSettings.http_port(%{"PORT" => "4101"}) == 4101
    assert RuntimeSettings.http_port(%{"PORT" => ""}) == 4000
    assert RuntimeSettings.server_enabled?(%{}) == false
    assert RuntimeSettings.server_enabled?(%{"PHX_SERVER" => "true"}) == true
    assert RuntimeSettings.server_enabled?(%{"PHX_SERVER" => ""}) == true
    assert is_map(RuntimeSettings.system_env())
    assert RuntimeSettings.dns_cluster_query(%{}) == nil
    assert RuntimeSettings.dns_cluster_child(nil) == {DNSCluster, [query: :ignore]}
    assert RuntimeSettings.fixture_runner?(nil, "f", fn _, _ -> true end) == false
    assert RuntimeSettings.fixture_runner?("", "f", fn _, _ -> true end) == false
    assert Model.port_for("(unset)") == 4000

    assert_raise RuntimeError, "PORT must be a positive integer", fn ->
      RuntimeSettings.http_port(%{"PORT" => "not-a-port"})
    end

    assert RuntimeSettings.runtime_root(%{"BNEST_RUNTIME_ROOT" => ""}) == nil

    assert RuntimeSettings.codex_working_directory(%{"BNEST_CODEX_WORKING_DIRECTORY" => ""}) ==
             nil

    assert RuntimeSettings.codex_home(%{"BNEST_CODEX_HOME" => ""}) == nil
    assert RuntimeSettings.boolean_setting!(%{}, "BNEST_IDENTITY_CUTOVER") == false

    # Committed key fixtures, read by the production settings reader: the test only
    # passes path strings, so it touches neither the file system nor the clock.
    # (`__DIR__` is a compile-time path, and plain string concatenation keeps the
    # unit layer's ban on `Path` and `File` calls intact.)
    key_dir = __DIR__ <> "/fixtures/push-keys"

    assert %{subject: "mailto:ops@example.com"} =
             RuntimeSettings.push_config!(%{
               "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE" => key_dir <> "/public.key",
               "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE" => key_dir <> "/private.key",
               "BNEST_WEB_PUSH_SUBJECT" => "mailto:ops@example.com"
             })
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: Production boot needs SECRET_KEY_BASE and PHX_HOST names the host
  test "production boot names its secret and host" do
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

    assert Model.prod_host("(unset)") == "example.com"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: BNEST_RUNTIME_ROOT moves the flat-file runtime root
  test "runtime root follows its override" do
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
  test "codex directories follow their overrides" do
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
  test "codex runners follow their overrides" do
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
  test "boolean settings accept only true or false" do
    for {name, value, outcome} <- [
          {"BNEST_IDENTITY_CUTOVER", "true", "true"},
          {"BNEST_IDENTITY_CUTOVER", "false", "false"},
          {"BNEST_IDENTITY_CUTOVER", "(unset)", "false"},
          {"BNEST_IDENTITY_CUTOVER", "yes", "BNEST_IDENTITY_CUTOVER must be true or false"},
          {"BNEST_FAMILY_CHAT_ENABLED", "true", "true"},
          {"BNEST_FAMILY_CHAT_ENABLED", "false", "false"},
          {"BNEST_FAMILY_CHAT_ENABLED", "(unset)", "false"},
          {"BNEST_FAMILY_CHAT_ENABLED", "yes", "BNEST_FAMILY_CHAT_ENABLED must be true or false"},
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
