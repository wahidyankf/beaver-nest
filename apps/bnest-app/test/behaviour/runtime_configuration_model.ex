defmodule BnestApp.Behaviour.RuntimeConfigurationModel do
  @moduledoc """
  Shared expectations for runtime_configuration.feature.

  Both layers drive scenarios through this model. The unit adapter feeds it
  the scenario data over pure doubles; the integration adapter feeds it values
  read back from the real config files with Config.Reader.
  """

  alias BnestApp.RuntimeSettings

  @loopback {127, 0, 0, 1}
  @default_port 4000
  @default_host "example.com"

  def loopback_tuple, do: @loopback
  def default_port, do: @default_port
  def default_host, do: @default_host

  def port_for("(unset)"), do: @default_port
  def port_for(""), do: @default_port
  def port_for(raw) when is_binary(raw), do: RuntimeSettings.http_port(%{"PORT" => raw})

  def server_for("(unset)"), do: false
  def server_for(""), do: false
  def server_for(_set), do: true

  def prod_boot("(unset)", _host) do
    {:error, "environment variable SECRET_KEY_BASE is missing."}
  end

  def prod_boot(_secret, "(unset)"), do: {:ok, @default_host}
  def prod_boot(_secret, ""), do: {:ok, @default_host}
  def prod_boot(_secret, host), do: {:ok, host}

  def prod_host("(unset)"), do: @default_host
  def prod_host(""), do: @default_host
  def prod_host(host), do: host

  def runtime_expected("(unset)", _cwd, _expand), do: :default
  def runtime_expected("", _cwd, _expand), do: :default

  def runtime_expected(raw, cwd, expand) when is_binary(raw) do
    if relative?(raw), do: expand.(cwd <> "/" <> raw), else: expand.(raw)
  end

  defp relative?(""), do: false
  defp relative?(raw), do: not String.starts_with?(raw, "/")

  def codex_expected("(unset)"), do: :default
  def codex_expected(""), do: :default
  def codex_expected(raw), do: {:expanded, raw}

  def chat_expected("(unset)"), do: :bundled
  def chat_expected("(fixture)"), do: :fixture
  def chat_expected(raw), do: {:path, raw}

  def models_expected("(unset)"), do: :bundled
  def models_expected("(fixture)"), do: :fixture
  def models_expected(raw), do: {:path, raw}

  def session_for("(fixture)", "(fixture)"), do: :real
  def session_for(_runner, _models), do: :fixture

  def boolean_default("BNEST_IDENTITY_CUTOVER"), do: false
  def boolean_default("BNEST_COOKIE_SECURE"), do: false

  def boolean_for(_name, "(unset)"), do: {:ok, false}
  def boolean_for(_name, ""), do: {:ok, false}
  def boolean_for(_name, "true"), do: {:ok, true}
  def boolean_for(_name, "false"), do: {:ok, false}

  def boolean_for(name, _invalid), do: {:error, name <> " must be true or false"}
end
