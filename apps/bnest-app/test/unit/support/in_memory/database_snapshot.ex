defmodule BnestApp.Test.InMemory.DatabaseSnapshot do
  @moduledoc """
  An Agent-backed `BnestApp.Backup.Ports.DatabaseSnapshot` over the unit layer's in-memory
  stand-in for the live database: the `BnestApp.Test.InMemory.RoomStore` the test installed.

  A snapshot copies everything that store holds into `BnestApp.Test.InMemory.ArtifactStore`
  at the partial path it is given, as SQLite's `VACUUM INTO` writes a file; a restore reads
  the copy back out of that artifact store, never out of the live store, so a restore proves
  what the copy holds. It reads back the copy's rows unshaped, bodies and push keys
  included, so what keeps them out of the restore evidence is Backup's own shaping. A copy takes a simulated `copy_ms/0` milliseconds: a timeout shorter
  than that cancels it after it wrote part of the file, as the SQLite snapshot does.

  The unit layer configures this module as Backup's `:database_snapshot`; its `new/0`
  serves the snapshot a test started with `install/0`, which the test supervisor stops
  before the next test. `fail_next/3` makes the next copy or proof fail, and `hold_next_copy/2`
  holds the next copy open until a function of the test's returns, so traffic the test runs
  meanwhile overlaps it; `snapshots/1`, `proofs/1`, `cancellations/1` and `holds/1` report
  what Backup asked of it.
  """

  @behaviour BnestApp.Backup.Ports.DatabaseSnapshot

  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.RoomStore

  @source_path "/srv/test-user-backup/database/bnest.sqlite3"
  @schema_versions [20_260_801_000_000, 20_260_901_000_000]
  @copy_ms 10

  @doc """
  Starts a fresh snapshot under the calling test's supervisor as the one `new/0` serves,
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
              "no in-memory database snapshot is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.Backup"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "How long a simulated copy takes, in milliseconds."
  def copy_ms, do: @copy_ms

  @doc "The schema versions every proof reports."
  def schema_versions(_snapshot), do: @schema_versions

  @doc "Makes the next `operation` (`:vacuum_into` or `:prove`) fail with `reason`."
  def fail_next(%{pid: pid}, operation, reason),
    do: Agent.update(pid, &put_in(&1.failures[operation], reason))

  @doc """
  Holds the next copy open, once it started, until `hold` returns: a copy that takes as long
  as the test's own traffic needs. `hold` runs in the process that runs the backup.
  """
  def hold_next_copy(%{pid: pid}, hold) when is_function(hold, 0),
    do: Agent.update(pid, &%{&1 | hold: hold})

  @doc "What each hold returned once its copy went on, oldest first."
  def holds(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.holds))

  @doc "The partial path of every copy started, oldest first."
  def snapshots(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.snapshots))

  @doc "The path of every copy proved, oldest first."
  def proofs(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.proofs))

  @doc "How many copies were cancelled past their timeout."
  def cancellations(%{pid: pid}), do: Agent.get(pid, & &1.cancellations)

  @impl true
  def source_path(_snapshot), do: @source_path

  @impl true
  def source_generation(%{pid: pid}), do: Agent.get(pid, & &1.generation)

  @impl true
  def vacuum_into(%{pid: pid} = snapshot, path, timeout_ms) do
    {failure, hold} =
      Agent.get_and_update(pid, fn state ->
        {failure, failures} = Map.pop(state.failures, :vacuum_into)

        {{failure, state.hold},
         %{state | snapshots: [path | state.snapshots], failures: failures, hold: fn -> :ok end}}
      end)

    # Outside the agent, so the held copy blocks only the backup, never the store.
    held = hold.()
    Agent.update(pid, &%{&1 | holds: [held | &1.holds]})
    copy = %{database: live_database(), generation: source_generation(snapshot)}

    cond do
      failure != nil ->
        :ok = ArtifactStore.put_file(ArtifactStore.new(), path, :partial)
        {:error, failure}

      timeout_ms < @copy_ms ->
        :ok = ArtifactStore.put_file(ArtifactStore.new(), path, :partial)
        Agent.update(pid, &%{&1 | cancellations: &1.cancellations + 1})
        {:error, :timeout}

      true ->
        ArtifactStore.put_file(ArtifactStore.new(), path, copy)
    end
  end

  @impl true
  def prove(%{pid: pid}, path) do
    failure =
      Agent.get_and_update(pid, fn state ->
        {failure, failures} = Map.pop(state.failures, :prove)
        {failure, %{state | proofs: [path | state.proofs], failures: failures}}
      end)

    case {failure, ArtifactStore.file(ArtifactStore.new(), path)} do
      {nil, %{content: %{database: _database}}} ->
        {:ok, %{schema_versions: @schema_versions, logical_sha256: logical_sha256()}}

      _corrupt_or_missing ->
        {:error, :corrupt}
    end
  end

  @impl true
  def restore(_snapshot, artifact_path) do
    with %{content: %{database: database}} <-
           ArtifactStore.file(ArtifactStore.new(), artifact_path),
         [{room, false}] <- Enum.filter(Map.values(database.rooms), &match?({_room, false}, &1)) do
      messages = for message <- database.messages, message.room_id == room.id, do: message

      {:ok,
       %{
         room: room,
         message_ids: messages |> Enum.map(& &1.id) |> Enum.sort(),
         subscription_count: length(database.subscriptions),
         delivery_states:
           database.deliveries |> Enum.map(& &1.state) |> Enum.uniq() |> Enum.sort(),
         messages: messages,
         subscriptions: database.subscriptions,
         deliveries: database.deliveries
       }}
    else
      _unrestorable -> {:error, :restore_failed}
    end
  end

  defp empty do
    %{
      generation:
        "test-user-backup-generation-" <> Integer.to_string(:erlang.unique_integer([:positive])),
      failures: %{},
      hold: fn -> :ok end,
      holds: [],
      snapshots: [],
      proofs: [],
      cancellations: 0
    }
  end

  defp live_database, do: RoomStore.new() |> RoomStore.contents()

  defp logical_sha256,
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(@schema_versions))
      |> Base.encode16(case: :lower)
end
