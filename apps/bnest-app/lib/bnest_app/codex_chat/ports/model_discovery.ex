defmodule BnestApp.CodexChat.Ports.ModelDiscovery do
  @moduledoc """
  Lists the models the local Codex agent offers.

  An implementation returns the raw decoded models and never normalizes or falls back, so
  `BnestApp.CodexChat.ModelCatalog` keeps exactly one validation path.
  """

  @callback discover(keyword()) :: {:ok, list()} | :error
end
