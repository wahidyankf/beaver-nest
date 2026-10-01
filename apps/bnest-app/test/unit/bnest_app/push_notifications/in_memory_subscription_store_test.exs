defmodule BnestApp.PushNotifications.InMemorySubscriptionStoreTest do
  use BnestApp.Test.Contracts.SubscriptionStoreContract, async: true

  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore

  defp new_store(_context), do: InMemorySubscriptionStore.start()

  defp stored(store, endpoint) do
    store
    |> InMemorySubscriptionStore.subscriptions()
    |> Enum.find_value(fn
      %{endpoint: ^endpoint} = row ->
        %{
          id: row.id,
          user_id: row.user_id,
          session_digest: row.session_digest,
          active?: is_nil(row.deleted_at)
        }

      _other ->
        nil
    end)
  end

  test "keeps the audit actor and instant of every change", %{store: store} do
    binding = binding_for("audited")
    later = DateTime.add(now(), 60, :second)
    :ok = upsert!(store, "test-user-in-memory-a", @session_a, binding)
    :ok = SubscriptionStore.disable_session!(store, "test-user-in-memory-a", @session_a, later)

    assert [row] = InMemorySubscriptionStore.subscriptions(store)

    assert %{
             created_at: created_at,
             created_by: "user:test-user-in-memory-a",
             updated_at: ^later,
             updated_by: "user:test-user-in-memory-a",
             deleted_at: ^later,
             deleted_by: "user:test-user-in-memory-a",
             expiration_time: nil
           } = row

    assert created_at == now()

    :ok = upsert!(store, "test-user-in-memory-a", @session_a, binding)
    %{id: id} = stored(store, binding.endpoint)
    :ok = SubscriptionStore.disable_gone!(store, id, later)

    assert [%{deleted_by: "system:push-dispatcher", updated_by: "system:push-dispatcher"}] =
             InMemorySubscriptionStore.subscriptions(store)
  end
end
