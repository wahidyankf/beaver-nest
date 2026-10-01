defmodule BnestApp.Test.InterruptedChatWriteBackend do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # A record backend over a real store whose first chat write fails, as an import interrupted
  # after preserving its envelope would; every other operation reaches the store unchanged.

  @behaviour BnestApp.Storage.Ports.RecordBackend

  alias BnestApp.Storage.Ports.RecordBackend

  @spec wrap(RecordBackend.state()) :: RecordBackend.state()
  def wrap(store) do
    {:ok, interruptions} = Agent.start_link(fn -> 1 end)
    %{backend: __MODULE__, store: store, interruptions: interruptions}
  end

  @impl true
  def read(state, type, identity), do: RecordBackend.read(state.store, type, identity)

  @impl true
  def write(state, :chat, identity, revision, candidate) do
    if Agent.get_and_update(state.interruptions, &{&1 > 0, max(&1 - 1, 0)}),
      do: {:error, :interrupted},
      else: RecordBackend.write(state.store, :chat, identity, revision, candidate)
  end

  def write(state, type, identity, revision, candidate),
    do: RecordBackend.write(state.store, type, identity, revision, candidate)

  @impl true
  def put_new(state, type, identity, candidate),
    do: RecordBackend.put_new(state.store, type, identity, candidate)

  @impl true
  def replace(state, type, identity, candidate),
    do: RecordBackend.replace(state.store, type, identity, candidate)

  @impl true
  def remove_exact(state, type, identity, expected),
    do: RecordBackend.remove_exact(state.store, type, identity, expected)
end
