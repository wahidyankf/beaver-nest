defmodule BnestApp.Test.CodexFixtureModels do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # The test configuration's model discovery: it offers this fixed catalog without running
  # the Codex CLI. It is the local Codex model list (`codex app-server model/list`) as read on the
  # development machine, so the picker's filtering runs on the real ids, display names and efforts.
  @behaviour BnestApp.CodexChat.Ports.ModelDiscovery

  @models [
    %{
      id: "gpt-6.1-sol",
      display_name: "GPT-6.1-Sol",
      default_reasoning_effort: "low",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-6-astra",
      display_name: "GPT-6-Astra",
      default_reasoning_effort: "low",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-6.1-terra",
      display_name: "GPT-6.1 Terra",
      default_reasoning_effort: "low",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-6-sol",
      display_name: "GPT-6-Sol",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-6-luna",
      display_name: "GPT-6-Luna",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ~w(low medium high xhigh max)
    },
    %{
      id: "gpt-5.6-sol",
      display_name: "GPT-5.6-Sol",
      default_reasoning_effort: "low",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-5.6-terra",
      display_name: "GPT-5.6-Terra",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra)
    },
    %{
      id: "gpt-5.6-luna",
      display_name: "GPT-5.6-Luna",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ~w(low medium high xhigh max)
    }
  ]

  def all do
    Enum.map(@models, fn model ->
      model
      |> Map.put(:is_default, model.id == "gpt-6.1-sol")
    end)
  end

  @impl true
  def discover(_options), do: {:ok, all()}

  def fetch_by_display_name!(display_name) do
    Enum.find(@models, &(&1.display_name == display_name)) ||
      raise ArgumentError, "unknown fixture model: #{inspect(display_name)}"
  end

  def fetch_by_id!(id) do
    Enum.find(@models, &(&1.id == id)) ||
      raise ArgumentError, "unknown fixture model: #{inspect(id)}"
  end
end
