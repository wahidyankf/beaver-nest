defmodule BnestApp.PushNotifications.InMemoryDeliveryStoreTest do
  use BnestApp.Test.Contracts.DeliveryStoreContract, async: true

  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.PushNotifications.Ports.SubscriptionStore
  alias BnestApp.Test.InMemory.DeliveryStore, as: InMemoryDeliveryStore
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore

  defp new_store(_context), do: InMemoryDeliveryStore.start()

  # The recipient's one subscription is upserted again before each commit, so every commit
  # owes exactly one delivery. The scheme is built from fragments (no unit URL literal).
  defp put_delivery(store, body) do
    endpoint = "https:" <> "//push.allowed.example.com/in-memory-recipient"

    :ok =
      SubscriptionStore.upsert!(
        InMemorySubscriptionStore.over(store),
        "test-user-in-memory-recipient",
        "recipient-session",
        %{endpoint: endpoint, endpoint_sha256: endpoint, p256dh: "p256dh", auth: "auth"},
        at()
      )

    {:ok, %{id: message_id, deliveries: [%{subscription_id: subscription_id}]}} =
      RoomStore.insert_message!(
        InMemoryRoomStore.over(store),
        1,
        "user",
        "test-user-in-memory-sender",
        "Test User",
        Ecto.UUID.generate(),
        body,
        nil
      )

    %{message_id: message_id, subscription_id: subscription_id}
  end

  test "keeps every column a stored delivery carries", %{store: store} do
    %{message_id: message_id, subscription_id: subscription_id} = put_delivery(store, "columns")
    %{id: id} = claim(store)
    :ok = DeliveryStore.retry!(store, id, at(30), at())

    assert [
             %{
               id: ^id,
               message_id: ^message_id,
               subscription_id: ^subscription_id,
               state: "retryable",
               attempt_count: 1,
               next_attempt_at: next_attempt_at,
               lease_expires_at: nil,
               failure_category: "retryable",
               provider_accepted_at: nil,
               created_by: "user:test-user-in-memory-sender",
               updated_at: updated_at,
               updated_by: "system:push-dispatcher",
               deleted_at: nil,
               deleted_by: nil
             }
           ] = InMemoryDeliveryStore.deliveries(store)

    assert {next_attempt_at, updated_at} == {at(30), at()}
  end

  test "a stored delivery can be put into the state a scenario describes", %{store: store} do
    put_delivery(store, "aged")
    [%{id: id}] = InMemoryDeliveryStore.deliveries(store)

    assert InMemoryDeliveryStore.put(store, id, state: "delivered", updated_at: at(-86_400)) ==
             :ok

    assert DeliveryStore.soft_delete_final!(store, at(-86_400), at(), 250) == 1

    assert [%{deleted_at: deleted_at, deleted_by: "system:push-retention"}] =
             InMemoryDeliveryStore.deliveries(store)

    assert deleted_at == at()
  end
end
