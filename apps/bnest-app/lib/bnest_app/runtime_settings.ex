defmodule BnestApp.RuntimeSettings do
  @moduledoc """
  The Runtime Settings bounded context: pure release configuration over an
  environment map.

  This module is the context's facade. Every setting parses from a plain
  `%{"NAME" => value}` map, so unit tests drive every row over doubles while
  `config/runtime.exs` passes the deployment snapshot. The operating-system
  reads live behind the `Adapters` seam
  (`BnestApp.RuntimeSettings.Adapters.SystemEnvironment`, over `System` for
  the snapshot and `File` for the push key files), keeping effects in the
  adapters as the hexagonal layers require; this facade names no effect
  module directly.

  Reason for extraction: testability without widening the unit boundary;
  `runtime.exs` remains the single writer of application config.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [],
    exports: []

  alias BnestApp.RuntimeSettings.Adapters.SystemEnvironment

  @type env :: %{optional(String.t()) => String.t() | nil}

  @doc "Reads the deployment environment into a plain map (release seam only)."
  def system_env, do: SystemEnvironment.snapshot()

  @doc """
  The HTTP port: `PORT` or 4000 when unset. Any other value goes through
  `String.to_integer/1`, so a non-integer raises ArgumentError.
  """
  def http_port(env) do
    case Map.get(env, "PORT") do
      nil -> 4000
      raw -> String.to_integer(raw)
    end
  end

  @doc "True when `PHX_SERVER` is set (any value, as `System.get_env/1` is truthy)."
  def server_enabled?(env), do: Map.get(env, "PHX_SERVER") != nil

  @doc "The secret key base, raising with the reviewed message when missing."
  def secret_key_base!(env) do
    Map.get(env, "SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """
  end

  @doc "The production host: `PHX_HOST` or `example.com`."
  def phx_host(env), do: Map.get(env, "PHX_HOST") || "example.com"

  @doc "The DNS cluster query, or nil when unset."
  def dns_cluster_query(env), do: Map.get(env, "DNS_CLUSTER_QUERY")

  @doc """
  The flat-file runtime root: nil when unset (keep the compiled default),
  otherwise expanded with `expand` (defaults to `Path.expand/1` so relative
  values resolve against the working directory).
  """
  def runtime_root(env, expand \\ &Path.expand/1) do
    case Map.get(env, "BNEST_RUNTIME_ROOT") do
      nil -> nil
      raw -> expand.(raw)
    end
  end

  @doc "The Codex working directory override, expanded, or nil when unset."
  def codex_working_directory(env, expand \\ &Path.expand/1) do
    case Map.get(env, "BNEST_CODEX_WORKING_DIRECTORY") do
      nil -> nil
      raw -> expand.(raw)
    end
  end

  @doc "The Codex home override, expanded, or nil when unset."
  def codex_home(env, expand \\ &Path.expand/1) do
    case Map.get(env, "BNEST_CODEX_HOME") do
      nil -> nil
      raw -> expand.(raw)
    end
  end

  @doc "Parses a boolean setting: true/false, false when unset, else raises."
  def boolean_setting!(env, name, default \\ false) do
    case Map.get(env, name) do
      nil -> default
      "true" -> true
      "false" -> false
      _invalid -> raise "#{name} must be true or false"
    end
  end

  @doc "The chat runner: `BNEST_CODEX_RUNNER` or the bundled runner."
  def codex_runner(env, bundled), do: Map.get(env, "BNEST_CODEX_RUNNER") || bundled

  @doc "The model-discovery runner: `BNEST_CODEX_MODELS_RUNNER` or the bundled one."
  def codex_models_runner(env, bundled), do: Map.get(env, "BNEST_CODEX_MODELS_RUNNER") || bundled

  @doc """
  True when the test profile selects the real port session: the runner names
  the bundled fixture file by identity. Any other value, an empty or missing
  path, or a real Codex runner fails closed to the fixture session.
  `same_file?` compares identities (inode/device); production passes a
  `File.stat/1` comparison, unit passes a double.
  """
  def fixture_runner?(runner_value, fixture_path, same_file?) do
    case runner_value do
      nil -> false
      "" -> false
      runner -> same_file?.(runner, fixture_path)
    end
  end

  @doc """
  Validates the production push configuration over an env map and a
  `read!` double. Returns `%{public_key, private_key, subject}` trimmed,
  raising each reviewed named message. The release does not boot on any
  refusal.
  """
  def push_config!(env, read! \\ &SystemEnvironment.read!/1) do
    public_key_path =
      Map.get(env, "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE") ||
        raise "environment variable BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE is missing"

    private_key_path =
      Map.get(env, "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE") ||
        raise "environment variable BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE is missing"

    subject =
      Map.get(env, "BNEST_WEB_PUSH_SUBJECT") ||
        raise "environment variable BNEST_WEB_PUSH_SUBJECT is missing"

    unless subject =~ ~r/^(mailto:|https:\/\/)\S+$/ do
      raise "BNEST_WEB_PUSH_SUBJECT must be a mailto: or https: contact"
    end

    public_key = read!.(public_key_path) |> String.trim()
    private_key = read!.(private_key_path) |> String.trim()

    if public_key == "" or private_key == "" do
      raise "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE/BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must not be empty"
    end

    %{public_key: public_key, private_key: private_key, subject: subject}
  end

  @doc "True when stable mode turns off code reload and asset watchers."
  def stable_mode?(env), do: Map.get(env, "BNEST_STABLE") == "true"

  @doc """
  The application child spec for the DNS cluster query: `{DNSCluster, query}`
  when set, `{DNSCluster, query: :ignore}` when unset.
  """
  def dns_cluster_child(query) when is_binary(query), do: {DNSCluster, [query: query]}
  def dns_cluster_child(_unset), do: {DNSCluster, [query: :ignore]}
end
