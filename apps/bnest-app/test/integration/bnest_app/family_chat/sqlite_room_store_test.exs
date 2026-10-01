defmodule BnestApp.FamilyChat.SqliteRoomStoreTest do
  # Not async: the SQLite repository is one named process, and the application's Family Chat
  # database path is repointed for each test.
  use BnestApp.Test.Contracts.RoomStoreContract, async: false

  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.PushNotifications
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.TestRuntimeRoot

  # Each test gets its own database under an isolated test-run root; the adapter
  # repoints the shared repository onto it and migrates and seeds it on first use. The
  # application's Family Chat database path points at it too, so PushNotifications stores
  # the contract's subscriptions there.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-room-store")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    previous_path = Application.fetch_env!(:bnest_app, :family_chat_sqlite_path)
    Application.put_env(:bnest_app, :family_chat_sqlite_path, database_path)

    on_exit(fn ->
      Application.put_env(:bnest_app, :family_chat_sqlite_path, previous_path)
      Storage.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    SqliteRoomStore.new(database_path: database_path)
  end

  # A subscription comes to exist the way production makes one: PushNotifications' upsert
  # for a session of its own, then its disable when the owner turns it off. Synthetic keys
  # on the test-only allowlisted provider host; nothing is ever sent.
  defp put_subscription(store, attributes) do
    :ok = RoomStore.ensure_ready!(store)
    user_id = Keyword.fetch!(attributes, :user_id)
    session = "contract-session-" <> Ecto.UUID.generate()
    endpoint = "https://push.allowed.example.com/" <> Ecto.UUID.generate()

    input = %{
      "endpoint" => endpoint,
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    {:ok, %{enabled: true}} = PushNotifications.upsert_subscription(user_id, session, input)

    unless Keyword.get(attributes, :active?, true) do
      {:ok, %{enabled: false}} = PushNotifications.disable_subscription(user_id, session)
    end

    %{rows: [[id]]} =
      SqliteRepo.query!("SELECT id FROM web_push_subscriptions WHERE endpoint = ?", [endpoint])

    id
  end
end
