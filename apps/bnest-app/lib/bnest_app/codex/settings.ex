defmodule BnestApp.Codex.Settings do
  @moduledoc false

  @model "gpt-5.6-terra"
  @reasoning_effort "medium"

  @spec preferred_model() :: String.t()
  def preferred_model, do: @model

  @spec preferred_reasoning_effort() :: String.t()
  def preferred_reasoning_effort, do: @reasoning_effort

  @spec label(String.t(), String.t()) :: String.t()
  def label(display_name, reasoning_effort) do
    "#{String.replace_prefix(display_name, "GPT-5.6-", "")} · #{reasoning_effort}"
  end
end
