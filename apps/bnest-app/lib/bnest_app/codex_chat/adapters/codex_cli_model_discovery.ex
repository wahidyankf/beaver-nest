defmodule BnestApp.CodexChat.Adapters.CodexCliModelDiscovery do
  @moduledoc """
  The `BnestApp.CodexChat.Ports.ModelDiscovery` over the local Codex CLI: it runs the bundled
  Node models runner in the configured working directory and decodes its output. It is the
  only place model discovery touches the operating system.
  """

  @behaviour BnestApp.CodexChat.Ports.ModelDiscovery

  @spec bundled_models_runner() :: String.t()
  def bundled_models_runner do
    Application.app_dir(:bnest_app, "priv/codex/list_models.mjs")
  end

  @impl true
  def discover(options) do
    config = Application.fetch_env!(:bnest_app, :codex)

    runner =
      Keyword.get(options, :models_runner) || System.get_env("BNEST_CODEX_MODELS_RUNNER") ||
        Keyword.get(config, :models_runner, bundled_models_runner())

    working_directory =
      Keyword.get(options, :working_directory, Keyword.fetch!(config, :working_directory))

    executable = Keyword.get_lazy(options, :node, fn -> System.find_executable("node") end)

    with executable when is_binary(executable) <- executable,
         {output, 0} <-
           System.cmd(executable, [runner],
             cd: working_directory,
             stderr_to_stdout: true
           ),
         {:ok, models} <- Jason.decode(output) do
      {:ok, models}
    else
      _reason -> :error
    end
  end
end
