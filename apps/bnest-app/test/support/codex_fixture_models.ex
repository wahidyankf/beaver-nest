defmodule BnestApp.Codex.FixtureModels do
  @moduledoc false

  @models [
    %{id: "gpt-5.6-sol", display_name: "GPT-5.6-Sol", default_reasoning_effort: "low"},
    %{
      id: "gpt-5.6-terra",
      display_name: "GPT-5.6-Terra",
      default_reasoning_effort: "medium"
    },
    %{
      id: "gpt-5.6-luna",
      display_name: "GPT-5.6-Luna",
      default_reasoning_effort: "medium"
    },
    %{id: "gpt-5.5", display_name: "GPT-5.5", default_reasoning_effort: "medium"},
    %{id: "gpt-5.4", display_name: "GPT-5.4", default_reasoning_effort: "medium"},
    %{
      id: "gpt-5.4-mini",
      display_name: "GPT-5.4-Mini",
      default_reasoning_effort: "medium"
    },
    %{
      id: "gpt-5.3-codex-spark",
      display_name: "GPT-5.3-Codex-Spark",
      default_reasoning_effort: "high"
    }
  ]

  def all do
    Enum.map(@models, fn model ->
      model
      |> Map.put(:supported_reasoning_efforts, ~w(low medium high xhigh max ultra))
      |> Map.put(:is_default, model.id == "gpt-5.6-sol")
    end)
  end

  def display_names, do: Enum.map(@models, & &1.display_name)

  def fetch_by_display_name!(display_name) do
    Enum.find(@models, &(&1.display_name == display_name)) ||
      raise ArgumentError, "unknown fixture model: #{inspect(display_name)}"
  end
end
