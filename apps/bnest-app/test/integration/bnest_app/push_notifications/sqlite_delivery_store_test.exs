defmodule BnestApp.PushNotifications.SqliteDeliveryStoreTest do
  # Not async: the SQLite repository is one named process, and the application's Family Chat
  # database path is repointed for each test.
  use BnestApp.Test.Contracts.DeliveryStoreContract, async: false

  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.PushNotifications.Adapters.SqliteDeliveryStore
  alias BnestApp.PushNotifications.Adapters.SqliteSubscriptionStore
  alias BnestApp.PushNotifications.Ports.SubscriptionStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.TestRuntimeRoot

  @recipient_endpoint "https://push.allowed.example.com/sqlite-recipient"

  # Each test gets its own Family Chat database under an isolated test-run root, prepared
  # (migrated, seeded, and the shared repository pointed at it) as the facade prepares it
  # before every store call. The handle also names that database for `put_delivery/2`.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-delivery-store")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    previous_path = Application.fetch_env!(:bnest_app, :family_chat_sqlite_path)
    Application.put_env(:bnest_app, :family_chat_sqlite_path, database_path)

    on_exit(fn ->
      Application.put_env(:bnest_app, :family_chat_sqlite_path, previous_path)
      Storage.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    :ok = RoomStore.ensure_ready!(SqliteRoomStore.new(database_path: database_path))
    Map.put(SqliteDeliveryStore.new(), :database_path, database_path)
  end

  # A delivery comes to exist the way production makes one: the recipient's one
  # subscription (upserted again before each commit, so every commit owes exactly one
  # delivery) and Family Chat's commit, which fans the message out to it.
  defp put_delivery(store, body) do
    :ok =
      SubscriptionStore.upsert!(
        SqliteSubscriptionStore.new(),
        "test-user-sqlite-recipient",
        sha256("recipient-session"),
        %{
          endpoint: @recipient_endpoint,
          endpoint_sha256: sha256(@recipient_endpoint),
          p256dh: "p256dh",
          auth: "auth"
        },
        at()
      )

    {:ok, %{id: message_id, deliveries: [%{subscription_id: subscription_id}]}} =
      RoomStore.insert_message!(
        SqliteRoomStore.new(database_path: store.database_path),
        1,
        "user",
        "test-user-sqlite-sender",
        "Test User",
        Ecto.UUID.generate(),
        body,
        nil
      )

    %{message_id: message_id, subscription_id: subscription_id}
  end

  test "writes every column a claimed and retried delivery carries", %{store: store} do
    %{message_id: message_id, subscription_id: subscription_id} = put_delivery(store, "columns")
    %{id: id} = claim(store)
    :ok = DeliveryStore.retry!(store, id, at(30), at())

    assert row(id) == [
             message_id,
             subscription_id,
             "retryable",
             1,
             iso(at(30)),
             nil,
             "retryable",
             nil,
             "user:test-user-sqlite-sender",
             iso(at()),
             "system:push-dispatcher",
             nil,
             nil
           ]
  end

  test "a final delivery records when the provider accepted it", %{store: store} do
    put_delivery(store, "accepted")
    claim = claim(store)
    :ok = finalize!(store, claim, "delivered", 5)

    assert [_message_id, _subscription_id, "delivered", 1, nil, nil, nil | _rest] = row(claim.id)

    %{rows: [[accepted_at]]} =
      SqliteRepo.query!(
        "SELECT provider_accepted_at FROM family_chat_push_deliveries WHERE id = ?",
        [claim.id]
      )

    assert accepted_at == iso(at(5))
  end

  test "a failed transaction raises with its owner and changes nothing", %{store: store} do
    put_delivery(store, "rolled-back")

    assert_raise RuntimeError, ~r/^push notifications transaction failed: :refused/, fn ->
      DeliveryStore.transaction(store, fn ->
        DeliveryStore.soft_delete_final!(store, at(), at(), 250)
        SqliteRepo.rollback(:refused)
      end)
    end

    assert DeliveryStore.count_active_unfinished(store) == 1
  end

  defp row(id) do
    %{rows: [row]} =
      SqliteRepo.query!(
        """
        SELECT message_id, subscription_id, state, attempt_count, next_attempt_at,
               lease_expires_at, failure_category, provider_accepted_at, created_by,
               updated_at, updated_by, deleted_at, deleted_by
        FROM family_chat_push_deliveries WHERE id = ?
        """,
        [id]
      )

    row
  end

  defp iso(time), do: DateTime.to_iso8601(time)
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
