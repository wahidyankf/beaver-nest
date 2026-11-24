defmodule BnestApp.RuntimeSettings.Adapters.SystemEnvironment do
  @moduledoc """
  Runtime Settings' system seam: the deployment environment snapshot and the
  release file reads.

  `snapshot/0` reads the deployment variables `BnestApp.RuntimeSettings`
  parses through `System`, omitting the unset ones. `read!/1` reads one
  release file through `File`, raising as `File.read!/1` does. Only the
  `BnestApp.RuntimeSettings` facade names this module; callers that must not
  touch the operating system inject doubles through the facade's arguments
  instead.
  """

  @variables [
    "PORT",
    "PHX_SERVER",
    "SECRET_KEY_BASE",
    "PHX_HOST",
    "BNEST_RUNTIME_ROOT",
    "BNEST_CODEX_WORKING_DIRECTORY",
    "BNEST_CODEX_HOME",
    "BNEST_CODEX_RUNNER",
    "BNEST_CODEX_MODELS_RUNNER",
    "BNEST_IDENTITY_CUTOVER",
    "BNEST_FAMILY_CHAT_ENABLED",
    "BNEST_FAMILY_CHAT_REPLY_ENABLED",
    "BNEST_COOKIE_SECURE",
    "BNEST_BACKUP_TIMEOUT_MS",
    "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE",
    "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE",
    "BNEST_WEB_PUSH_SUBJECT",
    "DNS_CLUSTER_QUERY",
    "BNEST_DEPLOY_PEER",
    "BNEST_STABLE"
  ]

  @doc "Snapshots every set deployment variable `BnestApp.RuntimeSettings` parses."
  @spec snapshot() :: %{optional(String.t()) => String.t()}
  def snapshot do
    for name <- @variables,
        value = System.get_env(name),
        value != nil,
        into: %{},
        do: {name, value}
  end

  @doc "Reads one release file, raising as `File.read!/1` does."
  @spec read!(Path.t()) :: binary()
  def read!(path), do: File.read!(path)
end
