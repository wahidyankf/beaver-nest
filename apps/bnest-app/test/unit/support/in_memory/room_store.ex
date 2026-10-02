defmodule BnestApp.Test.InMemory.RoomStore do
  @moduledoc """
  An Agent-backed `BnestApp.FamilyChat.Ports.RoomStore`. It keeps the port's semantics
  without SQL: the seeded canonical room, append-only messages with ascending IDs, the
  unique idempotency key per sender, reply targets that must exist, cursor pages, and one
  pending delivery per other active push subscription.

  The agent is the unit layer's in-memory stand-in for Family Chat's SQLite database, which
  also holds PushNotifications' subscriptions and deliveries. `BnestApp.Test.InMemory.
  SubscriptionStore` and `BnestApp.Test.InMemory.DeliveryStore` serve those rows from the
  same agent, so a commit fans out to the subscriptions they store and records the
  deliveries they claim, as the SQLite stores share one database. `over/1` turns a handle
  of any of the three into a room store handle on the same agent.

  `start/0` gives a test its own store. The unit layer also configures this module as the
  `:room_store` adapter; its `new/0` then serves the store a test started with
  `install/0`, which the test supervisor stops before the next test, so each test starts
  from a fresh store. The test seam `put_room/3` stands in for rooms other than the
  canonical one, which the store's own callbacks never write. `calls/1` reports every room
  store callback the store has served, so a test can prove that code it ran never reached
  Family Chat's store. `pristine?/1` tells whether nothing was seeded or committed yet, and
  `fail_next_delivery_insert/1` makes the next commit fail at its delivery rows, rolling the
  whole commit back as the SQLite store's transaction does.
  """

  @behaviour BnestApp.FamilyChat.Ports.RoomStore

  @canonical_room %{
    id: 1,
    slug: "ruang-keluarga",
    name: "Ruang Keluarga",
    room_kind: "conversation",
    member_posting_enabled: true
  }

  @doc "A fresh store with no room seeded yet, linked to the calling test."
  def start do
    {:ok, pid} = Agent.start_link(&empty/0)
    %{adapter: __MODULE__, pid: pid}
  end

  @doc """
  Starts a fresh store under the calling test's supervisor as the store `new/0` serves,
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

  # Configured as the unit layer's `:room_store`, so the facade, the GraphQL resolvers and
  # the controller all reach the store the current test installed. Without one it fails
  # loudly rather than serve a store nobody seeded or reads.
  @impl true
  def new do
    case GenServer.whereis(__MODULE__) do
      nil ->
        raise ArgumentError,
              "no in-memory room store is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.FamilyChat"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Stores `room` as is, replacing the room with its ID; `deleted?: true` archives it."
  def put_room(%{pid: pid}, room, options \\ []) do
    Agent.update(pid, fn state ->
      state = seed(state)
      put_in(state.rooms[room.id], {room, Keyword.get(options, :deleted?, false)})
    end)
  end

  @doc "A room store handle on the agent of `handle`, a handle of any in-memory store."
  def over(%{pid: pid}), do: %{adapter: __MODULE__, pid: pid}

  @doc """
  Everything the store holds, as Family Chat's SQLite database would: its rooms (by ID, each
  with whether it is archived), messages, push subscriptions and deliveries. Backup's
  in-memory snapshot copies it.
  """
  def contents(%{pid: pid}),
    do:
      Agent.get(
        pid,
        &(&1 |> seed() |> Map.take([:rooms, :messages, :subscriptions, :deliveries]))
      )

  @doc "Whether the store holds no room and no message: nothing seeded or committed yet."
  def pristine?(%{pid: pid}), do: Agent.get(pid, &(&1.rooms == %{} and &1.messages == []))

  @doc """
  Makes the next commit fail while it writes its delivery rows. Nothing of that commit is
  kept: not the message, not a delivery.
  """
  def fail_next_delivery_insert(%{pid: pid}),
    do: Agent.update(pid, &%{&1 | fail_delivery_insert: true})

  @doc "The name of every port callback the store has served, oldest first."
  def calls(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.calls))

  @impl true
  def ensure_ready!(%{pid: pid}),
    do: Agent.update(pid, &(&1 |> seed() |> called(:ensure_ready!)))

  @impl true
  def list_active_rooms(store) do
    read(store, :list_active_rooms, fn state ->
      for {_id, {room, false}} <- Enum.sort(state.rooms), do: room
    end)
  end

  @impl true
  def get_active_room(store, slug) when is_binary(slug) do
    read(store, :get_active_room, fn state ->
      Enum.find_value(state.rooms, fn
        {_id, {%{slug: ^slug} = room, false}} -> room
        _other -> nil
      end)
    end)
  end

  @impl true
  def list_messages(store, room_id, before_id, after_id, limit)
      when is_integer(room_id) and is_integer(limit) do
    read(store, :list_messages, fn state ->
      messages = Enum.filter(state.messages, &(&1.room_id == room_id))
      page(messages, before_id, after_id, limit)
    end)
  end

  @impl true
  def find_message(store, room_id, sender_kind, sender_id, idempotency_key) do
    read(store, :find_message, fn state ->
      Enum.find(
        state.messages,
        &(&1.room_id == room_id and &1.sender_kind == sender_kind and &1.sender_id == sender_id and
            &1.idempotency_key == idempotency_key)
      )
    end)
  end

  @impl true
  def insert_message!(
        %{pid: pid},
        room_id,
        sender_kind,
        sender_id,
        sender_display_name,
        idempotency_key,
        body,
        reply_to_message_id
      ) do
    result =
      Agent.get_and_update(pid, fn state ->
        state = state |> seed() |> called(:insert_message!)

        message = %{
          id: state.next_message_id,
          room_id: room_id,
          sender_kind: sender_kind,
          sender_id: sender_id,
          sender_display_name: sender_display_name,
          idempotency_key: idempotency_key,
          body: body,
          committed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          reply_to_message_id: reply_to_message_id
        }

        case refusal(state, message) do
          nil -> commit(state, message)
          reason -> {{:error, reason}, %{state | fail_delivery_insert: false}}
        end
      end)

    case result do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> raise ArgumentError, "family chat message refused: #{reason}"
    end
  end

  @impl true
  def quotes_for(store, room_id, messages) when is_integer(room_id) and is_list(messages) do
    ids =
      messages
      |> Enum.map(& &1[:reply_to_message_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    read(store, :quotes_for, &messages_by_id(&1.messages, room_id, ids))
  end

  defp messages_by_id(messages, room_id, ids) do
    for message <- messages,
        message.room_id == room_id and message.id in ids,
        into: %{},
        do: {message.id, message}
  end

  @impl true
  def message_by_id(store, room_id, message_id)
      when is_integer(room_id) and is_integer(message_id) do
    read(store, :message_by_id, fn state ->
      Enum.find(state.messages, &(&1.id == message_id and &1.room_id == room_id))
    end)
  end

  defp empty do
    %{
      rooms: %{},
      messages: [],
      next_message_id: 1,
      subscriptions: [],
      next_subscription_id: 1,
      deliveries: [],
      next_delivery_id: 1,
      fail_delivery_insert: false,
      calls: []
    }
  end

  # Every callback reads a seeded store, as the SQLite store's self-healing bootstrap does,
  # and is logged for `calls/1`.
  defp read(%{pid: pid}, callback, fun) do
    Agent.get_and_update(pid, fn state ->
      state = state |> seed() |> called(callback)
      {fun.(state), state}
    end)
  end

  defp called(state, callback), do: %{state | calls: [callback | state.calls]}

  defp seed(%{rooms: rooms} = state) when is_map_key(rooms, 1), do: state

  defp seed(state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    room =
      Map.merge(@canonical_room, %{
        created_at: now,
        created_by: "system:migration",
        updated_at: now,
        updated_by: "system:migration"
      })

    put_in(state.rooms[1], {room, false})
  end

  defp refusal(state, message) do
    cond do
      state.fail_delivery_insert ->
        "the delivery rows could not be written"

      not Map.has_key?(state.rooms, message.room_id) ->
        "room #{message.room_id} does not exist"

      find_duplicate(state, message) ->
        "the sender already committed idempotency key #{message.idempotency_key}"

      message.reply_to_message_id != nil and
          not Enum.any?(state.messages, &(&1.id == message.reply_to_message_id)) ->
        "reply target #{message.reply_to_message_id} is no message"

      true ->
        nil
    end
  end

  defp find_duplicate(state, message) do
    Enum.any?(
      state.messages,
      &(&1.room_id == message.room_id and &1.sender_kind == message.sender_kind and
          &1.sender_id == message.sender_id and &1.idempotency_key == message.idempotency_key)
    )
  end

  # One pending delivery per active subscription, in subscription order; a user sender's
  # own are excluded, a system sender owns none. Each is stored as a whole delivery row,
  # stamped with the commit's time and actor, as the SQLite store's commit inserts it.
  defp commit(state, message) do
    excluded = if message.sender_kind == "user", do: message.sender_id
    actor = actor_for(message.sender_kind, message.sender_id)

    owed =
      for subscription <- state.subscriptions,
          is_nil(subscription.deleted_at) and subscription.user_id != excluded,
          do: subscription.id

    rows =
      owed
      |> Enum.with_index(state.next_delivery_id)
      |> Enum.map(fn {subscription_id, id} ->
        delivery_row(id, message, subscription_id, actor)
      end)

    state = %{
      state
      | messages: state.messages ++ [message],
        next_message_id: message.id + 1,
        deliveries: state.deliveries ++ rows,
        next_delivery_id: state.next_delivery_id + length(rows)
    }

    deliveries = Enum.map(owed, &%{subscription_id: &1, state: "pending"})
    {{:ok, Map.put(message, :deliveries, deliveries)}, state}
  end

  defp delivery_row(id, message, subscription_id, actor) do
    %{
      id: id,
      message_id: message.id,
      subscription_id: subscription_id,
      state: "pending",
      attempt_count: 0,
      next_attempt_at: nil,
      lease_expires_at: nil,
      failure_category: nil,
      provider_accepted_at: nil,
      created_at: message.committed_at,
      created_by: actor,
      updated_at: message.committed_at,
      updated_by: actor,
      deleted_at: nil,
      deleted_by: nil
    }
  end

  defp actor_for("system", sender_id), do: "system:" <> sender_id
  defp actor_for(_user_kind, sender_id), do: "user:" <> sender_id

  # An after cursor wins over a before cursor, as in the SQLite store.
  defp page(messages, _before_id, after_id, limit) when not is_nil(after_id) do
    {nodes, has_newer} = messages |> Enum.filter(&(&1.id > after_id)) |> take(limit)

    %{
      nodes: nodes,
      has_older: Enum.any?(messages, &(&1.id < after_id)),
      has_newer: has_newer
    }
  end

  defp page(messages, nil, nil, limit) do
    {nodes, has_older} = messages |> Enum.reverse() |> take(limit)
    %{nodes: Enum.reverse(nodes), has_older: has_older, has_newer: false}
  end

  defp page(messages, before_id, nil, limit) do
    {nodes, has_older} =
      messages |> Enum.filter(&(&1.id < before_id)) |> Enum.reverse() |> take(limit)

    %{nodes: Enum.reverse(nodes), has_older: has_older, has_newer: true}
  end

  defp take(messages, limit), do: {Enum.take(messages, limit), length(messages) > limit}
end
