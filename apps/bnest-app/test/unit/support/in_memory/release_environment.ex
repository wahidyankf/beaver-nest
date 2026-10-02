defmodule BnestApp.Test.InMemory.ReleaseEnvironment do
  @moduledoc """
  An Agent-backed `BnestApp.Operations.Ports.ReleaseEnvironment`. The deployment named no
  revision, slot or peer unless a test says otherwise, and no peer is ever dialled: a named
  peer answers as the test said. It reads no operating-system environment variable, so the
  unit layer cannot see the deployment's.

  A process counts as running while it is registered locally, as in the system adapter,
  unless a test pinned it with `put_running/3`, so a scenario's real Records, Identity and
  model catalog processes decide readiness.

  The unit layer configures this module as Operations' `:release_environment`; its `new/0`
  serves the environment a test started with `install/0`, which the test supervisor stops
  before the next test. `pinged/1` reports every peer readiness tried, oldest first.
  """

  @behaviour BnestApp.Operations.Ports.ReleaseEnvironment

  @doc """
  Starts a fresh environment under the calling test's supervisor as the one `new/0` serves,
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
              "no in-memory release environment is installed; call " <>
                "#{inspect(__MODULE__)}.install/0 in the test before reaching BnestApp.Operations"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Names the released revision."
  def put_revision(%{pid: pid}, revision), do: Agent.update(pid, &%{&1 | revision: revision})

  @doc "Names the deployment slot."
  def put_slot(%{pid: pid}, slot), do: Agent.update(pid, &%{&1 | slot: slot})

  @doc "Names the peer slot's node, and whether it answers a ping."
  def put_peer(%{pid: pid}, peer, reachable?),
    do: Agent.update(pid, &%{&1 | peer: peer, peer_reachable?: reachable?})

  @doc "Pins whether the process registered under `name` counts as running."
  def put_running(%{pid: pid}, name, running?),
    do: Agent.update(pid, &put_in(&1.running[name], running?))

  @doc "Every peer readiness pinged, oldest first."
  def pinged(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.pinged))

  @impl true
  def revision(%{pid: pid}), do: Agent.get(pid, & &1.revision)

  @impl true
  def slot(%{pid: pid}), do: Agent.get(pid, & &1.slot)

  @impl true
  def peer(%{pid: pid}), do: Agent.get(pid, & &1.peer)

  @impl true
  def running?(%{pid: pid}, name) do
    case Agent.get(pid, &Map.fetch(&1.running, name)) do
      {:ok, running?} -> running?
      :error -> GenServer.whereis(name) != nil
    end
  end

  @impl true
  def peer_reachable?(%{pid: pid}, peer) do
    Agent.get_and_update(pid, fn state ->
      {state.peer_reachable?, %{state | pinged: [peer | state.pinged]}}
    end)
  end

  defp empty,
    do: %{
      revision: nil,
      slot: nil,
      peer: nil,
      peer_reachable?: false,
      running: %{},
      pinged: []
    }
end
