defmodule BnestApp.Test.InMemory.FailingTranscriptStore do
  @moduledoc """
  A `BnestApp.CodexChat.Ports.TranscriptStore` double that refuses writes on demand.
  Reads come from the snapshot a scenario installs, so a refused save leaves exactly
  what the server held before. The refusal mode comes from the application
  environment, so a scenario flips reads and writes without touching the filesystem:

    * `:refused` — every write answers `{:error, :refused}`;
    * `:stale` — every write answers `{:error, :stale}`;
    * any other value — the write follows the port's optimistic revision rule.
  """

  @behaviour BnestApp.CodexChat.Ports.TranscriptStore

  @doc "Starts a fresh store holding `records` under the calling test's supervisor."
  def install(records \\ %{}) do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> records end, [name: __MODULE__]]}
    })

    :ok
  end

  @doc "Every stored chat record, keyed by owner."
  def snapshot, do: Agent.get(__MODULE__, & &1)

  @doc "A handle the `CodexChat` facade reads through the configured adapter."
  @impl true
  def new, do: %{adapter: __MODULE__, pid: __MODULE__}

  @impl true
  def read(%{pid: _pid}, owner_id) do
    case Agent.get(__MODULE__, &Map.fetch(&1, owner_id)) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  @impl true
  def write(%{pid: _pid}, owner_id, expected_revision, record) do
    case Application.get_env(:bnest_app, :transcript_write_outcome, :ok) do
      :refused -> {:error, :refused}
      :stale -> {:error, :stale}
      _write -> apply_write(owner_id, expected_revision, record)
    end
  end

  defp apply_write(owner_id, expected_revision, record) do
    Agent.get_and_update(__MODULE__, fn records ->
      actual_revision =
        case Map.fetch(records, owner_id) do
          {:ok, existing} -> existing["revision"]
          :error -> nil
        end

      if actual_revision == expected_revision do
        stored = Map.put(record, "revision", (actual_revision || -1) + 1)
        {{:ok, stored}, Map.put(records, owner_id, stored)}
      else
        {{:error, :stale}, records}
      end
    end)
  end
end
