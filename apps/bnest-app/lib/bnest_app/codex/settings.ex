defmodule BnestApp.Codex.Settings do
  @moduledoc false

  @model "gpt-5.6-terra"
  @reasoning_effort "medium"
  @label "Terra · medium"

  @spec model() :: String.t()
  def model, do: @model

  @spec reasoning_effort() :: String.t()
  def reasoning_effort, do: @reasoning_effort

  @spec label() :: String.t()
  def label, do: @label
end
