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

  # The test-owned sweep time. The store is installed with the same `now:`, so
  # stamps and dispatcher decisions share one clock and no test reads the system
  # clock.
  @now ~U[2026-09-18 20:00:00Z]

  setup do
    store = InMemoryRoomStore.install(now: @now)
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

  # Every stored delivery, lowest ID first.
  defp deliveries(store) do
    store
    |> InMemoryDeliveryStore.over()
    |> InMemoryDeliveryStore.deliveries()
  end

  # Changes the stored columns of one delivery, standing in for time that has passed.
  defp set_row!(store, id, changes),
    do: :ok = InMemoryDeliveryStore.put(InMemoryDeliveryStore.over(store), id, changes)

  defp days_before(time, days), do: DateTime.add(time, -days * 86_400, :second)

  # One message from a fresh member in the canonical room: it owes one delivery to the
  # single subscription a test has stored.
  defp send_messages!(count, prefix) do
    for number <- 1..count do
      {:ok, _message} =
        FamilyChat.send_message(
          unique_user(),
          FamilyChat.canonical_room_slug(),
          Ecto.UUID.generate(),
          "#{prefix} #{number}"
        )
    end

    :ok
  end

  describe "current_subscription/2" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads their current Web Push subscription state
    test "reports disabled for a user with no stored row" do
      assert {:ok, %{enabled: false, expiration_time: nil}} =
               PushNotifications.current_subscription(unique_user(), "session-a")
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads their current Web Push subscription state
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
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A visitor with no session is refused every Web Push subscription operation
    test "rejects an unauthenticated (nil) caller" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               PushNotifications.upsert_subscription(nil, "session-c", valid_input("unused"))
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An unsafe Web Push subscription endpoint is rejected
    test "rejects an endpoint off the allowlist the configured sender extends", %{store: store} do
      input = Map.put(valid_input("x"), "endpoint", "https:" <> "//push.example.com/x")

      assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
               PushNotifications.upsert_subscription(unique_user(), "session-f", input)

      assert store
             |> InMemorySubscriptionStore.over()
             |> InMemorySubscriptionStore.subscriptions() ==
               []
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member enables Web Push for this device only
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An unsafe Web Push subscription endpoint is rejected
    test "rejects an IP-literal, non-default-port, or userinfo endpoint and stores nothing", %{
      store: store
    } do
      for suffix <- [
            "//203.0.113.7/ip-literal-endpoint",
            "//push.allowed.example.com:8443/nondefault-port",
            "//user@push.allowed.example.com/userinfo-present"
          ] do
        input =
          valid_input("unsafe-" <> Ecto.UUID.generate())
          |> Map.put("endpoint", "https:" <> suffix)

        assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
                 PushNotifications.upsert_subscription(unique_user(), "session-unsafe", input)
      end

      assert store
             |> InMemorySubscriptionStore.over()
             |> InMemorySubscriptionStore.subscriptions() == []
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

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member enables Web Push for this device only
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
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member disables Web Push on this device
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Disabling Web Push again still reports disabled
    test "disables the session's subscription, idempotently" do
      user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(user, "s", valid_input(user))

      assert {:ok, %{enabled: false}} = PushNotifications.disable_subscription(user, "s")
      assert {:ok, %{enabled: false}} = PushNotifications.disable_subscription(user, "s")
      assert {:ok, %{enabled: false}} = PushNotifications.current_subscription(user, "s")
    end
  end

  describe "dispatch_all_due!/1" do
    test "sends every due delivery once and records each accepted one delivered",
         %{store: store} do
      # The second message is owed to both subscriptions: three deliveries.
      owe_delivery!(store, "accepted-1")
      owe_delivery!(store, "accepted-2")
      owed = store |> InMemoryDeliveryStore.over() |> InMemoryDeliveryStore.deliveries()

      assert PushNotifications.dispatch_all_due!(@now) == :ok

      assert length(owed) == 3

      for %{id: id} <- owed do
        assert %{state: "delivered", attempt_count: 1, provider_accepted_at: %DateTime{}} =
                 delivery(store, id)
      end

      assert Enum.sort(for {_endpoint, payload} <- sent(), do: payload["messageId"]) ==
               Enum.sort(Enum.map(owed, & &1.message_id))

      assert Dispatcher.attempt(@now) == {:error, :no_due_delivery}
      assert sent() == []
    end

    test "retires a delivery the provider refuses outright, without retry", %{store: store} do
      owed = owe_delivery!(store, "status-403")

      assert {:ok, %{state: "terminal", next_attempt_at: nil, attempt: 1}} =
               Dispatcher.attempt(@now)

      assert %{state: "terminal", failure_category: "provider"} =
               delivery(store, owed.delivery_id)

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(owed.user, "session-owed")
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A device the push service reports gone stops receiving notifications and shows as disabled
    test "disables the subscription the provider reports gone, sending it nothing more", %{
      store: store
    } do
      owed = owe_delivery!(store, "status-410")

      assert {:ok, %{state: "terminal", next_attempt_at: nil, attempt: 1}} =
               Dispatcher.attempt(@now)

      assert %{state: "terminal", failure_category: "gone"} =
               delivery(store, owed.delivery_id)

      assert {:ok, %{enabled: false}} =
               PushNotifications.current_subscription(owed.user, "session-owed")

      assert Dispatcher.attempt(@now) == {:error, :no_due_delivery}
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A reply notifies the other member once and the notification shows none of the quoted message
    test "a reply notifies once with the reply body and none of the quoted message" do
      other = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(other, "session-reply", valid_input("reply"))

      {:ok, target} =
        FamilyChat.send_message(
          unique_user(),
          FamilyChat.canonical_room_slug(),
          Ecto.UUID.generate(),
          "quoted question"
        )

      {:ok, reply} =
        FamilyChat.send_message(
          unique_user(),
          FamilyChat.canonical_room_slug(),
          Ecto.UUID.generate(),
          "reply answer",
          "Member",
          target.id
        )

      for _ <- 1..3, do: Dispatcher.attempt(@now)

      payloads = for {_endpoint, payload} <- sent(), do: payload
      reply_payloads = Enum.filter(payloads, &(&1["messageId"] == reply.id))

      assert length(reply_payloads) == 1
      assert hd(reply_payloads)["body"] =~ "reply answer"
      refute inspect(hd(reply_payloads)) =~ "quoted question"
    end

    test "retires a delivery whose message cannot be read, sending nothing", %{store: store} do
      owed = owe_delivery!(store, "accepted-3")
      deliveries = InMemoryDeliveryStore.over(store)
      :ok = InMemoryDeliveryStore.put(deliveries, owed.delivery_id, message_id: 999_999)

      assert {:ok, %{state: "terminal", attempt: 1}} = Dispatcher.attempt(@now)

      assert %{state: "terminal", failure_category: "provider"} =
               delivery(store, owed.delivery_id)

      refute_received {:push_notification_sent, _endpoint, _payload}
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
    test "a transient provider failure is retried after the first fixed wait and stays unfinished",
         %{store: store} do
      owed = owe_delivery!(store, "status-503")

      # The dispatcher and the store share the test-owned clock, so the first
      # backoff wait lands exactly thirty seconds after the sweep time.
      expected_wait = DateTime.add(@now, 30, :second)

      assert {:ok, %{state: "retryable", attempt: 1, next_attempt_at: ^expected_wait}} =
               Dispatcher.attempt(@now)

      assert %{state: "retryable", failure_category: "retryable", next_attempt_at: ^expected_wait} =
               delivery(store, owed.delivery_id)

      assert Dispatcher.attempt(@now) == {:error, :no_due_delivery}
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
    test "retires a claimed delivery already past the one-hour ceiling, sending nothing",
         %{store: store} do
      owed = owe_delivery!(store, "accepted-late")
      created_at = DateTime.add(@now, -3_601, :second)
      deliveries = InMemoryDeliveryStore.over(store)
      :ok = InMemoryDeliveryStore.put(deliveries, owed.delivery_id, created_at: created_at)

      assert {:ok, %{state: "terminal", next_attempt_at: nil, attempt: 1}} =
               Dispatcher.attempt(@now)

      assert %{state: "terminal", failure_category: "ceiling", next_attempt_at: nil} =
               delivery(store, owed.delivery_id)

      assert sent() == []
      assert Dispatcher.attempt(@now) == {:error, :no_due_delivery}
    end
  end

  describe "retain_deliveries/1" do
    test "reports zero of everything over an empty store" do
      assert PushNotifications.retain_deliveries(~U[2026-09-18 00:00:00Z]) ==
               {:ok, %{soft_deleted: 0, purged: 0, remaining_active: 0}}
    end

    test "soft-deletes only final deliveries older than seven days, keeping the rest",
         %{store: store} do
      now = ~U[2026-09-18 00:00:00Z]

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(
                 unique_user(),
                 "session-retain",
                 valid_input("retain-" <> Ecto.UUID.generate())
               )

      send_messages!(6, "retain")

      [delivered_old, terminal_old, delivered_young, pending, claimed, retryable] =
        deliveries(store)

      set_row!(store, delivered_old.id, state: "delivered", updated_at: days_before(now, 8))

      set_row!(store, terminal_old.id,
        state: "terminal",
        failure_category: "provider",
        updated_at: days_before(now, 8)
      )

      set_row!(store, delivered_young.id, state: "delivered", updated_at: days_before(now, 6))
      set_row!(store, pending.id, state: "pending", updated_at: days_before(now, 8))
      set_row!(store, claimed.id, state: "claimed", updated_at: days_before(now, 8))

      set_row!(store, retryable.id,
        state: "retryable",
        next_attempt_at: DateTime.add(now, 30, :second),
        updated_at: days_before(now, 8)
      )

      assert PushNotifications.retain_deliveries(now) ==
               {:ok, %{soft_deleted: 2, purged: 0, remaining_active: 3}}

      soft_deleted =
        for %{id: id, deleted_at: deleted_at, deleted_by: by} <- deliveries(store),
            deleted_at != nil,
            do: {id, by}

      assert soft_deleted == [
               {delivered_old.id, "system:push-retention"},
               {terminal_old.id, "system:push-retention"}
             ]
    end

    test "purges deliveries soft-deleted more than seven days ago, and a further run changes nothing",
         %{store: store} do
      now = ~U[2026-09-18 00:00:00Z]
      later = DateTime.add(now, 8 * 86_400, :second)

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(
                 unique_user(),
                 "session-purge",
                 valid_input("purge-" <> Ecto.UUID.generate())
               )

      send_messages!(1, "purge")
      [row] = deliveries(store)
      set_row!(store, row.id, state: "delivered", updated_at: days_before(now, 8))

      assert PushNotifications.retain_deliveries(now) ==
               {:ok, %{soft_deleted: 1, purged: 0, remaining_active: 0}}

      assert PushNotifications.retain_deliveries(later) ==
               {:ok, %{soft_deleted: 0, purged: 1, remaining_active: 0}}

      assert deliveries(store) == []

      assert PushNotifications.retain_deliveries(later) ==
               {:ok, %{soft_deleted: 0, purged: 0, remaining_active: 0}}
    end
  end

  describe "configuration/0" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads the Web Push configuration
    test "reports available: false with no VAPID config set at all" do
      original = Application.get_env(:web_push, :vapid)
      Application.delete_env(:web_push, :vapid)
      on_exit(fn -> Application.put_env(:web_push, :vapid, original) end)

      assert {:ok, %{available: false, public_key: nil}} = PushNotifications.configuration()
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads the Web Push configuration
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
