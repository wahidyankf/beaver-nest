defmodule BnestApp.Test.InMemory.ProgressStore do
  @moduledoc """
  An Agent-backed `BnestApp.SifatAllah.Ports.ProgressStore`. It keeps the port's optimistic
  revision semantics, as Storage's record backends do, without schema validation. Each
  handle owns its own agent, so tests that start their own stores may run concurrently.
  """

  @behaviour BnestApp.SifatAllah.Ports.ProgressStore

  @doc "A fresh, empty store linked to the calling test."
  def start do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{adapter: __MODULE__, pid: pid}
  end

  @doc "Every stored progress record, keyed by owner."
  def snapshot(%{pid: pid}), do: Agent.get(pid, & &1)

  # The in-memory store has no records the running application serves, so it must never be
  # configured as the `:progress_store` adapter; tests pass a started handle as `store:`.
  @dialyzer {:nowarn_function, new: 0}
  @impl true
  def new do
    raise ArgumentError,
          "#{inspect(__MODULE__)} serves no application records; start/0 a store and pass " <>
            "its handle as the SifatAllah `store:` option instead of configuring it as the " <>
            ":progress_store adapter"
  end

  @impl true
  def read(%{pid: pid}, owner_id) do
    case Agent.get(pid, &Map.fetch(&1, owner_id)) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  @impl true
  def write(%{pid: pid}, owner_id, expected_revision, record) do
    Agent.get_and_update(pid, fn records ->
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
