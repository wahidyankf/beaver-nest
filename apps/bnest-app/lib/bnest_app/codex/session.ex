defmodule BnestApp.Codex.Session do
  @moduledoc false

  @callback open(pid(), String.t() | nil, String.t(), String.t()) ::
              {:ok, term()} | {:error, term()}
  @callback send_prompt(term(), String.t()) :: :ok | {:error, term()}
  @callback close(term()) :: :ok
end
