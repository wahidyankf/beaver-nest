defmodule BnestApp.Test.InMemory.DeliveryStore do
  @moduledoc """
  An Agent-backed `BnestApp.PushNotifications.Ports.DeliveryStore`. It keeps the port's
  semantics without SQL, on the agent of an in-memory room store, whose commits record the
  deliveries it serves and whose messages and rooms it reads (see
  `BnestApp.Test.InMemory.RoomStore`).

  `start/0` gives a test its own store; `over/1` gives the delivery store on the agent of
  another in-memory store's handle. The unit layer configures this module as the
  `:delivery_store` adapter; its `new/0` serves the room store a test installed.
  `deliveries/1` reads back every stored row. The test seam `put/3` changes a stored row's
  columns, standing in for time that has passed: a delivery last stamped days ago, a wait
  that has elapsed.
  """

  @behaviour BnestApp.PushNotifications.Ports.DeliveryStore

  alias BnestApp.Test.InMemory.RoomStore

  @dispatcher "system:push-dispatcher"
  @final ~w(delivered terminal)
  @unfinished ~w(pending claimed retryable)

  @doc "A fresh store, on a fresh in-memory room store linked to the calling test."
  def start, do: over(RoomStore.start())

  @doc "The delivery store on the agent of `handle`, a handle of any in-memory store."
  def over(%{pid: pid}), do: %{adapter: __MODULE__, pid: pid}

  @impl true
  def new, do: over(RoomStore.new())

  @doc "Every stored delivery, lowest ID first."
  def deliveries(%{pid: pid}), do: Agent.get(pid, & &1.deliveries)

  @doc "Changes the given columns of the stored delivery with the ID."
  def put(%{pid: pid}, delivery_id, changes) do
    changes = Map.new(changes, fn {column, value} -> {column, second(value)} end)
    update_where(pid, &(&1.id == delivery_id), &Map.merge(&1, changes))
  end

  @impl true
  def claim_due(%{pid: pid}, now, lease_until) do
    now = second(now)

    Agent.get_and_update(pid, fn state ->
      case Enum.find(state.deliveries, &due?(&1, now)) do
        nil ->
          {nil, state}

        due ->
          claimed = %{
            due
            | state: "claimed",
              attempt_count: due.attempt_count + 1,
              lease_expires_at: second(lease_until),
              next_attempt_at: nil,
              updated_at: now,
              updated_by: @dispatcher
          }

          claim = %{
            id: claimed.id,
            message_id: claimed.message_id,
            subscription_id: claimed.subscription_id,
            attempt: claimed.attempt_count,
            created_at: claimed.created_at
          }

          {claim, %{state | deliveries: replace(state.deliveries, claimed)}}
      end
    end)
  end

  @impl true
  def retry!(%{pid: pid}, delivery_id, next_attempt_at, now) do
    update_where(pid, &(&1.id == delivery_id), fn row ->
      %{
        row
        | state: "retryable",
          lease_expires_at: nil,
          next_attempt_at: second(next_attempt_at),
          failure_category: "retryable",
          updated_at: second(now),
          updated_by: @dispatcher
      }
    end)
  end

  @impl true
  def finalize!(%{pid: pid}, delivery_id, state, failure_category, provider_accepted_at, now) do
    update_where(pid, &(&1.id == delivery_id), fn row ->
      %{
        row
        | state: state,
          lease_expires_at: nil,
          next_attempt_at: nil,
          failure_category: failure_category,
          provider_accepted_at: provider_accepted_at && second(provider_accepted_at),
          updated_at: second(now),
          updated_by: @dispatcher
      }
    end)
  end

  @impl true
  def message(%{pid: pid}, message_id) do
    Agent.get(pid, fn state ->
      with %{} = message <- Enum.find(state.messages, &(&1.id == message_id)),
           {room, _deleted?} <- Map.get(state.rooms, message.room_id) do
        %{
          id: message.id,
          body: message.body,
          sender_display_name: message.sender_display_name,
          room_slug: room.slug
        }
      end
    end)
  end

  @impl true
  def soft_delete_final!(%{pid: pid}, cutoff, now, limit) do
    cutoff = second(cutoff)
    now = second(now)

    Agent.get_and_update(pid, fn state ->
      ids =
        state.deliveries
        |> Enum.filter(
          &(is_nil(&1.deleted_at) and &1.state in @final and not later?(&1.updated_at, cutoff))
        )
        |> Enum.take(limit)
        |> Enum.map(& &1.id)

      rows =
        map_where(
          state.deliveries,
          &(&1.id in ids),
          &%{&1 | deleted_at: now, deleted_by: "system:push-retention"}
        )

      {length(ids), %{state | deliveries: rows}}
    end)
  end

  @impl true
  def purge_deleted!(%{pid: pid}, cutoff, limit) do
    cutoff = second(cutoff)

    Agent.get_and_update(pid, fn state ->
      ids =
        state.deliveries
        |> Enum.filter(&(not is_nil(&1.deleted_at) and not later?(&1.deleted_at, cutoff)))
        |> Enum.take(limit)
        |> Enum.map(& &1.id)

      {length(ids), %{state | deliveries: Enum.reject(state.deliveries, &(&1.id in ids))}}
    end)
  end

  @impl true
  def count_active_unfinished(%{pid: pid}) do
    Agent.get(pid, fn state ->
      Enum.count(state.deliveries, &(is_nil(&1.deleted_at) and &1.state in @unfinished))
    end)
  end

  # Every callback changes the agent in one step, so a transaction only runs the function.
  @impl true
  def transaction(_store, fun), do: fun.()

  # Pending or retryable once its wait (if any) is over, or claimed once its lease expired;
  # a soft-deleted delivery is never due.
  defp due?(%{deleted_at: deleted_at}, _now) when not is_nil(deleted_at), do: false

  defp due?(%{state: state} = row, now) when state in ~w(pending retryable),
    do: is_nil(row.next_attempt_at) or not later?(row.next_attempt_at, now)

  defp due?(%{state: "claimed", lease_expires_at: lease}, now),
    do: not is_nil(lease) and not later?(lease, now)

  defp due?(_final, _now), do: false

  defp later?(time, than), do: DateTime.compare(time, than) == :gt

  defp replace(rows, row), do: Enum.map(rows, &if(&1.id == row.id, do: row, else: &1))

  defp update_where(pid, matches?, change) do
    Agent.update(pid, fn state ->
      %{state | deliveries: map_where(state.deliveries, matches?, change)}
    end)
  end

  defp map_where(rows, matches?, change),
    do: Enum.map(rows, &if(matches?.(&1), do: change.(&1), else: &1))

  defp second(%DateTime{} = time), do: DateTime.truncate(time, :second)
  defp second(other), do: other
end
