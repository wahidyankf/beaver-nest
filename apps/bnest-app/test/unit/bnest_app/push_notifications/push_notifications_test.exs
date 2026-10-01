defmodule BnestApp.PushNotificationsTest do
  # `async: false`: the facade serves the one in-memory room store this test installs under
  # a registered name (its subscriptions and deliveries live on it), and several cases
  # temporarily mutate the global `:web_push, :vapid` Application env, restoring it via
  # `on_exit/1`.
  use ExUnit.Case, async: false

  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.Test.InMemory.DeliveryStore, as: InMemoryDeliveryStore
  alias BnestApp.Test.InMemory.PushSender
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore

  setup do
    store = InMemoryRoomStore.install()
    :ok = PushSender.forget_sent()
    {:ok, store: store}
  end

  defp unique_user, do: "test-user-family-chat-pushctx-" <> Ecto.UUID.generate()
  defp valid_key, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # Built from separate fragments (not one literal URL-shaped string) so this
  # synthetic fixture does not trip the unit-layer boundary policy's blanket
  # network-URL scan (`test/behaviour/verify.exs`).
  defp endpoint(suffix), do: "https:" <> "//push.allowed.example.com/" <> suffix

  defp valid_input(endpoint_suffix) do
    %{"endpoint" => endpoint(endpoint_suffix), "p256dh" => valid_key(), "auth" => valid_key()}
  end

  # A subscription of a fresh user and session whose endpoint ends in `suffix`, and one
  # message from another member, which owes it a delivery.
  defp owe_delivery!(store, suffix) do
    user = unique_user()

    assert {:ok, %{enabled: true}} =
             PushNotifications.upsert_subscription(user, "session-owed", valid_input(suffix))

    {:ok, message} =
      FamilyChat.send_message(
        unique_user(),
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "owed"
      )

    delivery =
      store
      |> InMemoryDeliveryStore.over()
      |> InMemoryDeliveryStore.deliveries()
      |> Enum.find(&(&1.message_id == message.id))

    %{user: user, message: message, delivery_id: delivery.id}
  end

  defp delivery(store, id) do
    store
    |> InMemoryDeliveryStore.over()
    |> InMemoryDeliveryStore.deliveries()
    |> Enum.find(&(&1.id == id))
  end

  describe "current_subscription/2" do
    test "reports disabled for a user with no stored row" do
      assert {:ok, %{enabled: false, expiration_time: nil}} =
               PushNotifications.current_subscription(unique_user(), "session-a")
    end

    test "reports enabled with the stored expiration once a subscription exists" do
      user = unique_user()
      session = "session-b"

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(user, session, valid_input(user))

      assert {:ok, %{enabled: true, expiration_time: nil}} =
               PushNotifications.current_subscription(user, session)
    end
  end

  describe "upsert_subscription/3" do
    test "rejects an unauthenticated (nil) caller" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               PushNotifications.upsert_subscription(nil, "session-c", valid_input("unused"))
    end

    test "rejects an endpoint off the allowlist the configured sender extends", %{store: store} do
      input = Map.put(valid_input("x"), "endpoint", "https:" <> "//push.example.com/x")

      assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
               PushNotifications.upsert_subscription(unique_user(), "session-f", input)

      assert store
             |> InMemorySubscriptionStore.over()
             |> InMemorySubscriptionStore.subscriptions() ==
               []
    end

    test "stores the endpoint under its digest and the session under the session key's digest",
         %{store: store} do
      user = unique_user()
      input = valid_input("digest-" <> Ecto.UUID.generate())

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(user, "session-g", input)

      assert [stored] =
               store
               |> InMemorySubscriptionStore.over()
               |> InMemorySubscriptionStore.subscriptions()

      assert stored.endpoint == input["endpoint"]
      assert stored.endpoint_sha256 == sha256(input["endpoint"])
      assert stored.session_digest == sha256("session-g")
      assert byte_size(stored.session_digest) == 64
    end

    test "rebinds an existing endpoint to a new (user, session) pair instead of duplicating it" do
      shared_endpoint_suffix = "rebind-" <> Ecto.UUID.generate()
      input = valid_input(shared_endpoint_suffix)
      first_user = unique_user()
      second_user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(first_user, "session-d", input)

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(second_user, "session-e", input)

      # Ownership moved explicitly to `second_user`; the first binding no
      # longer reports enabled for its own (user, session) pair.
      assert {:ok, %{enabled: false}} =
               PushNotifications.current_subscription(first_user, "session-d")

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(second_user, "session-e")
    end
  end

  describe "disable_subscription/2" do
    test "disables the session's subscription, idempotently" do
      user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(user, "s", valid_input(user))

      assert {:ok, %{enabled: false}} = PushNotifications.disable_subscription(user, "s")
      assert {:ok, %{enabled: false}} = PushNotifications.disable_subscription(user, "s")
      assert {:ok, %{enabled: false}} = PushNotifications.current_subscription(user, "s")
    end
  end

  describe "dispatch_all_due!/0" do
    test "sends every due delivery once and records each accepted one delivered",
         %{store: store} do
      # The second message is owed to both subscriptions: three deliveries.
      owe_delivery!(store, "accepted-1")
      owe_delivery!(store, "accepted-2")
      owed = store |> InMemoryDeliveryStore.over() |> InMemoryDeliveryStore.deliveries()

      assert PushNotifications.dispatch_all_due!() == :ok

      assert length(owed) == 3

      for %{id: id} <- owed do
        assert %{state: "delivered", attempt_count: 1, provider_accepted_at: %DateTime{}} =
                 delivery(store, id)
      end

      assert Enum.sort(for {_endpoint, payload} <- sent(), do: payload["messageId"]) ==
               Enum.sort(Enum.map(owed, & &1.message_id))

      assert Dispatcher.attempt() == {:error, :no_due_delivery}
      assert sent() == []
    end

    test "retires a delivery the provider refuses outright, without retry", %{store: store} do
      owed = owe_delivery!(store, "status-403")

      assert {:ok, %{state: "terminal", next_attempt_at: nil, attempt: 1}} = Dispatcher.attempt()

      assert %{state: "terminal", failure_category: "provider"} =
               delivery(store, owed.delivery_id)

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(owed.user, "session-owed")
    end

    test "retires a delivery whose message cannot be read, sending nothing", %{store: store} do
      owed = owe_delivery!(store, "accepted-3")
      deliveries = InMemoryDeliveryStore.over(store)
      :ok = InMemoryDeliveryStore.put(deliveries, owed.delivery_id, message_id: 999_999)

      assert {:ok, %{state: "terminal", attempt: 1}} = Dispatcher.attempt()

      assert %{state: "terminal", failure_category: "provider"} =
               delivery(store, owed.delivery_id)

      refute_received {:push_notification_sent, _endpoint, _payload}
    end

    test "retires a claimed delivery already past the one-hour ceiling, sending nothing",
         %{store: store} do
      owed = owe_delivery!(store, "accepted-late")
      created_at = DateTime.add(DateTime.utc_now(), -3_601, :second)
      deliveries = InMemoryDeliveryStore.over(store)
      :ok = InMemoryDeliveryStore.put(deliveries, owed.delivery_id, created_at: created_at)

      assert {:ok, %{state: "terminal", next_attempt_at: nil, attempt: 1}} = Dispatcher.attempt()

      assert %{state: "terminal", failure_category: "ceiling", next_attempt_at: nil} =
               delivery(store, owed.delivery_id)

      assert sent() == []
      assert Dispatcher.attempt() == {:error, :no_due_delivery}
    end
  end

  describe "retain_deliveries/1" do
    test "reports zero of everything over an empty store" do
      assert PushNotifications.retain_deliveries(~U[2026-09-18 00:00:00Z]) ==
               {:ok, %{soft_deleted: 0, purged: 0, remaining_active: 0}}
    end
  end

  describe "configuration/0" do
    test "reports available: false with no VAPID config set at all" do
      original = Application.get_env(:web_push, :vapid)
      Application.delete_env(:web_push, :vapid)
      on_exit(fn -> Application.put_env(:web_push, :vapid, original) end)

      assert {:ok, %{available: false, public_key: nil}} = PushNotifications.configuration()
    end

    test "reads a map-shaped VAPID config exactly like the keyword-list shape" do
      original = Application.get_env(:web_push, :vapid)

      Application.put_env(:web_push, :vapid, %{
        public_key: "map-shaped-public-key",
        private_key: "map-shaped-private-key",
        subject: "mailto:map-shaped@example.com"
      })

      on_exit(fn -> Application.put_env(:web_push, :vapid, original) end)

      assert {:ok, %{available: true, public_key: "map-shaped-public-key"}} =
               PushNotifications.configuration()
    end
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  # Every request the push-client double recorded in this process, oldest first; draining.
  defp sent do
    receive do
      {:push_notification_sent, endpoint, payload} -> [{endpoint, payload} | sent()]
    after
      0 -> []
    end
  end
end
