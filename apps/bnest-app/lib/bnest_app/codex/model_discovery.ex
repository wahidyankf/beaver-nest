defmodule BnestApp.Codex.ModelDiscovery do
  @moduledoc false

  # The only place Codex model discovery touches the operating system. It returns raw
  # decoded models and never normalizes or falls back, so `ModelCatalog` keeps exactly one
  # validation path and can be exercised without spawning a Node process.

  @callback discover(keyword()) :: {:ok, list()} | :error

  @spec bundled_models_runner() :: String.t()
  def bundled_models_runner do
    Application.app_dir(:bnest_app, "priv/codex/list_models.mjs")
  end

  @spec discover(keyword()) :: {:ok, list()} | :error
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
