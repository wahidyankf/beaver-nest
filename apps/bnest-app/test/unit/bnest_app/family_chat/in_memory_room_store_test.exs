defmodule BnestApp.FamilyChat.InMemoryRoomStoreTest do
  use BnestApp.Test.Contracts.RoomStoreContract, async: true

  alias BnestApp.Test.InMemory.DeliveryStore, as: InMemoryDeliveryStore
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore

  defp new_store(_context), do: InMemoryRoomStore.start()

  # A subscription comes to exist through the in-memory subscription store on the same
  # agent, as the SQLite contract's comes through PushNotifications.
  defp put_subscription(store, attributes) do
    InMemorySubscriptionStore.subscribe!(
      store,
      Keyword.fetch!(attributes, :user_id),
      Keyword.take(attributes, [:active?])
    )
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Every other member with push enabled is notified of a new message and the sender is not
  test "commits one pending delivery per other active subscription", %{store: store} do
    other = put_subscription(store, user_id: "test-user-in-memory-other")
    sender = put_subscription(store, user_id: "test-user-in-memory-sender")

    {:ok, from_user} =
      commit!(store, "key-user", "from a user", nil, "test-user-in-memory-sender")

    {:ok, from_system} =
      RoomStore.insert_message!(
        store,
        1,
        "system",
        "test-user-in-memory-sender",
        "System",
        "k",
        "notice",
        nil
      )

    assert from_user.deliveries == [%{subscription_id: other, state: "pending"}]

    assert Enum.sort_by(from_system.deliveries, & &1.subscription_id) ==
             [
               %{subscription_id: other, state: "pending"},
               %{subscription_id: sender, state: "pending"}
             ]

    assert store
           |> InMemoryDeliveryStore.deliveries()
           |> Enum.map(&Map.take(&1, [:message_id, :subscription_id, :state])) == [
             %{message_id: from_user.id, subscription_id: other, state: "pending"},
             %{message_id: from_system.id, subscription_id: other, state: "pending"},
             %{message_id: from_system.id, subscription_id: sender, state: "pending"}
           ]

    # One transaction: when the delivery rows cannot be written, the message and every
    # delivery row of that commit are kept out of the store together.
    deliveries_before = InMemoryDeliveryStore.deliveries(store)
    :ok = InMemoryRoomStore.fail_next_delivery_insert(store)

    assert_raise ArgumentError, ~r/the delivery rows could not be written/, fn ->
      commit!(store, "key-refused", "refused", nil, "test-user-in-memory-sender")
    end

    assert RoomStore.find_message(store, 1, "user", "test-user-in-memory-sender", "key-refused") ==
             nil

    assert InMemoryDeliveryStore.deliveries(store) == deliveries_before
  end

  test "a seeded room is served as stored, and only active rooms are listed", %{store: store} do
    :ok = RoomStore.ensure_ready!(store)
    [canonical] = RoomStore.list_active_rooms(store)
    archived = %{canonical | id: 900, slug: "ruang-arsip", name: "Ruang Arsip"}

    :ok = InMemoryRoomStore.put_room(store, %{canonical | member_posting_enabled: false})
    :ok = InMemoryRoomStore.put_room(store, archived, deleted?: true)

    assert RoomStore.list_active_rooms(store) == [%{canonical | member_posting_enabled: false}]
    assert RoomStore.get_active_room(store, "ruang-arsip") == nil

    {:ok, foreign} =
      RoomStore.insert_message!(store, 900, "user", "test-user-archive", "Arsip", "k", "x", nil)

    assert RoomStore.message_by_id(store, 1, foreign.id) == nil
    assert RoomStore.message_by_id(store, 900, foreign.id) == stored(foreign)
  end
end
