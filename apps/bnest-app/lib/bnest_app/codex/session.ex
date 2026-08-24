defmodule BnestApp.Codex.Session do
  @moduledoc false

  @callback open(pid()) :: {:ok, term()} | {:error, term()}
  @callback send_prompt(term(), String.t()) :: :ok | {:error, term()}
  @callback close(term()) :: :ok
end
