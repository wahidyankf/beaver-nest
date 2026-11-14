defmodule BnestApp.CodexChat.Domain.Settings do
  @moduledoc false

  @model "gpt-6.1-terra"
  @reasoning_effort "medium"

  @spec preferred_model() :: String.t()
  def preferred_model, do: @model

  @spec preferred_reasoning_effort() :: String.t()
  def preferred_reasoning_effort, do: @reasoning_effort

  @spec label(String.t(), String.t()) :: String.t()
  def label(display_name, reasoning_effort) do
    "#{tier_name(display_name)} · #{reasoning_effort}"
  end

  # Codex names a model "GPT-6-Luna" or "GPT-6.1 Terra"; the chip shows only the tier name.
  defp tier_name(display_name), do: Regex.replace(~r/\AGPT-\d+(\.\d+)?[ -]/u, display_name, "")

  @spec effort_label(String.t()) :: String.t()
  def effort_label("xhigh"), do: "XHigh"
  def effort_label(reasoning_effort), do: String.capitalize(reasoning_effort)
end
