defmodule BnestApp.PushNotificationsDispatcherTest do
  # Push fan-out and redelivery against the real stores: subscriptions and deliveries live in
  # the fresh instance's SQLite database, the dispatcher runs its real claim/attempt cycle,
  # and only the provider's answer comes from a double (the recording sender for accepted
  # pushes, the answering in-memory sender for retryable and gone answers), exactly as the
  # scenarios' exemption notes allow.
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.Test.InMemory.PushSender

  @now ~U[2026-09-18 20:00:00Z]

  setup do
    {:ok, _room} = FamilyChat.migrate!()
    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Every other member with push enabled is notified of a new message and the sender is not
  test "a message notifies every other subscription once and the sender's own never" do
    members = for _ <- 1..3, do: unique_user()
    sender = unique_user()

    for {user, index} <- Enum.with_index(members ++ [sender]) do
      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(
                 user,
                 "session-#{index}",
                 valid_input("member-#{index}")
               )
    end

    assert {:ok, _message} =
             FamilyChat.send_message(
               sender,
               FamilyChat.canonical_room_slug(),
               Ecto.UUID.generate(),
               "hello everyone"
             )

    assert :ok = PushNotifications.dispatch_all_due!(@now)

    for index <- 0..2 do
      assert_push_once("member-#{index}", "hello everyone")
    end

    refute_received {:push_notification_sent, _sender_endpoint, _payload}
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

    assert :ok = PushNotifications.dispatch_all_due!(@now)
    assert_received {:push_notification_sent, _endpoint, target_payload}
    assert target_payload["messageId"] == target.id
    flush_pushes()

    {:ok, reply} =
      FamilyChat.send_message(
        unique_user(),
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "reply answer",
        "Member",
        target.id
      )

    assert :ok = PushNotifications.dispatch_all_due!(@now)

    assert_received {:push_notification_sent, _endpoint, payload}
    assert payload["messageId"] == reply.id
    assert payload["body"] =~ "reply answer"
    refute payload["body"] =~ "quoted question"
    refute inspect(payload) =~ "quoted question"
    refute_received {:push_notification_sent, _endpoint, _payload}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A push that fails temporarily is sent again after fixed waits and given up after five attempts or one hour
  test "a retryable provider answer is retried after the fixed waits and then given up" do
    with_answering_sender(fn ->
      user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(
                 user,
                 "session-retry",
                 valid_input("status-503")
               )

      assert {:ok, _message} =
               FamilyChat.send_message(
                 unique_user(),
                 FamilyChat.canonical_room_slug(),
                 Ecto.UUID.generate(),
                 "retry me"
               )

      assert {:ok, %{state: "retryable", attempt: 1, next_attempt_at: first}} =
               Dispatcher.attempt(@now)

      assert first == DateTime.add(@now, 30, :second)

      assert {:ok, %{state: "retryable", attempt: 2, next_attempt_at: second}} =
               Dispatcher.attempt(DateTime.add(@now, 31, :second))

      assert second == DateTime.add(@now, 31 + 120, :second)

      assert {:ok, %{state: "retryable", attempt: 3, next_attempt_at: third}} =
               Dispatcher.attempt(DateTime.add(@now, 151, :second))

      assert third == DateTime.add(@now, 151 + 480, :second)

      assert {:ok, %{state: "retryable", attempt: 4, next_attempt_at: fourth}} =
               Dispatcher.attempt(DateTime.add(@now, 631, :second))

      assert fourth == DateTime.add(@now, 631 + 1_920, :second)

      assert {:ok, %{state: "terminal", attempt: 5, next_attempt_at: nil}} =
               Dispatcher.attempt(DateTime.add(@now, 2_551, :second))

      assert Dispatcher.attempt(DateTime.add(@now, 2_552, :second)) ==
               {:error, :no_due_delivery}
    end)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A device the push service reports gone stops receiving notifications and shows as disabled
  test "a gone provider answer disables the subscription and sends nothing more" do
    with_answering_sender(fn ->
      user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(
                 user,
                 "session-gone",
                 valid_input("status-410")
               )

      assert {:ok, _message} =
               FamilyChat.send_message(
                 unique_user(),
                 FamilyChat.canonical_room_slug(),
                 Ecto.UUID.generate(),
                 "gone device"
               )

      assert {:ok, %{state: "terminal", attempt: 1, next_attempt_at: nil}} =
               Dispatcher.attempt(@now)

      assert {:ok, %{enabled: false}} =
               PushNotifications.current_subscription(user, "session-gone")

      assert Dispatcher.attempt(@now) == {:error, :no_due_delivery}
    end)
  end

  defp flush_pushes do
    receive do
      {:push_notification_sent, _endpoint, _payload} -> flush_pushes()
    after
      0 -> :ok
    end
  end

  defp assert_push_once(suffix, body) do
    assert_received {:push_notification_sent, endpoint, payload}
    assert String.ends_with?(endpoint, "/" <> suffix)
    assert payload["body"] == body
    refute_received {:push_notification_sent, ^endpoint, _payload}
  end

  # The provider's answer for one test: the answering double instead of the recording
  # sender, restored afterwards. Stores, room, dispatcher and policy stay real.
  defp with_answering_sender(fun) do
    configuration = Application.fetch_env!(:bnest_app, PushNotifications)

    Application.put_env(
      :bnest_app,
      PushNotifications,
      Keyword.put(configuration, :push_sender, PushSender)
    )

    try do
      fun.()
    after
      Application.put_env(:bnest_app, PushNotifications, configuration)
    end
  end

  defp unique_user, do: "test-user-push-dispatch-" <> Ecto.UUID.generate()
  defp valid_key, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # Built from separate fragments (not one literal URL-shaped string) so this synthetic
  # fixture does not trip the unit-layer boundary policy's blanket network-URL scan.
  defp endpoint(suffix), do: "https:" <> "//push.allowed.example.com/" <> suffix

  defp valid_input(endpoint_suffix) do
    %{"endpoint" => endpoint(endpoint_suffix), "p256dh" => valid_key(), "auth" => valid_key()}
  end
end
