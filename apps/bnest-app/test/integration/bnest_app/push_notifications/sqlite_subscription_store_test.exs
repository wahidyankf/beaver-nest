defmodule BnestApp.PushNotifications.SqliteSubscriptionStoreTest do
  # Not async: the SQLite repository is one named process, and the application's Family Chat
  # database path is repointed for each test.
  use BnestApp.Test.Contracts.SubscriptionStoreContract, async: false

  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.PushNotifications.Adapters.SqliteSubscriptionStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.TestRuntimeRoot

  # Each test gets its own Family Chat database under an isolated test-run root, prepared
  # (migrated, and the shared repository pointed at it) as the facade prepares it before
  # every store call.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-subscription-store")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    previous_path = Application.fetch_env!(:bnest_app, :family_chat_sqlite_path)
    Application.put_env(:bnest_app, :family_chat_sqlite_path, database_path)

    on_exit(fn ->
      Application.put_env(:bnest_app, :family_chat_sqlite_path, previous_path)
      Storage.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    :ok = RoomStore.ensure_ready!(SqliteRoomStore.new(database_path: database_path))
    SqliteSubscriptionStore.new()
  end

  defp stored(_store, endpoint) do
    case SqliteRepo.query!(
           "SELECT id, user_id, session_digest, deleted_at FROM web_push_subscriptions WHERE endpoint = ?",
           [endpoint]
         ) do
      %{rows: [[id, user_id, session_digest, deleted_at]]} ->
        %{id: id, user_id: user_id, session_digest: session_digest, active?: is_nil(deleted_at)}

      %{rows: []} ->
        nil
    end
  end

  test "writes the audit actor and instant of every change", %{store: store} do
    binding = binding_for("audited")
    later = DateTime.add(now(), 60, :second)
    :ok = upsert!(store, "test-user-sqlite-a", @session_a, binding)
    :ok = SubscriptionStore.disable_session!(store, "test-user-sqlite-a", @session_a, later)

    assert audit(binding.endpoint) == [
             iso(now()),
             "user:test-user-sqlite-a",
             iso(later),
             "user:test-user-sqlite-a",
             iso(later),
             "user:test-user-sqlite-a",
             nil
           ]

    :ok = upsert!(store, "test-user-sqlite-a", @session_a, binding)
    :ok = SubscriptionStore.disable_gone!(store, stored(store, binding.endpoint).id, later)

    assert [
             _created_at,
             _created_by,
             _updated_at,
             "system:push-dispatcher",
             _deleted_at,
             "system:push-dispatcher",
             nil
           ] = audit(binding.endpoint)
  end

  defp audit(endpoint) do
    %{rows: [row]} =
      SqliteRepo.query!(
        """
        SELECT created_at, created_by, updated_at, updated_by, deleted_at, deleted_by,
               expiration_time
        FROM web_push_subscriptions WHERE endpoint = ?
        """,
        [endpoint]
      )

    row
  end

  defp iso(time), do: DateTime.to_iso8601(time)
end
