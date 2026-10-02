defmodule BnestApp.Test.InMemory.CapacityProbe do
  @moduledoc """
  An Agent-backed `BnestApp.Backup.Ports.CapacityProbe`: a fixed measured source size and
  a destination with ample free space unless a test says otherwise. It reaches no disk.

  The unit layer configures this module as Backup's `:capacity_probe`; its `new/0` serves
  the probe a test started with `install/0`, which the test supervisor stops before the
  next test. `put_available_bytes/2` and `put_unmeasurable/1` set the destination's free
  space; `measured/1` reports every directory measured.
  """

  @behaviour BnestApp.Backup.Ports.CapacityProbe

  @source %{page_count: 64, page_size: 4096, wal_bytes: 8192}
  @ample_bytes 1024 * 1024 * 1024 * 1024

  @doc """
  Starts a fresh probe under the calling test's supervisor as the one `new/0` serves,
  replacing one this test installed before, and returns its handle.
  """
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [&empty/0, [name: __MODULE__]]}
    })

    new()
  end

  @impl true
  def new do
    case GenServer.whereis(__MODULE__) do
      nil ->
        raise ArgumentError,
              "no in-memory capacity probe is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.Backup"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "What the probe measures now, or nil when it cannot measure."
  def measurement(%{pid: pid}), do: Agent.get(pid, & &1.measurement)

  @doc "Gives the destination `bytes` of free space."
  def put_available_bytes(%{pid: pid}, bytes),
    do: Agent.update(pid, &%{&1 | measurement: Map.put(@source, :available_bytes, bytes)})

  @doc "Makes the destination's free space unmeasurable."
  def put_unmeasurable(%{pid: pid}), do: Agent.update(pid, &%{&1 | measurement: nil})

  @doc "Every directory measured, oldest first."
  def measured(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.measured))

  @impl true
  def measure(%{pid: pid}, directory) do
    Agent.get_and_update(pid, fn state ->
      result = if state.measurement, do: {:ok, state.measurement}, else: {:error, :unmeasurable}
      {result, %{state | measured: [directory | state.measured]}}
    end)
  end

  defp empty, do: %{measurement: Map.put(@source, :available_bytes, @ample_bytes), measured: []}
end
